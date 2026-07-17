export interface UserRoleContext {
  userId: string
  email: string
  businessId: string
  branchId: string
  roleId: string
  roleName: string
  branches: Array<{ id: string; name: string }>
}

export function canAccessPage(
  roleName: string,
  page: "catalog" | "sales" | "refunds" | "shifts" | "inventory" | "users" | "settings" | "overview" | "ai"
) {
  switch (page) {
    case "overview":
    case "sales":
    case "refunds":
    case "shifts":
      return ["owner", "manager", "cashier", "accountant"].includes(roleName)
    case "inventory":
      return ["owner", "manager", "cashier"].includes(roleName)
    case "catalog":
      return ["owner", "manager"].includes(roleName)
    case "users":
    case "settings":
      return ["owner", "manager"].includes(roleName)
    case "ai":
      return ["owner", "manager", "accountant"].includes(roleName)
    default:
      return false
  }
}
