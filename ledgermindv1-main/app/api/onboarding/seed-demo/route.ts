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

export async function POST(_request: NextRequest) {
  try {
    const userClient = await createServerClientForUser()
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser()

    if (userError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const serviceClient = createServiceClient()

    // Use the user's existing business/branch if available; otherwise create one.
    const { data: membership, error: membershipError } = await serviceClient
      .from("user_business_roles")
      .select("business_id")
      .eq("user_id", user.id)
      .single()

    let businessId: string
    let branchId: string

    if (membershipError?.code === "PGRST116" || !membership) {
      const { data: business, error: businessError } = await serviceClient
        .from("businesses")
        .insert({ name: "Demo Business" })
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
        .insert({ business_id: business.id, name: "Accra HQ" })
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
        return NextResponse.json({ error: "Owner role not found" }, { status: 500 })
      }

      const { error: roleError } = await serviceClient
        .from("user_business_roles")
        .insert({
          user_id: user.id,
          business_id: business.id,
          role_id: ownerRole.id,
        })

      if (roleError) {
        return NextResponse.json({ error: roleError.message }, { status: 500 })
      }

      businessId = business.id
      branchId = branch.id
    } else {
      businessId = membership.business_id

      const { data: branch, error: branchError } = await serviceClient
        .from("branches")
        .select("id")
        .eq("business_id", businessId)
        .single()

      if (branchError || !branch) {
        return NextResponse.json(
          { error: branchError?.message || "No branch found for business" },
          { status: 500 }
        )
      }
      branchId = branch.id
    }

    // Idempotent: only seed if no products exist yet.
    const { data: existingProducts } = await serviceClient
      .from("products")
      .select("id")
      .eq("business_id", businessId)
      .limit(1)

    if (existingProducts && existingProducts.length > 0) {
      return NextResponse.json({
        businessId,
        branchId,
        products: existingProducts.length,
        message: "Demo data already seeded",
      })
    }

    const categories = [
      { business_id: businessId, name: "Beverages" },
      { business_id: businessId, name: "Snacks" },
    ]
    const { data: insertedCategories, error: categoryError } = await serviceClient
      .from("categories")
      .insert(categories)
      .select("id, name")

    if (categoryError || !insertedCategories) {
      return NextResponse.json(
        { error: categoryError?.message || "Failed to create categories" },
        { status: 500 }
      )
    }

    const beveragesId = insertedCategories.find((c) => c.name === "Beverages")!.id
    const snacksId = insertedCategories.find((c) => c.name === "Snacks")!.id

    const products = [
      {
        business_id: businessId,
        category_id: beveragesId,
        sku: "WATER-500ML",
        name: "Bottled Water 500ml",
        barcode: "1234567890123",
        selling_price: 2.5,
        cost_price: 1.2,
      },
      {
        business_id: businessId,
        category_id: beveragesId,
        sku: "SODA-330ML",
        name: "Soda Can 330ml",
        barcode: "1234567890124",
        selling_price: 4.0,
        cost_price: 2.0,
      },
      {
        business_id: businessId,
        category_id: snacksId,
        sku: "CHIPS-50G",
        name: "Potato Chips 50g",
        barcode: "1234567890125",
        selling_price: 3.5,
        cost_price: 1.8,
      },
    ]

    const { data: insertedProducts, error: productError } = await serviceClient
      .from("products")
      .insert(products)
      .select("id, sku")

    if (productError || !insertedProducts) {
      return NextResponse.json(
        { error: productError?.message || "Failed to create products" },
        { status: 500 }
      )
    }

    const inventory = insertedProducts.map((p) => ({
      business_id: businessId,
      branch_id: branchId,
      product_id: p.id,
      quantity: 100,
      reorder_level: 20,
    }))

    const { error: inventoryError } = await serviceClient
      .from("inventory")
      .insert(inventory)

    if (inventoryError) {
      return NextResponse.json(
        { error: inventoryError.message },
        { status: 500 }
      )
    }

    return NextResponse.json({
      businessId: businessId,
      branchId: branchId,
      products: insertedProducts.length,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
