-- 007_refunds.sql
-- Refunds and returns support for LedgerMind OS MVP.

CREATE TABLE IF NOT EXISTS refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    cashier_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'voided')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refund_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id UUID NOT NULL REFERENCES refunds(id) ON DELETE CASCADE,
    sale_item_id UUID NOT NULL REFERENCES sale_items(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Refund indexes
CREATE INDEX IF NOT EXISTS idx_refunds_business ON refunds(business_id);
CREATE INDEX IF NOT EXISTS idx_refunds_branch ON refunds(branch_id);
CREATE INDEX IF NOT EXISTS idx_refunds_sale ON refunds(sale_id);
CREATE INDEX IF NOT EXISTS idx_refund_items_refund ON refund_items(refund_id);

-- Helper: quantity already refunded for a sale item
CREATE OR REPLACE FUNCTION refunded_quantity(p_sale_item_id UUID)
RETURNS INTEGER AS $$
DECLARE
    total INTEGER;
BEGIN
    SELECT COALESCE(SUM(ri.quantity), 0)
    INTO total
    FROM refund_items ri
    JOIN refunds r ON r.id = ri.refund_id
    WHERE ri.sale_item_id = p_sale_item_id
      AND r.status = 'completed';

    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- Process a refund. Returns the refund id.
CREATE OR REPLACE FUNCTION process_refund(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_sale_id UUID,
    p_items JSONB,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_refund_id UUID;
    v_total NUMERIC(12,2) := 0;
    item JSONB;
    v_sale_item RECORD;
    v_sale_item_id UUID;
    v_product_id UUID;
    v_quantity INTEGER;
    v_unit_price NUMERIC(12,2);
    v_subtotal NUMERIC(12,2);
    v_already_refunded INTEGER;
    v_old_quantity INTEGER;
BEGIN
    -- Authorization and ownership checks
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'User does not belong to business';
    END IF;

    IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
        RAISE EXCEPTION 'Unauthorized cashier';
    END IF;

    -- Verify sale exists and belongs to business/branch
    PERFORM 1 FROM sales
    WHERE id = p_sale_id
      AND business_id = p_business_id
      AND branch_id = p_branch_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale not found in branch';
    END IF;

    -- Create refund record
    INSERT INTO refunds (business_id, branch_id, sale_id, cashier_id, reason, total_amount)
    VALUES (p_business_id, p_branch_id, p_sale_id, p_cashier_id, p_reason, 0)
    RETURNING id INTO v_refund_id;

    -- Process each item
    FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_sale_item_id := (item->>'sale_item_id')::UUID;
        v_quantity := (item->>'quantity')::INTEGER;

        SELECT si.id, si.product_id, si.quantity, si.unit_price
        INTO v_sale_item
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        WHERE si.id = v_sale_item_id
          AND s.id = p_sale_id
          AND s.business_id = p_business_id;

        IF v_sale_item.id IS NULL THEN
            RAISE EXCEPTION 'Invalid sale item: %', v_sale_item_id;
        END IF;

        v_already_refunded := refunded_quantity(v_sale_item_id);
        IF v_already_refunded + v_quantity > v_sale_item.quantity THEN
            RAISE EXCEPTION 'Refund quantity exceeds sold quantity for item %', v_sale_item_id;
        END IF;

        v_product_id := v_sale_item.product_id;
        v_unit_price := v_sale_item.unit_price;
        v_subtotal := v_unit_price * v_quantity;
        v_total := v_total + v_subtotal;

        INSERT INTO refund_items (refund_id, sale_item_id, product_id, quantity, unit_price, subtotal)
        VALUES (v_refund_id, v_sale_item_id, v_product_id, v_quantity, v_unit_price, v_subtotal);

        -- Return inventory to stock
        SELECT quantity INTO v_old_quantity
        FROM inventory
        WHERE product_id = v_product_id
          AND branch_id = p_branch_id;

        UPDATE inventory
        SET quantity = quantity + v_quantity,
            updated_at = now()
        WHERE product_id = v_product_id
          AND branch_id = p_branch_id;

        -- Insert inventory log
        INSERT INTO inventory_logs (business_id, branch_id, product_id, old_quantity, new_quantity, change_amount, reason, actor_id)
        VALUES (p_business_id, p_branch_id, v_product_id, v_old_quantity, v_old_quantity + v_quantity, v_quantity, 'refund', p_cashier_id);
    END LOOP;

    -- Update refund total
    UPDATE refunds
    SET total_amount = v_total,
        updated_at = now()
    WHERE id = v_refund_id;

    -- Audit log
    INSERT INTO activity_logs (business_id, branch_id, actor_id, action, entity_table, entity_id, metadata)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'refund_created', 'refunds', v_refund_id,
            jsonb_build_object('sale_id', p_sale_id, 'amount', v_total));

    RETURN v_refund_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS on refund tables
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE refund_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS refunds_business_access ON refunds;
CREATE POLICY refunds_business_access ON refunds
    FOR ALL
    TO authenticated
    USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS refund_items_business_access ON refund_items;
CREATE POLICY refund_items_business_access ON refund_items
    FOR ALL
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM refunds r
        WHERE r.id = refund_items.refund_id
          AND user_belongs_to_business(r.business_id)
    ));
