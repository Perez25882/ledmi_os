-- 03_functions_triggers.sql
-- Unified Retail OS - Triggers and RPC Functions

-- ============================================================
-- 1. updated_at Trigger Helper
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $func$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;


-- ============================================================
-- 2. Legacy Functions (Preserved)
-- ============================================================

-- Atomic Checkout: confirms a cart, deducts inventory, and records the sale transactionally.
CREATE OR REPLACE FUNCTION process_checkout(
    p_cart_id UUID,
    p_payment_method VARCHAR,
    p_amount DECIMAL,
    p_provider_ref VARCHAR DEFAULT NULL,
    p_card_last4 VARCHAR DEFAULT NULL,
    p_card_brand VARCHAR DEFAULT NULL
) RETURNS UUID AS $func$
DECLARE
    v_business_id UUID;
    v_cashier_id UUID;
    v_cart_status VARCHAR;
    v_payment_id UUID;
    v_invoice_id UUID;
    v_sale_id UUID;
    v_item RECORD;
    v_invoice_number VARCHAR;
    v_subtotal DECIMAL := 0;
    v_old_qty INT;
    v_new_qty INT;
    v_seq INT;
BEGIN
    -- Validate payment method
    IF p_payment_method NOT IN ('CASH', 'CARD', 'MOMO', 'BANK_TRANSFER') THEN
        RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
    END IF;

    SELECT business_id, cashier_id, status
    INTO v_business_id, v_cashier_id, v_cart_status
    FROM carts WHERE id = p_cart_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cart % not found', p_cart_id;
    END IF;

    IF v_cart_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Cart is already processed or abandoned';
    END IF;

    IF p_payment_method = 'CARD' AND p_provider_ref IS NULL THEN
        RAISE EXCEPTION 'Card payment requires provider reference';
    END IF;

    -- Lock and process cart items to prevent race conditions
    -- (phantom read protection via explicit lock ordering)
    FOR v_item IN
        SELECT product_id, quantity, unit_price FROM cart_items
        WHERE cart_id = p_cart_id ORDER BY product_id FOR UPDATE OF cart_items
    LOOP
        v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);

        SELECT quantity INTO v_old_qty FROM inventory
        WHERE product_id = v_item.product_id AND business_id = v_business_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Inventory record missing for product %', v_item.product_id;
        END IF;

        IF v_old_qty < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_item.product_id;
        END IF;

        UPDATE inventory SET quantity = quantity - v_item.quantity, updated_at = NOW()
        WHERE product_id = v_item.product_id AND business_id = v_business_id
        RETURNING quantity INTO v_new_qty;

        INSERT INTO inventory_logs (business_id, product_id, old_quantity, new_quantity, change_amount, reason, actor_id)
        VALUES (v_business_id, v_item.product_id, v_old_qty, v_new_qty, -v_item.quantity, 'SALE', v_cashier_id);
    END LOOP;

    IF TRUNC(v_subtotal, 2) != TRUNC(p_amount, 2) THEN
        RAISE EXCEPTION 'Payment amount mismatch. Expected: %, Received: %', v_subtotal, p_amount;
    END IF;

    INSERT INTO payments (business_id, cashier_id, method, amount, status, provider_reference, card_last4, card_brand)
    VALUES (v_business_id, v_cashier_id, p_payment_method, p_amount, 'SUCCESS', p_provider_ref, p_card_last4, p_card_brand)
    RETURNING id INTO v_payment_id;

    -- Use sequence-based invoice number to prevent collisions
    SELECT COALESCE(MAX(CAST(SPLIT_PART(invoice_number, '-', 4) AS INT)), 0) + 1
    INTO v_seq FROM invoices
    WHERE invoice_number LIKE 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '%';

    v_invoice_number := 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 6, '0');

    INSERT INTO invoices (business_id, invoice_number, cashier_id, payment_id, subtotal, tax, total)
    VALUES (v_business_id, v_invoice_number, v_cashier_id, v_payment_id, v_subtotal, 0, v_subtotal)
    RETURNING id INTO v_invoice_id;

    INSERT INTO sales (business_id, invoice_id, payment_id, cashier_id)
    VALUES (v_business_id, v_invoice_id, v_payment_id, v_cashier_id)
    RETURNING id INTO v_sale_id;

    INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
    SELECT v_sale_id, product_id, quantity, unit_price, (quantity * unit_price)
    FROM cart_items WHERE cart_id = p_cart_id;

    UPDATE carts SET status = 'COMPLETED', updated_at = NOW() WHERE id = p_cart_id;

    RETURN v_invoice_id;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- Legacy convenience wrappers
