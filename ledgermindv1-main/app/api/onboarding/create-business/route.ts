import { NextRequest, NextResponse } from "next/server"
import { createServiceClient, createServerClientForUser } from "@/lib/supabase/server"
import { SupabaseClient } from "@supabase/supabase-js"

const OWNER_PERMISSIONS = {
  manage_products: true,
  manage_inventory: true,
  manage_users: true,
  process_sales: true,
  view_reports: true,
  view_inventory: true,
  view_sales: true,
}

async function ensureDefaultRoles(serviceClient: SupabaseClient, businessId: string) {
  const roles = ["owner", "manager", "cashier", "accountant"]
  const permissions = {
    owner: OWNER_PERMISSIONS,
    manager: {
      manage_products: true,
      manage_inventory: true,
      manage_users: true,
      process_sales: true,
      view_reports: true,
    },
    cashier: { process_sales: true, view_inventory: true },
    accountant: { view_reports: true, view_sales: true, view_inventory: true },
  }

  for (const name of roles) {
    await serviceClient.from("custom_roles").insert({
      business_id: businessId,
      name,
      permissions: permissions[name as keyof typeof permissions],
    })
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = (await request.json()) as {
      businessName: string
      branchName: string
    }

    const businessName = body.businessName?.trim()
    const branchName = body.branchName?.trim()

    if (!businessName || !branchName) {
      return NextResponse.json(
        { error: "businessName and branchName are required" },
        { status: 400 }
      )
    }

    const userClient = await createServerClientForUser()
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser()

    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const serviceClient = createServiceClient()

    const { data: business, error: businessError } = await serviceClient
      .from("businesses")
      .insert({ name: businessName })
      .select("id")
      .single()

    if (businessError || !business) {
      return NextResponse.json(
        { error: businessError?.message || "Failed to create business" },
        { status: 500 }
      )
    }

    const { data: branch, error: branchError } = await serviceClient
      .from("branches")
      .insert({ business_id: business.id, name: branchName })
      .select("id")
      .single()

    if (branchError || !branch) {
      return NextResponse.json(
        { error: branchError?.message || "Failed to create branch" },
        { status: 500 }
      )
    }

    let { data: ownerRole } = await serviceClient
      .from("custom_roles")
      .select("id")
      .eq("business_id", business.id)
      .eq("name", "owner")
      .single()

    if (!ownerRole) {
      await ensureDefaultRoles(serviceClient, business.id)
      const { data: refetchedOwner } = await serviceClient
        .from("custom_roles")
        .select("id")
        .eq("business_id", business.id)
        .eq("name", "owner")
        .single()
      ownerRole = refetchedOwner
    }

    if (!ownerRole) {
      return NextResponse.json(
        { error: "Owner role not found for business" },
        { status: 500 }
      )
    }

    const { error: roleError } = await serviceClient
      .from("user_business_roles")
      .insert({
        user_id: user.id,
        business_id: business.id,
        role_id: ownerRole.id,
      })

    if (roleError) {
      return NextResponse.json(
        { error: roleError.message },
        { status: 500 }
      )
    }

    return NextResponse.json({
      businessId: business.id,
      branchId: branch.id,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
