-- 022_ledmi_read_rpcs.sql
-- Ship-readiness remediation — Part 3.
-- PostgREST does not expose the aggregation matviews/view over REST (they 404 for
-- every role), so the Ledmi insights feature could not read them, and migration
-- 020 correctly revoked the over-broad direct grants. Expose the data through
-- SECURITY DEFINER wrapper RPCs that enforce business membership + branch access,
-- which is the sanctioned Supabase pattern for serving matview data securely.
-- Idempotent.

CREATE OR REPLACE FUNCTION get_stock_velocity(p_business_id UUID, p_branch_id UUID)
RETURNS SETOF mv_stock_velocity
LANGUAGE plpgsql SECURITY DEFINER AS $func$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;
    IF p_branch_id NOT IN (SELECT user_accessible_branches(p_business_id)) THEN
        RAISE EXCEPTION 'Access denied for branch';
    END IF;
    RETURN QUERY
        SELECT * FROM mv_stock_velocity
        WHERE business_id = p_business_id AND branch_id = p_branch_id;
END;
$func$;

CREATE OR REPLACE FUNCTION get_daily_sales(p_business_id UUID, p_branch_id UUID, p_since DATE)
RETURNS SETOF mv_daily_sales
LANGUAGE plpgsql SECURITY DEFINER AS $func$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;
    IF p_branch_id NOT IN (SELECT user_accessible_branches(p_business_id)) THEN
        RAISE EXCEPTION 'Access denied for branch';
    END IF;
    RETURN QUERY
        SELECT * FROM mv_daily_sales
        WHERE business_id = p_business_id AND branch_id = p_branch_id
          AND sale_date >= p_since;
END;
$func$;

CREATE OR REPLACE FUNCTION get_inventory_snapshot(p_business_id UUID, p_branch_id UUID)
RETURNS SETOF v_inventory_snapshot
LANGUAGE plpgsql SECURITY DEFINER AS $func$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;
    IF p_branch_id NOT IN (SELECT user_accessible_branches(p_business_id)) THEN
        RAISE EXCEPTION 'Access denied for branch';
    END IF;
    RETURN QUERY
        SELECT * FROM v_inventory_snapshot
        WHERE business_id = p_business_id AND branch_id = p_branch_id;
END;
$func$;

-- These wrappers enforce access internally; expose to authenticated + service_role.
REVOKE EXECUTE ON FUNCTION get_stock_velocity(UUID, UUID)         FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_daily_sales(UUID, UUID, DATE)      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_inventory_snapshot(UUID, UUID)     FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION get_stock_velocity(UUID, UUID)         TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION get_daily_sales(UUID, UUID, DATE)      TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION get_inventory_snapshot(UUID, UUID)     TO authenticated, service_role;