CREATE OR REPLACE FUNCTION process_cash_sale(p_cart_id UUID, p_amount DECIMAL)
RETURNS UUID AS $func$
BEGIN
    RETURN process_checkout(p_cart_id, 'CASH', p_amount);
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION process_momo_sale(p_cart_id UUID, p_amount DECIMAL, p_ref VARCHAR DEFAULT NULL)
RETURNS UUID AS $func$
BEGIN
    RETURN process_checkout(p_cart_id, 'MOMO', p_amount, p_ref);
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION process_card_sale(
    p_cart_id UUID,
    p_amount DECIMAL,
    p_ref VARCHAR,
    p_last4 VARCHAR,
    p_brand VARCHAR
) RETURNS UUID AS $func$
BEGIN
    RETURN process_checkout(p_cart_id, 'CARD', p_amount, p_ref, p_last4, p_brand);
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION prune_abandoned_carts()
RETURNS void AS $func$
BEGIN
    DELETE FROM carts WHERE status = 'ACTIVE' AND created_at < NOW() - INTERVAL '24 hours';
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 3. Event-Sourced Payment Functions
-- ============================================================

-- 3A. get_payment_status
-- Derives the current payment state from the immutable event ledger.
CREATE OR REPLACE FUNCTION get_payment_status(p_payment_intent_id UUID)
RETURNS VARCHAR(50) AS $func$
DECLARE
    v_captured BOOLEAN := false;
    v_refunded_amount DECIMAL := 0;
    v_amount DECIMAL;
    v_latest_fail TIMESTAMPTZ;
    v_latest_cancel TIMESTAMPTZ;
    v_latest_chargeback TIMESTAMPTZ;
BEGIN
    SELECT amount INTO v_amount FROM payment_intents WHERE id = p_payment_intent_id;

    IF v_amount IS NULL THEN
        RETURN 'unknown';
    END IF;

    -- Check for chargeback
    SELECT MAX(occurred_at) INTO v_latest_chargeback
    FROM payment_events
    WHERE payment_intent_id = p_payment_intent_id
    AND event_type = 'chargeback_created';

    IF v_latest_chargeback IS NOT NULL THEN
        RETURN 'disputed';
    END IF;

    -- Check for refunds
    SELECT COALESCE(SUM((payload->>'amount')::DECIMAL), 0) INTO v_refunded_amount
    FROM payment_events
    WHERE payment_intent_id = p_payment_intent_id
    AND event_type IN ('payment_refunded', 'payment_partially_refunded');

    IF v_refunded_amount >= v_amount THEN
        RETURN 'refunded';
    ELSIF v_refunded_amount > 0 THEN
        RETURN 'partially_refunded';
    END IF;

    -- Check for captured
    SELECT EXISTS (
        SELECT 1 FROM payment_events
        WHERE payment_intent_id = p_payment_intent_id
        AND event_type = 'payment_captured'
    ) INTO v_captured;

    IF v_captured THEN
        RETURN 'captured';
    END IF;

    -- Check for failed or cancelled
    SELECT MAX(occurred_at) INTO v_latest_fail
    FROM payment_events WHERE payment_intent_id = p_payment_intent_id
    AND event_type = 'payment_failed';

    SELECT MAX(occurred_at) INTO v_latest_cancel
    FROM payment_events WHERE payment_intent_id = p_payment_intent_id
    AND event_type = 'payment_cancelled';

    IF COALESCE(v_latest_fail, '1900-01-01') > COALESCE(v_latest_cancel, '1900-01-01') THEN
        RETURN 'failed';
    ELSIF v_latest_cancel IS NOT NULL THEN
        RETURN 'cancelled';
    END IF;

    -- Check for authorized
    IF EXISTS (SELECT 1 FROM payment_events WHERE payment_intent_id = p_payment_intent_id AND event_type = 'payment_authorized') THEN
        RETURN 'authorized';
    END IF;

    -- Check for initiated
    IF EXISTS (SELECT 1 FROM payment_events WHERE payment_intent_id = p_payment_intent_id AND event_type = 'payment_initiated') THEN
        RETURN 'initiated';
    END IF;

    RETURN 'unknown';
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3B. create_payment_intent
CREATE OR REPLACE FUNCTION create_payment_intent(
    p_idempotency_key UUID,
    p_business_id UUID,
    p_cart_id UUID,
    p_amount DECIMAL,
    p_currency VARCHAR(3) DEFAULT 'GHS',
    p_provider VARCHAR(50) DEFAULT 'paystack',
    p_customer_reference VARCHAR(255) DEFAULT NULL
) RETURNS UUID AS $func$
DECLARE
    v_intent_id UUID;
