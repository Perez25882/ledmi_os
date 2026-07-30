-- 019_quick_sale_rpc.sql
-- LedgerMind OS — Quick Sale support in checkout RPCs.
--
-- Updates process_checkout_cash() and create_checkout_intent() so that line
-- items flagged `is_quick_sale = true` are:
--   * Priced from the client-supplied `unit_price` (no products-table lookup).
--   * Exempt from inventory stock checks and stock decrements.
--   * Persisted to sale_items / cart_items with `is_quick_sale` and
--     `quick_sale_name` (columns added in 017).
--
-- Catalog items continue to behave exactly as before: price is resolved from
-- the products table, inventory is validated and decremented.
--
-- Notes:
--   * Uses CREATE OR REPLACE FUNCTION so the migration is idempotent.
--   * The DROP FUNCTION IF EXISTS guards keep the signature stable for
--     re-runs (the argument types are unchanged).
--   * p_items JSONB rows may now carry optional keys:
--       is_quick_sale  BOOLEAN  (default false)
--       quick_sale_name TEXT    (only present when is_quick_sale is true)

-- ============================================================
-- 0. Make product_id nullable on sale_items and cart_items
--    so quick-sale rows (no catalog product) can be inserted.
-- ============================================================

ALTER TABLE sale_items ALTER COLUMN product_id DROP NOT NULL;
ALTER TABLE cart_items ALTER COLUMN product_id DROP NOT NULL;

-- ============================================================
-- 1. process_checkout_cash — updated for quick sale
-- ============================================================

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
    v_is_quick_sale BOOLEAN;
    v_quick_sale_name TEXT;
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

    -- Validate items, resolve prices, and compute total.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_quantity := (v_item->>'quantity')::INT;
        v_is_quick_sale := COALESCE((v_item->>'is_quick_sale')::BOOLEAN, false);

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid item: %', v_item;
        END IF;

        IF v_is_quick_sale THEN
            -- Quick sale: use the client-supplied price; no product/inventory lookup.
            v_unit_price := (v_item->>'unit_price')::DECIMAL(12, 2);
            IF v_unit_price IS NULL OR v_unit_price < 0 THEN
                RAISE EXCEPTION 'Quick sale item missing unit_price: %', v_item;
            END IF;
        ELSE
            -- Catalog item: resolve price from the products table.
            v_product_id := (v_item->>'product_id')::UUID;

            IF v_product_id IS NULL THEN
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
        END IF;

        v_computed_total := v_computed_total + (v_unit_price * v_quantity);
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
        v_quantity := (v_item->>'quantity')::INT;
        v_is_quick_sale := COALESCE((v_item->>'is_quick_sale')::BOOLEAN, false);

        IF v_is_quick_sale THEN
            v_unit_price := (v_item->>'unit_price')::DECIMAL(12, 2);
            v_product_id := NULL;
        ELSE
            v_product_id := (v_item->>'product_id')::UUID;
            v_unit_price := (
                SELECT selling_price
                FROM products
                WHERE id = v_product_id AND business_id = p_business_id
            );
        END IF;

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

    -- Decrement stock and write audit logs (catalog items only).
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_quantity := (v_item->>'quantity')::INT;
        v_is_quick_sale := COALESCE((v_item->>'is_quick_sale')::BOOLEAN, false);
        v_quick_sale_name := v_item->>'quick_sale_name';

        IF v_is_quick_sale THEN
            v_unit_price := (v_item->>'unit_price')::DECIMAL(12, 2);
            -- Quick sale: no product_id, no inventory decrement.
            INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal, is_quick_sale, quick_sale_name)
            VALUES (v_sale_id, NULL, v_quantity, v_unit_price, v_unit_price * v_quantity, true, v_quick_sale_name);
        ELSE
            v_product_id := (v_item->>'product_id')::UUID;
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
        END IF;
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
-- 2. create_checkout_intent — updated for quick sale
-- ============================================================

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
    v_is_quick_sale BOOLEAN;
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
        v_quantity := (v_item->>'quantity')::INT;
        v_is_quick_sale := COALESCE((v_item->>'is_quick_sale')::BOOLEAN, false);

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid item: %', v_item;
        END IF;

        IF v_is_quick_sale THEN
            v_unit_price := (v_item->>'unit_price')::DECIMAL(12, 2);
            IF v_unit_price IS NULL OR v_unit_price < 0 THEN
                RAISE EXCEPTION 'Quick sale item missing unit_price: %', v_item;
            END IF;
        ELSE
            v_product_id := (v_item->>'product_id')::UUID;

            IF v_product_id IS NULL THEN
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

            IF NOT EXISTS (
                SELECT 1
                FROM inventory
                WHERE product_id = v_product_id
                  AND branch_id = p_branch_id
                  AND quantity >= v_quantity
            ) THEN
                RAISE EXCEPTION 'Insufficient stock for product %', v_product_id;
            END IF;
        END IF;

        v_computed_total := v_computed_total + (v_unit_price * v_quantity);
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
        v_quantity := (v_item->>'quantity')::INT;
        v_is_quick_sale := COALESCE((v_item->>'is_quick_sale')::BOOLEAN, false);

        IF v_is_quick_sale THEN
            v_unit_price := (v_item->>'unit_price')::DECIMAL(12, 2);
            v_product_id := NULL;
        ELSE
            v_product_id := (v_item->>'product_id')::UUID;
            v_unit_price := (
                SELECT selling_price
                FROM products
                WHERE id = v_product_id AND business_id = p_business_id
            );
        END IF;

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
