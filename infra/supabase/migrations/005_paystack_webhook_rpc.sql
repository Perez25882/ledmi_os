-- 005_paystack_webhook_rpc.sql
-- Paystack webhook RPCs: capture marker + atomic sale finalization.
-- These functions are intentionally self-contained and idempotent.
-- They depend on the core schema (payment_intents, inventory, carts, etc.)
-- created by migrations 001-004.

-- ============================================================
-- 1. process_payment_capture
-- Marks a payment intent as captured so safe_finalize_sale can run.
-- The unique constraint on payment_processing_markers makes this idempotent.
-- ============================================================
CREATE OR REPLACE FUNCTION process_payment_capture(
    p_payment_intent_id UUID,
    p_event_id UUID
) RETURNS BOOLEAN AS $func$
DECLARE
    v_pi RECORD;
BEGIN
    -- Lock the intent to serialize concurrent webhooks.
    SELECT * INTO v_pi
    FROM payment_intents WHERE id = p_payment_intent_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent % not found', p_payment_intent_id;
    END IF;

    -- The unique index on payment_processing_markers(payment_intent_id) ensures
    -- only the first caller wins; subsequent calls return false.
    BEGIN
        INSERT INTO payment_processing_markers (payment_intent_id, event_id)
        VALUES (p_payment_intent_id, p_event_id);
    EXCEPTION WHEN unique_violation THEN
        RETURN false;
    END;

    RETURN true;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. safe_finalize_sale
-- Atomic cross-table sale finalization with inventory decrement.
-- Attaches the capture marker itself, so a failure rolls back cleanly.
-- Returns the new sale UUID, or raises if the sale is already finalized.
-- ============================================================
CREATE OR REPLACE FUNCTION safe_finalize_sale(
    p_payment_intent_id UUID
) RETURNS UUID AS $func$
DECLARE
    v_pi RECORD;
    v_cart RECORD;
    v_item RECORD;
    v_branch_id UUID;
    v_subtotal DECIMAL := 0;
    v_old_qty INT;
    v_new_qty INT;
    v_payment_id UUID;
    v_invoice_id UUID;
    v_sale_id UUID;
    v_invoice_number VARCHAR;
    v_seq INT;
BEGIN
    -- Fetch and lock the intent.
    SELECT * INTO v_pi
    FROM payment_intents WHERE id = p_payment_intent_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent % not found', p_payment_intent_id;
    END IF;

    -- Idempotently attach the capture marker inside this transaction.
    BEGIN
        INSERT INTO payment_processing_markers (payment_intent_id, event_id)
        SELECT p_payment_intent_id, id
        FROM payment_events
        WHERE payment_intent_id = p_payment_intent_id
          AND event_type = 'payment_captured'
        LIMIT 1;
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM payment_processing_markers WHERE payment_intent_id = p_payment_intent_id
    ) THEN
        RAISE EXCEPTION 'No payment_captured event found for payment intent %', p_payment_intent_id;
    END IF;

    -- Lock the cart; fail loudly if it is missing or not active.
    SELECT * INTO v_cart FROM carts WHERE id = v_pi.cart_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cart % not found for payment intent %', v_pi.cart_id, p_payment_intent_id;
    END IF;

    IF v_cart.status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Cart % is not active. Already processed?', v_pi.cart_id;
    END IF;

    v_branch_id := v_cart.branch_id;

    -- Decrement branch inventory for each cart item and write immutable inventory logs.
    FOR v_item IN
        SELECT product_id, quantity, unit_price FROM cart_items
        WHERE cart_id = v_pi.cart_id ORDER BY product_id
    LOOP
        v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);

        SELECT quantity INTO v_old_qty FROM inventory
        WHERE product_id = v_item.product_id AND branch_id = v_branch_id
        FOR UPDATE;

        IF NOT FOUND OR v_old_qty < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock or missing inventory for product %', v_item.product_id;
        END IF;

        UPDATE inventory
        SET quantity = quantity - v_item.quantity, updated_at = NOW()
        WHERE product_id = v_item.product_id AND branch_id = v_branch_id
        RETURNING quantity INTO v_new_qty;

        INSERT INTO inventory_logs (
            business_id, branch_id, product_id, old_quantity, new_quantity,
            change_amount, reason, actor_id
        ) VALUES (
            v_pi.business_id, v_branch_id, v_item.product_id, v_old_qty, v_new_qty,
            -v_item.quantity, 'SALE_EVENT', v_pi.created_by
        );
    END LOOP;

    -- Validate the cart amount matches the intent amount before mutating anything else.
    IF TRUNC(v_subtotal, 2) != TRUNC(v_pi.amount, 2) THEN
        RAISE EXCEPTION 'Cart amount (%) does not match payment intent amount (%)', v_subtotal, v_pi.amount;
    END IF;

    -- Create the legacy payment record. We deliberately NEVER store full PAN or CVV.
    -- Paystack Ghana uses the same charge channel for cards and mobile money;
    -- a channel column on payment_intents should be added in a later migration.
    INSERT INTO payments (
        business_id, cashier_id, method, amount, status, provider_reference
    ) VALUES (
        v_pi.business_id, v_pi.created_by, 'CARD', v_pi.amount, 'SUCCESS', v_pi.provider_reference
    ) RETURNING id INTO v_payment_id;

    -- Link the legacy payment and mark the intent completed.
    UPDATE payment_intents
    SET legacy_payment_id = v_payment_id, status = 'completed'
    WHERE id = p_payment_intent_id;

    -- Generate a collision-resistant invoice number scoped by branch.
    SELECT COALESCE(MAX(CAST(SPLIT_PART(invoice_number, '-', 4) AS INT)), 0) + 1
    INTO v_seq FROM invoices
    WHERE branch_id = v_branch_id
      AND invoice_number LIKE 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '%';

    v_invoice_number := 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 6, '0');

    INSERT INTO invoices (
        business_id, branch_id, invoice_number, cashier_id, payment_id, subtotal, tax, total
    ) VALUES (
        v_pi.business_id, v_branch_id, v_invoice_number, v_pi.created_by, v_payment_id,
        v_subtotal, 0, v_subtotal
    ) RETURNING id INTO v_invoice_id;

    -- Create the sale.
    INSERT INTO sales (business_id, branch_id, invoice_id, payment_id, cashier_id)
    VALUES (v_pi.business_id, v_branch_id, v_invoice_id, v_payment_id, v_pi.created_by)
    RETURNING id INTO v_sale_id;

    -- Persist line items.
    INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
    SELECT v_sale_id, product_id, quantity, unit_price, (quantity * unit_price)
    FROM cart_items WHERE cart_id = v_pi.cart_id;

    -- Mark the cart completed.
    UPDATE carts
    SET status = 'COMPLETED', updated_at = NOW()
    WHERE id = v_pi.cart_id;

    RETURN v_sale_id;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;