BEGIN
    INSERT INTO payment_intents (
        business_id, cart_id, amount, currency,
        idempotency_key, provider, customer_reference, created_by, status
    )
    VALUES (
        p_business_id, p_cart_id, p_amount, COALESCE(p_currency, 'GHS'),
        p_idempotency_key, COALESCE(p_provider, 'paystack'), p_customer_reference,
        COALESCE(auth.uid(), uuid_nil()), 'initiated'
    )
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING id INTO v_intent_id;

    IF v_intent_id IS NULL THEN
        SELECT id INTO v_intent_id FROM payment_intents WHERE idempotency_key = p_idempotency_key;
    END IF;

    RETURN v_intent_id;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3C. record_payment_event
CREATE OR REPLACE FUNCTION record_payment_event(
    p_payment_intent_id UUID,
    p_event_type VARCHAR(50),
    p_provider VARCHAR(50),
    p_provider_event_id VARCHAR(255) DEFAULT NULL,
    p_provider_reference VARCHAR(255) DEFAULT NULL,
    p_payload JSONB DEFAULT NULL,
    p_occurred_at TIMESTAMPTZ DEFAULT NULL
) RETURNS TABLE (out_event_id UUID, out_is_new BOOLEAN) AS $func$
DECLARE
    v_event_id UUID;
    v_is_new BOOLEAN := true;
BEGIN
    INSERT INTO payment_events (
        payment_intent_id, event_type, provider,
        provider_event_id, provider_reference, payload, occurred_at
    ) VALUES (
        p_payment_intent_id, p_event_type, p_provider,
        p_provider_event_id, p_provider_reference,
        COALESCE(p_payload, '{}'::jsonb), COALESCE(p_occurred_at, NOW())
    )
    ON CONFLICT (provider, provider_event_id) WHERE provider_event_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_event_id;

    IF v_event_id IS NULL AND p_provider_event_id IS NOT NULL THEN
        -- Duplicate event: return existing
        SELECT id INTO v_event_id
        FROM payment_events
        WHERE provider = p_provider AND provider_event_id = p_provider_event_id;
        v_is_new := false;
    END IF;

    RETURN QUERY SELECT v_event_id, v_is_new;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3D. process_payment_capture
-- One-shot side-effect handler. Prevents double-processing via marker table.
-- Returns true if the event was processed, false if already handled.
CREATE OR REPLACE FUNCTION process_payment_capture(
    p_payment_intent_id UUID,
    p_event_id UUID
) RETURNS BOOLEAN AS $func$
DECLARE
    v_pi RECORD;
BEGIN
    -- Lock the intent and check if already processed
    SELECT * INTO v_pi
    FROM payment_intents WHERE id = p_payment_intent_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent % not found', p_payment_intent_id;
    END IF;

    -- Attempt to mark; if already marked, this unique constraint will fail
    BEGIN
        INSERT INTO payment_processing_markers (payment_intent_id, event_id)
        VALUES (p_payment_intent_id, p_event_id);
    EXCEPTION WHEN unique_violation THEN
        RETURN false; -- Already processed
    END;

    RETURN true;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3E. safe_finalize_sale
