-- 003_auth_helpers.sql
-- LedgerMind OS MVP — Authentication & RBAC helper functions.
--
-- All helpers are SECURITY DEFINER and return safe defaults (false / NULL)
-- for anonymous users. They are used by the RLS policies in
-- 004_rls_policies.sql so policies never call auth.uid() directly.

-- ============================================================
-- 1. Current authenticated user ID
-- ============================================================

CREATE OR REPLACE FUNCTION current_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. Current business from JWT claim
-- ============================================================

CREATE OR REPLACE FUNCTION current_business_id()
RETURNS UUID AS $$
BEGIN
    RETURN (auth.jwt() ->> 'business_id')::UUID;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 3. Business membership
-- ============================================================

CREATE OR REPLACE FUNCTION user_belongs_to_business(p_business_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF current_user_id() IS NULL OR p_business_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles
        WHERE user_id = current_user_id()
        AND business_id = p_business_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 4. Owner check
-- ============================================================

CREATE OR REPLACE FUNCTION user_is_owner(p_business_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF current_user_id() IS NULL OR p_business_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles ubr
        JOIN custom_roles cr ON ubr.role_id = cr.id
        WHERE ubr.user_id = current_user_id()
        AND ubr.business_id = p_business_id
        AND cr.name = 'owner'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 5. Permission check (looks at the user's role JSONB)
-- ============================================================

CREATE OR REPLACE FUNCTION user_has_permission(p_business_id UUID, p_permission TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    IF current_user_id() IS NULL OR p_business_id IS NULL OR p_permission IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles ubr
        JOIN custom_roles cr ON ubr.role_id = cr.id
        WHERE ubr.user_id = current_user_id()
        AND ubr.business_id = p_business_id
        AND cr.permissions ? p_permission
        AND (cr.permissions ->> p_permission)::boolean = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
