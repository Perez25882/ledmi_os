export type RoleName = "owner" | "manager" | "cashier" | "accountant"

export type PermissionName =
  | "manage_products"
  | "manage_inventory"
  | "manage_users"
  | "process_sales"
  | "view_reports"
  | "view_inventory"
  | "view_sales"

export type DashboardPage =
  | "overview"
  | "sales"
  | "refunds"
  | "shifts"
  | "inventory"
  | "catalog"
  | "users"
  | "settings"
  | "reports"
  | "logs"
  | "subscription"
  | "system"
  | "ai"

export interface UserRoleContext {
  userId: string
  email: string
  businessId: string
  branchId: string
  roleId: string
  roleName: RoleName
  branches: Array<{ id: string; name: string }>
}

const ROLE_PERMISSIONS: Record<RoleName, PermissionName[]> = {
  owner: [
    "manage_products",
    "manage_inventory",
    "manage_users",
    "process_sales",
    "view_reports",
    "view_inventory",
    "view_sales",
  ],
  manager: ["manage_products", "manage_inventory", "process_sales", "view_reports", "view_inventory", "view_sales"],
  cashier: ["process_sales", "view_inventory"],
  accountant: ["view_reports", "view_sales", "view_inventory"],
}

const PAGE_ROLES: Record<DashboardPage, RoleName[]> = {
  overview: ["owner", "manager", "accountant"],
  sales: ["owner", "manager", "accountant"],
  refunds: ["owner", "manager"],
  shifts: ["owner", "manager"],
  inventory: ["owner", "manager"],
  catalog: ["owner", "manager"],
  users: ["owner"],
  settings: ["owner", "manager"],
  reports: ["owner", "accountant"],
  logs: ["owner", "accountant"],
  subscription: ["owner"],
  system: ["owner"],
  ai: ["owner", "manager", "accountant"],
}

export function canAccessPage(roleName: string, page: DashboardPage): boolean {
  const roles = PAGE_ROLES[page]
  if (!roles) return false
  return roles.includes(roleName as RoleName)
}

export function hasPermission(roleName: string, permission: PermissionName): boolean {
  const perms = ROLE_PERMISSIONS[roleName as RoleName]
  if (!perms) return false
  return perms.includes(permission)
}

export function isCashier(roleName: string): boolean {
  return roleName === "cashier"
}

export function isOwner(roleName: string): boolean {
  return roleName === "owner"
}

export function canAccessAllBranches(roleName: string): boolean {
  return roleName === "owner" || roleName === "accountant"
}

export function getScopedBranchIds(context: UserRoleContext): string[] {
  if (canAccessAllBranches(context.roleName)) {
    return context.branches.map((b) => b.id)
  }
  return [context.branchId]
}

export function getScopedBranchFilter(
  context: UserRoleContext
): { branchId: string | undefined; allBranches: boolean } {
  if (canAccessAllBranches(context.roleName)) {
    return { branchId: undefined, allBranches: true }
  }
  return { branchId: context.branchId, allBranches: false }
}
