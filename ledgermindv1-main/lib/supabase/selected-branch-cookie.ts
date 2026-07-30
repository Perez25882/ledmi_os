/**
 * Name of the cookie that stores the user's global branch selection.
 * Shared between the server-side reader (lib/supabase/selected-branch.ts)
 * and the client-side writer (components/branch-selector-provider.tsx), so it
 * must stay free of `server-only` / `next/headers` imports.
 */
export const SELECTED_BRANCH_COOKIE = "selected_branch_id"