-- Atomic cross-table sale finalization with inventory reduction.
-- Only runs after process_payment_capture has attached the processing marker.
-- Returns the new sale UUID on success.
CREATE OR REPLACE FUNCTION safe_finalize_sale(
    p_payment_intent_id UUID
) RETURNS UUID AS $func$
DECLARE
    v_pi RECORD;
    v_cart RECORD;
    v_item RECORD;
    v_subtotal DECIMAL := 0;
    v_old_qty INT;
    v_new_qty INT;
    v_payment_id UUID;
    v_invoice_id UUID;
    v_sale_id UUID;
    v_invoice_number VARCHAR;
    v_seq INT;
BEGIN
    -- Fetch and lock the intent
    SELECT * INTO v_pi
    FROM payment_intents WHERE id = p_payment_intent_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent % not found', p_payment_intent_id;
    END IF;

    -- Ensure the processing marker exists
    IF NOT EXISTS (SELECT 1 FROM payment_processing_markers WHERE payment_intent_id = p_payment_intent_id) THEN
        RAISE EXCEPTION 'Payment intent % has not been marked as captured. Call process_payment_capture first.', p_payment_intent_id;
    END IF;

    -- Lock the cart
    SELECT * INTO v_cart FROM carts WHERE id = v_pi.cart_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cart % not found for payment intent %', v_pi.cart_id, p_payment_intent_id;
    END IF;

    IF v_cart.status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Cart % is not active. Already processed?', v_pi.cart_id;
    END IF;

    -- Reduce inventory for each item
    FOR v_item IN
        SELECT product_id, quantity, unit_price FROM cart_items
        WHERE cart_id = v_pi.cart_id ORDER BY product_id
    LOOP
        v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);

        SELECT quantity INTO v_old_qty FROM inventory
        WHERE product_id = v_item.product_id AND business_id = v_pi.business_id
        FOR UPDATE;

        IF NOT FOUND OR v_old_qty < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock or missing inventory for product %', v_item.product_id;
        END IF;

        UPDATE inventory SET quantity = quantity - v_item.quantity, updated_at = NOW()
        WHERE product_id = v_item.product_id AND business_id = v_pi.business_id
        RETURNING quantity INTO v_new_qty;

        INSERT INTO inventory_logs (business_id, product_id, old_quantity, new_quantity, change_amount, reason, actor_id)
        VALUES (v_pi.business_id, v_item.product_id, v_old_qty, v_new_qty, -v_item.quantity, 'SALE_EVENT', v_pi.created_by);
    END LOOP;

    -- Validate cart amount matches intent amount
    IF TRUNC(v_subtotal, 2) != TRUNC(v_pi.amount, 2) THEN
        RAISE EXCEPTION 'Cart amount (%) does not match payment intent amount (%)', v_subtotal, v_pi.amount;
    END IF;

    -- Create legacy payment record
    INSERT INTO payments (business_id, cashier_id, method, amount, status, provider_reference)
    VALUES (v_pi.business_id, v_pi.created_by, 'CARD', v_pi.amount, 'SUCCESS', v_pi.provider_reference)
    RETURNING id INTO v_payment_id;

    -- Link legacy payment
    UPDATE payment_intents SET legacy_payment_id = v_payment_id, status = 'completed'
    WHERE id = p_payment_intent_id;

    -- Use sequence-based invoice number to prevent collisions
    SELECT COALESCE(MAX(CAST(SPLIT_PART(invoice_number, '-', 4) AS INT)), 0) + 1
    INTO v_seq FROM invoices
    WHERE invoice_number LIKE 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '%';

    v_invoice_number := 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 6, '0');

    INSERT INTO invoices (business_id, invoice_number, cashier_id, payment_id, subtotal, tax, total)
    VALUES (v_pi.business_id, v_invoice_number, v_pi.created_by, v_payment_id, v_subtotal, 0, v_subtotal)
    RETURNING id INTO v_invoice_id;

    -- Create sale
    INSERT INTO sales (business_id, invoice_id, payment_id, cashier_id)
    VALUES (v_pi.business_id, v_invoice_id, v_payment_id, v_pi.created_by)
    RETURNING id INTO v_sale_id;

    INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
    SELECT v_sale_id, product_id, quantity, unit_price, (quantity * unit_price)
    FROM cart_items WHERE cart_id = v_pi.cart_id;

    -- Mark cart completed
    UPDATE carts SET status = 'COMPLETED', updated_at = NOW() WHERE id = v_pi.cart_id;

    -- CRITICAL FIX: Return the sale_id so caller knows success
    RETURN v_sale_id;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 4. Payment Projection Trigger
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_update_payment_intent_status()
RETURNS TRIGGER AS $func$
DECLARE
    v_new_status VARCHAR(50);
