-- 009_shifts.sql
-- Cashier shift audit and reconciliation.

CREATE TABLE IF NOT EXISTS shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    cashier_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ,
    opening_float NUMERIC(12,2) NOT NULL DEFAULT 0,
    expected_cash NUMERIC(12,2),
    actual_cash NUMERIC(12,2),
    discrepancy NUMERIC(12,2),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'verified')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shifts_business ON shifts(business_id);
CREATE INDEX IF NOT EXISTS idx_shifts_branch ON shifts(branch_id);
CREATE INDEX IF NOT EXISTS idx_shifts_cashier ON shifts(cashier_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts(status);

ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shifts_business_access ON shifts;
CREATE POLICY shifts_business_access ON shifts
    FOR ALL
    TO authenticated
    USING (user_belongs_to_business(business_id));

-- Close a shift and compute expected cash from sales during the shift.
CREATE OR REPLACE FUNCTION close_shift(
    p_shift_id UUID,
    p_actual_cash NUMERIC(12,2),
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_shift RECORD;
    v_expected NUMERIC(12,2);
BEGIN
    SELECT * INTO v_shift FROM shifts WHERE id = p_shift_id;
    IF v_shift IS NULL THEN
        RAISE EXCEPTION 'Shift not found';
    END IF;

    IF v_shift.status <> 'open' THEN
        RAISE EXCEPTION 'Shift is not open';
    END IF;

    SELECT COALESCE(SUM(p.amount), 0)
    INTO v_expected
    FROM sales s
    JOIN payments p ON p.id = s.payment_id
    WHERE s.cashier_id = v_shift.cashier_id
      AND s.branch_id = v_shift.branch_id
      AND s.created_at >= v_shift.opened_at
      AND s.created_at <= now()
      AND p.method = 'cash';

    v_expected := v_expected + v_shift.opening_float;

    UPDATE shifts
    SET closed_at = now(),
        actual_cash = p_actual_cash,
        expected_cash = v_expected,
        discrepancy = p_actual_cash - v_expected,
        status = 'closed',
        notes = p_notes,
        updated_at = now()
    WHERE id = p_shift_id;

    INSERT INTO activity_logs (business_id, branch_id, actor_id, action, entity_table, entity_id, metadata)
    VALUES (v_shift.business_id, v_shift.branch_id, v_shift.cashier_id, 'shift_closed', 'shifts', p_shift_id,
            jsonb_build_object('expected_cash', v_expected,
                               'actual_cash', p_actual_cash,
                               'discrepancy', p_actual_cash - v_expected));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Open a shift only if the cashier has no other open shift for this branch.
CREATE OR REPLACE FUNCTION open_shift(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_opening_float NUMERIC(12,2) DEFAULT 0
)
RETURNS UUID AS $$
DECLARE
    v_existing UUID;
    v_shift_id UUID;
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'User does not belong to business';
    END IF;

    IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT id INTO v_existing
    FROM shifts
    WHERE cashier_id = p_cashier_id
      AND branch_id = p_branch_id
      AND status = 'open'
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'Cashier already has an open shift';
    END IF;

    INSERT INTO shifts (business_id, branch_id, cashier_id, opening_float)
    VALUES (p_business_id, p_branch_id, p_cashier_id, p_opening_float)
    RETURNING id INTO v_shift_id;

    INSERT INTO activity_logs (business_id, branch_id, actor_id, action, entity_table, entity_id, metadata)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'shift_opened', 'shifts', v_shift_id,
            jsonb_build_object('opening_float', p_opening_float));

    RETURN v_shift_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
