import { NextRequest, NextResponse } from "next/server"
import { createServiceClient, createServerClientForUser } from "@/lib/supabase/server"

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

    // Only owners/managers of the business can invite users.
    const { data: inviterRole } = await serviceClient
      .from("user_business_roles")
      .select("role_id, custom_roles(name)")
      .eq("user_id", user.id)
      .eq("business_id", businessId)
      .single()

    const roleName = (inviterRole as any)?.custom_roles?.name
    if (!["owner", "manager"].includes(roleName)) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    // Invite the user via Supabase Auth. If email is not configured, the
    // invitation will still create the user record but the email may not be sent.
    const { data: invite, error: inviteError } = await serviceClient.auth.admin.inviteUserByEmail(
      email,
      {
        data: {
          business_id: businessId,
          branch_id: branchId,
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
