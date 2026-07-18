import "server-only"
import { redirect } from "next/navigation"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import {
  type RoleName,
  type PermissionName,
  type DashboardPage,
  type UserRoleContext,
  isCashier,
  canAccessPage,
  hasPermission,
} from "@/lib/supabase/permissions"

export async function requireRole(allowedRoles: RoleName[]): Promise<UserRoleContext> {
  const context = await getCurrentUserRoleContext()
  if (!context) {
    redirect("/auth/sign-in")
  }
  if (isCashier(context.roleName)) {
    redirect("/auth/cashier-redirect")
  }
  if (!allowedRoles.includes(context.roleName)) {
    redirect("/dashboard/overview")
  }
  return context
}

export async function requirePermission(permission: PermissionName): Promise<UserRoleContext> {
  const context = await getCurrentUserRoleContext()
  if (!context) {
    redirect("/auth/sign-in")
  }
  if (isCashier(context.roleName)) {
    redirect("/auth/cashier-redirect")
  }
  if (!hasPermission(context.roleName, permission)) {
    redirect("/dashboard/overview")
  }
  return context
}

export async function requirePageAccess(page: DashboardPage): Promise<UserRoleContext> {
  const context = await getCurrentUserRoleContext()
  if (!context) {
    redirect("/auth/sign-in")
  }
  if (isCashier(context.roleName)) {
    redirect("/auth/cashier-redirect")
  }
  if (!canAccessPage(context.roleName, page)) {
    redirect("/dashboard/overview")
  }
  return context
}
