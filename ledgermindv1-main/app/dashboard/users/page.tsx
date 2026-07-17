import { redirect } from "next/navigation"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { createServiceClient } from "@/lib/supabase/server"
import { canAccessPage } from "@/lib/supabase/permissions"
import { UserManagementTable } from "@/components/user-management-table"
import { InviteUserForm } from "@/components/invite-user-form"

export interface BusinessMember {
  user_id: string
  email: string
  role_id: string
  role_name: string
  created_at: string
}

export default async function UsersPage() {
  const context = await getCurrentUserRoleContext()
  if (!context) {
    redirect("/onboarding")
  }

  if (!canAccessPage(context.roleName, "users")) {
    redirect("/dashboard/overview")
  }

  const serviceClient = createServiceClient()

  const { data: members, error } = await serviceClient
    .from("user_business_roles")
    .select("user_id, created_at, role_id, custom_roles(name)")
    .eq("business_id", context.businessId)
    .order("created_at", { ascending: false })

  if (error) {
    throw new Error(error.message)
  }

  const enrichedMembers: BusinessMember[] = await Promise.all(
    (members || []).map(async (m: any) => {
      const { data: user } = await serviceClient.auth.admin.getUserById(m.user_id)
      return {
        user_id: m.user_id,
        email: user?.user?.email || "Unknown",
        role_id: m.role_id,
        role_name: (m.custom_roles as any)?.name || "member",
        created_at: m.created_at,
      }
    })
  )

  const { data: roles } = await serviceClient
    .from("custom_roles")
    .select("id, name")
    .eq("business_id", context.businessId)

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-10">
      <div>
        <h1 className="text-3xl font-bold tracking-tight text-foreground">Team Members</h1>
        <p className="text-muted-foreground mt-1">
          Invite and manage users for your business.
        </p>
      </div>

      <InviteUserForm
        businessId={context.businessId}
        roles={(roles || []) as { id: string; name: string }[]}
        currentUserId={context.userId}
      />
      <UserManagementTable
        members={enrichedMembers}
        currentUserId={context.userId}
        roles={(roles || []) as { id: string; name: string }[]}
        businessId={context.businessId}
      />
    </div>
  )
}
