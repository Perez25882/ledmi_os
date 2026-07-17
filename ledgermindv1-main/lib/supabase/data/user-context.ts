import "server-only"
import { createServerClientForUser, createServiceClient } from "@/lib/supabase/server"
import { getBusinessContext } from "./inventory"
import { type UserRoleContext } from "@/lib/supabase/permissions"
export { type UserRoleContext } from "@/lib/supabase/permissions"

export async function getCurrentUserRoleContext(): Promise<UserRoleContext | null> {
  const userClient = await createServerClientForUser()
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser()

  if (userError || !user) {
    return null
  }

  const businessContext = await getBusinessContext(user.id)
  if (!businessContext) {
    return null
  }

  const serviceClient = createServiceClient()
  const { data, error } = await serviceClient
    .from("user_business_roles")
    .select("role_id, custom_roles(name)")
    .eq("user_id", user.id)
    .eq("business_id", businessContext.businessId)
    .single()

  if (error || !data) {
    return null
  }

  return {
    userId: user.id,
    email: user.email || "",
    businessId: businessContext.businessId,
    branchId: businessContext.branchId,
    roleId: data.role_id as string,
    roleName: (data as any).custom_roles?.name as string,
    branches: businessContext.branches,
  }
}
