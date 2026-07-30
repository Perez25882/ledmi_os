import "server-only"
import { cookies } from "next/headers"
import type { UserRoleContext } from "@/lib/supabase/permissions"
import { SELECTED_BRANCH_COOKIE } from "@/lib/supabase/selected-branch-cookie"

export { SELECTED_BRANCH_COOKIE }

/**
 * Reads the user's branch-selection cookie and validates it against the
 * branches they can actually access. Returns the validated branch id, or
 * `null` when no valid selection is stored (meaning "All Branches" for
 * owners/accountants, or the default branch for managers/cashiers).
 */
export async function getSelectedBranchId(
  context: UserRoleContext
): Promise<string | null> {
  const cookieStore = await cookies()
  const raw = cookieStore.get(SELECTED_BRANCH_COOKIE)?.value
  if (!raw) return null

  const accessible = context.branches.some((b) => b.id === raw)
  return accessible ? raw : null
}