BEGIN
    v_new_status := get_payment_status(NEW.payment_intent_id);

    UPDATE payment_intents
    SET status = v_new_status, updated_at = NOW()
    WHERE id = NEW.payment_intent_id
      AND status IS DISTINCT FROM v_new_status;

    RETURN NEW;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_update_payment_intent_status
    AFTER INSERT ON payment_events
    FOR EACH ROW
    EXECUTE FUNCTION trigger_update_payment_intent_status();


-- ============================================================
-- 5. Payment Events Immutability Guard
-- ============================================================

CREATE OR REPLACE FUNCTION prevent_payment_events_mutation()
RETURNS TRIGGER AS $func$
DECLARE
    v_intent_id UUID;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_intent_id := NEW.payment_intent_id;
    ELSE
        v_intent_id := OLD.payment_intent_id;
    END IF;
    RAISE EXCEPTION 'payment_events table is append-only. Mutations (UPDATE/DELETE) are forbidden. Intent ID: %', v_intent_id;
END;
$func$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_update_payment_events
    BEFORE UPDATE ON payment_events
    FOR EACH ROW
    EXECUTE FUNCTION prevent_payment_events_mutation();

CREATE TRIGGER trg_prevent_delete_payment_events
    BEFORE DELETE ON payment_events
    FOR EACH ROW
    EXECUTE FUNCTION prevent_payment_events_mutation();


-- ============================================================
-- 6. Auto-Process Capture on payment_captured Event
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_auto_process_capture()
RETURNS TRIGGER AS $func$
DECLARE
    v_pi_amount DECIMAL;
BEGIN
    -- Quick early-exit for non-capture events.
    IF NEW.event_type != 'payment_captured' THEN
        RETURN NEW;
    END IF;

    -- Safety: ensure the intent exists
    SELECT amount INTO v_pi_amount FROM payment_intents WHERE id = NEW.payment_intent_id;
    IF v_pi_amount IS NULL THEN
        RAISE EXCEPTION 'Auto-capture failed: payment intent % not found.', NEW.payment_intent_id;
    END IF;

    -- Insert the processing marker if not already present.
    BEGIN
        INSERT INTO payment_processing_markers (payment_intent_id, event_id)
        VALUES (NEW.payment_intent_id, NEW.id);
    EXCEPTION WHEN unique_violation THEN
        -- Already processed, nothing to do.
        NULL;
    END;

    RETURN NEW;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_auto_process_capture
    AFTER INSERT ON payment_events
    FOR EACH ROW
    EXECUTE FUNCTION trigger_auto_process_capture();


-- ============================================================
-- 7. Cleanup Functions
-- ============================================================

CREATE OR REPLACE FUNCTION prune_abandoned_payment_intents(p_max_age INTERVAL DEFAULT '24 hours')
RETURNS void AS $func$
BEGIN
    DELETE FROM payment_intents pi
    WHERE pi.status = 'initiated'
      AND pi.created_at < NOW() - p_max_age
      AND NOT EXISTS (
          SELECT 1 FROM payment_events pe
          WHERE pe.payment_intent_id = pi.id
          AND pe.event_type IN ('payment_captured', 'payment_failed', 'payment_refunded',
                                  'payment_partially_refunded', 'chargeback_created',
                                  'payment_cancelled')
      );
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;
