import { NextRequest, NextResponse } from "next/server"
import { createServiceClient, createServerClientForUser } from "@/lib/supabase/server"

// Roles grantable through a self-serve invite. "owner" is deliberately excluded:
// ownership must never be provisionable via this endpoint, or a compromised
// account could escalate itself to owner.
const INVITABLE_ROLES = ["manager", "cashier", "accountant"] as const
// Roles pinned to a single branch. Owners/accountants see all branches, encoded
// as a NULL branch_id on the role row (migration 015).
const BRANCH_SCOPED_ROLES = new Set<string>(["manager", "cashier"])

export async function POST(request: NextRequest) {
  try {
    const userClient = await createServerClientForUser()
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser()

    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const body = (await request.json()) as {
      email: string
      businessId: string
      branchId: string
      roleId: string
    }

    const { email, businessId, branchId, roleId } = body
    if (!email || !businessId || !branchId || !roleId) {
      return NextResponse.json({ error: "Missing fields" }, { status: 400 })
    }

    const serviceClient = createServiceClient()

    // Only owners may invite users (manage_users is an owner-only permission).
    const { data: inviterRole } = await serviceClient
      .from("user_business_roles")
      .select("role_id, custom_roles(name)")
      .eq("user_id", user.id)
      .eq("business_id", businessId)
      .single()

    const roleName = (inviterRole as { custom_roles?: { name?: string } } | null)?.custom_roles?.name
    if (roleName !== "owner") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    // The target role must belong to THIS business and be an invitable (non-owner)
    // role. Without this the caller could pass any role UUID — including the owner
    // role, or a role from another business — straight into the mapping insert.
    const { data: targetRole } = await serviceClient
      .from("custom_roles")
      .select("id, name")
      .eq("id", roleId)
      .eq("business_id", businessId)
      .single()

    if (!targetRole) {
      return NextResponse.json({ error: "Invalid role for this business" }, { status: 400 })
    }
    if (!INVITABLE_ROLES.includes(targetRole.name as (typeof INVITABLE_ROLES)[number])) {
      return NextResponse.json({ error: "Cannot invite this role" }, { status: 403 })
    }

    // The branch must belong to this business and be active. Branch-scoped roles
    // (manager/cashier) are pinned to it; all-branch roles (accountant) store NULL,
    // so an invited accountant is not silently granted single-branch scope and an
    // invited cashier is not silently granted all-branch access.
    const { data: targetBranch } = await serviceClient
      .from("branches")
      .select("id")
      .eq("id", branchId)
      .eq("business_id", businessId)
      .is("deleted_at", null)
      .single()

    if (!targetBranch) {
      return NextResponse.json({ error: "Invalid branch for this business" }, { status: 400 })
    }

    const assignedBranchId = BRANCH_SCOPED_ROLES.has(targetRole.name) ? branchId : null

    const { data: invite, error: inviteError } = await serviceClient.auth.admin.inviteUserByEmail(
      email,
      {
        data: {
          business_id: businessId,
          branch_id: assignedBranchId,
          role_id: roleId,
        },
      }
    )

    if (inviteError) {
      return NextResponse.json({ error: inviteError.message }, { status: 500 })
    }

    const invitedUserId = invite.user?.id
    if (!invitedUserId) {
      return NextResponse.json({ error: "User invitation failed" }, { status: 500 })
    }

    const { error: mappingError } = await serviceClient.from("user_business_roles").insert({
      user_id: invitedUserId,
      business_id: businessId,
      role_id: roleId,
      branch_id: assignedBranchId,
    })

    if (mappingError) {
      return NextResponse.json({ error: mappingError.message }, { status: 500 })
    }

    return NextResponse.json({ userId: invitedUserId })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}