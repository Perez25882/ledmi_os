-- 006_checkout_rpc.sql
-- LedgerMind OS Phase 2 — POS checkout and payment-intent RPCs.
--
-- Provides:
--   * process_checkout_cash() — idempotent cash sale, inventory decrement, audit trail.
--   * create_checkout_intent() — creates a cart + Paystack payment intent for card/MoMo.
--   * get_branch_catalog() / get_catalog_delta() — server-side full/delta sync helpers.
--
-- Notes:
--   * All functions are SECURITY DEFINER and validate the caller belongs to the business.
--   * Inventory is keyed per branch (product_id, branch_id) after 002_branch_model.sql.
--   * Legacy `payments` table is updated so existing receipt queries keep working.
--   * Payment events are appended for every checkout, including cash.

-- ============================================================
-- 1. Cash checkout
-- ============================================================

-- p_total_amount is in pesewas (integer minor units); tables store GHS decimals.
DROP FUNCTION IF EXISTS process_checkout_cash(UUID, UUID, UUID, UUID, JSONB, DECIMAL(12, 2));
CREATE OR REPLACE FUNCTION process_checkout_cash(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_idempotency_key UUID,
    p_items JSONB,
    p_total_amount BIGINT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cart_id UUID;
    v_intent_id UUID;
    v_payment_id UUID;
    v_invoice_id UUID;
    v_sale_id UUID;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price DECIMAL(12, 2);
    v_computed_total DECIMAL(12, 2) := 0;
    v_existing_sale_id UUID;
    v_invoice_number VARCHAR(100);
BEGIN
    -- Caller must be the authenticated cashier and belong to the business.
    IF v_user_id IS NULL OR v_user_id != p_cashier_id THEN
        RAISE EXCEPTION 'Caller must be the cashier';
    END IF;

    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Cashier does not belong to business';
    END IF;

    -- Branch must be owned by the business and active.
    IF NOT EXISTS (
        SELECT 1
        FROM branches
        WHERE id = p_branch_id
          AND business_id = p_business_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Invalid branch';
    END IF;

    -- Idempotency: if a sale already exists for this key, return it.
    SELECT s.id
    INTO v_existing_sale_id
    FROM payment_intents pi
    LEFT JOIN sales s ON s.payment_id = pi.legacy_payment_id
    WHERE pi.idempotency_key = p_idempotency_key
      AND pi.business_id = p_business_id
    LIMIT 1;

    IF v_existing_sale_id IS NOT NULL THEN
        RETURN v_existing_sale_id;
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    -- Validate items, resolve current prices, and compute total.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid item: %', v_item;
        END IF;

        SELECT selling_price
        INTO v_unit_price
        FROM products
        WHERE id = v_product_id
          AND business_id = p_business_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found', v_product_id;
        END IF;

        v_computed_total := v_computed_total + (v_unit_price * v_quantity);

        -- Prevent oversell at checkout time.
        IF NOT EXISTS (
            SELECT 1
            FROM inventory
            WHERE product_id = v_product_id
              AND branch_id = p_branch_id
              AND quantity >= v_quantity
        ) THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_product_id;
        END IF;
    END LOOP;

    -- Compare in pesewas; v_computed_total is GHS decimals, p_total_amount is pesewas.
    IF ROUND(v_computed_total * 100)::bigint != p_total_amount THEN
        RAISE EXCEPTION 'Total amount mismatch: computed % pesewas, received %', ROUND(v_computed_total * 100)::bigint, p_total_amount;
    END IF;

    -- Persist cart.
    INSERT INTO carts (business_id, branch_id, cashier_id, status)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'CHECKED_OUT')
    RETURNING id INTO v_cart_id;

    -- Persist cart items.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (
            SELECT selling_price
            FROM products
            WHERE id = v_product_id AND business_id = p_business_id
        );

        INSERT INTO cart_items (cart_id, product_id, quantity, unit_price)
        VALUES (v_cart_id, v_product_id, v_quantity, v_unit_price);
    END LOOP;

    -- Create a completed payment intent for the cash sale.
    INSERT INTO payment_intents (
        business_id, cart_id, amount, currency, idempotency_key,
        provider, status, created_by
    )
    VALUES (
        p_business_id, v_cart_id, v_computed_total, 'GHS', p_idempotency_key,
        'cash', 'completed', p_cashier_id
    )
    RETURNING id INTO v_intent_id;

    -- Append the capture event to the immutable ledger.
    INSERT INTO payment_events (payment_intent_id, event_type, provider, occurred_at)
    VALUES (v_intent_id, 'payment_captured', 'cash', NOW());

    -- Keep the legacy payment table in sync for receipts and dashboards.
    INSERT INTO payments (business_id, cashier_id, method, amount, status, provider_reference)
    VALUES (p_business_id, p_cashier_id, 'cash', v_computed_total, 'COMPLETED', p_idempotency_key::text)
    RETURNING id INTO v_payment_id;

    UPDATE payment_intents
    SET legacy_payment_id = v_payment_id
    WHERE id = v_intent_id;

    -- Invoice and sale records.
    v_invoice_number := 'INV-' || to_char(NOW(), 'YYYYMMDD') || '-' || substr(v_intent_id::text, 1, 8);

    INSERT INTO invoices (business_id, branch_id, invoice_number, cashier_id, payment_id, subtotal, tax, total)
    VALUES (p_business_id, p_branch_id, v_invoice_number, p_cashier_id, v_payment_id, v_computed_total, 0, v_computed_total)
    RETURNING id INTO v_invoice_id;

    INSERT INTO sales (business_id, branch_id, invoice_id, payment_id, cashier_id)
    VALUES (p_business_id, p_branch_id, v_invoice_id, v_payment_id, p_cashier_id)
    RETURNING id INTO v_sale_id;

    -- Decrement stock and write audit logs.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (
            SELECT selling_price
            FROM products
            WHERE id = v_product_id AND business_id = p_business_id
        );

        INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
        VALUES (v_sale_id, v_product_id, v_quantity, v_unit_price, v_unit_price * v_quantity);

        UPDATE inventory
        SET quantity = quantity - v_quantity
        WHERE product_id = v_product_id AND branch_id = p_branch_id;

        INSERT INTO inventory_logs (business_id, branch_id, product_id, old_quantity, new_quantity, change_amount, reason, actor_id)
        SELECT business_id, branch_id, product_id, quantity + v_quantity, quantity, -v_quantity, 'sale', p_cashier_id
        FROM inventory
        WHERE product_id = v_product_id AND branch_id = p_branch_id;
    END LOOP;

    INSERT INTO activity_logs (business_id, actor_id, action, entity_table, entity_id, metadata)
    VALUES (
        p_business_id, p_cashier_id, 'sale_completed', 'sales', v_sale_id,
        jsonb_build_object('payment_intent_id', v_intent_id, 'total', v_computed_total, 'method', 'cash')
    );

    RETURN v_sale_id;
END;
$$;


-- ============================================================
-- 2. Payment intent creation for Paystack card / MoMo
-- ============================================================

DROP FUNCTION IF EXISTS create_checkout_intent(UUID, UUID, UUID, UUID, JSONB, DECIMAL(12, 2), TEXT);
CREATE OR REPLACE FUNCTION create_checkout_intent(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_idempotency_key UUID,
    p_items JSONB,
    p_total_amount BIGINT,
    p_method TEXT DEFAULT 'card'
) RETURNS TABLE(intent_id UUID, cart_id UUID, reference TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cart_id UUID;
    v_intent_id UUID;
    v_reference TEXT;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price DECIMAL(12, 2);
    v_computed_total DECIMAL(12, 2) := 0;
BEGIN
    IF v_user_id IS NULL OR v_user_id != p_cashier_id THEN
        RAISE EXCEPTION 'Caller must be the cashier';
    END IF;

    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Cashier does not belong to business';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM branches
        WHERE id = p_branch_id
          AND business_id = p_business_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Invalid branch';
    END IF;

    -- Idempotency: return existing intent if the caller retries.
    SELECT pi.id, pi.cart_id, pi.provider_reference
    INTO v_intent_id, v_cart_id, v_reference
    FROM payment_intents pi
    WHERE pi.idempotency_key = p_idempotency_key
      AND pi.business_id = p_business_id;

    IF v_intent_id IS NOT NULL THEN
        RETURN QUERY SELECT v_intent_id, v_cart_id, v_reference;
        RETURN;
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid item: %', v_item;
        END IF;

        SELECT selling_price
        INTO v_unit_price
        FROM products
        WHERE id = v_product_id
          AND business_id = p_business_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found', v_product_id;
        END IF;

        v_computed_total := v_computed_total + (v_unit_price * v_quantity);

        IF NOT EXISTS (
            SELECT 1
            FROM inventory
            WHERE product_id = v_product_id
              AND branch_id = p_branch_id
              AND quantity >= v_quantity
        ) THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_product_id;
        END IF;
    END LOOP;

    -- Compare in pesewas; v_computed_total is GHS decimals, p_total_amount is pesewas.
    IF ROUND(v_computed_total * 100)::bigint != p_total_amount THEN
        RAISE EXCEPTION 'Total amount mismatch: computed % pesewas, received %', ROUND(v_computed_total * 100)::bigint, p_total_amount;
    END IF;

    INSERT INTO carts (business_id, branch_id, cashier_id, status)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'ACTIVE')
    RETURNING id INTO v_cart_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (
            SELECT selling_price
            FROM products
            WHERE id = v_product_id AND business_id = p_business_id
        );

        INSERT INTO cart_items (cart_id, product_id, quantity, unit_price)
        VALUES (v_cart_id, v_product_id, v_quantity, v_unit_price);
    END LOOP;

    v_reference := p_idempotency_key::text;

    INSERT INTO payment_intents (
        business_id, cart_id, amount, currency, idempotency_key,
        provider, provider_reference, status, created_by
    )
    VALUES (
        p_business_id, v_cart_id, v_computed_total, 'GHS', p_idempotency_key,
        'paystack', v_reference, 'initiated', p_cashier_id
    )
    RETURNING id INTO v_intent_id;

    RETURN QUERY SELECT v_intent_id, v_cart_id, v_reference;
END;
$$;


-- ============================================================
-- 3. Server-side catalog helpers for Flutter sync
-- ============================================================

CREATE OR REPLACE FUNCTION get_branch_catalog(
    p_business_id UUID,
    p_branch_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN jsonb_build_object(
        'categories', COALESCE(
            (SELECT jsonb_agg(to_jsonb(c))
             FROM categories c
             WHERE c.business_id = p_business_id AND c.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'products', COALESCE(
            (SELECT jsonb_agg(to_jsonb(p))
             FROM products p
             WHERE p.business_id = p_business_id AND p.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'inventory', COALESCE(
            (SELECT jsonb_agg(to_jsonb(i))
             FROM inventory i
             WHERE i.business_id = p_business_id AND i.branch_id = p_branch_id),
            '[]'::jsonb
        )
    );
END;
$$;


CREATE OR REPLACE FUNCTION get_catalog_delta(
    p_business_id UUID,
    p_branch_id UUID,
    p_since TIMESTAMPTZ
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN jsonb_build_object(
        'categories', COALESCE(
            (SELECT jsonb_agg(to_jsonb(c))
             FROM categories c
             WHERE c.business_id = p_business_id
               AND c.updated_at > p_since
               AND c.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'products', COALESCE(
            (SELECT jsonb_agg(to_jsonb(p))
             FROM products p
             WHERE p.business_id = p_business_id
               AND p.updated_at > p_since
               AND p.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'inventory', COALESCE(
            (SELECT jsonb_agg(to_jsonb(i))
             FROM inventory i
             WHERE i.business_id = p_business_id
               AND i.branch_id = p_branch_id
               AND i.updated_at > p_since),
            '[]'::jsonb
        ),
        'since', p_since
    );
END;
$$;
