import "server-only"
import { createServiceClient, createServerClientForUser } from "@/lib/supabase/server"
import { getBusinessContext } from "./inventory"

export interface ProductInput {
  name: string
  sku: string
  barcode: string
  sellingPrice: number
  costPrice: number
  categoryId?: string
  reorderThreshold?: number
}

export interface Product {
  id: string
  name: string
  sku: string
  barcode: string
  selling_price: number
  cost_price: number
  category_id?: string
  category_name?: string
  reorder_threshold: number
}

export async function getProducts(businessId: string): Promise<Product[]> {
  const serviceClient = createServiceClient()
  const { data, error } = await serviceClient
    .from("products")
    .select(
      `
      id,
      name,
      sku,
      barcode,
      selling_price,
      cost_price,
      category_id,
      reorder_threshold,
      categories(name)
    `
    )
    .eq("business_id", businessId)
    .is("deleted_at", null)
    .order("name")

  if (error) {
    throw new Error(error.message)
  }

  return (data as any[]).map((p) => ({
    id: p.id,
    name: p.name,
    sku: p.sku || "",
    barcode: p.barcode || "",
    selling_price: p.selling_price,
    cost_price: p.cost_price,
    category_id: p.category_id,
    category_name: p.categories?.name,
    reorder_threshold: p.reorder_threshold || 10,
  }))
}

export async function createProduct(businessId: string, input: ProductInput) {
  const serviceClient = createServiceClient()

  const { data, error } = await serviceClient
    .from("products")
    .insert({
      business_id: businessId,
      name: input.name,
      sku: input.sku || null,
      barcode: input.barcode || null,
      selling_price: input.sellingPrice,
      cost_price: input.costPrice,
      category_id: input.categoryId || null,
      reorder_threshold: input.reorderThreshold ?? 10,
    })
    .select("id")
    .single()

  if (error) {
    throw new Error(error.message)
  }

  return data
}

export async function updateProduct(productId: string, businessId: string, input: Partial<ProductInput>) {
  const serviceClient = createServiceClient()

  const { error } = await serviceClient
    .from("products")
    .update({
      name: input.name,
      sku: input.sku || null,
      barcode: input.barcode || null,
      selling_price: input.sellingPrice,
      cost_price: input.costPrice,
      category_id: input.categoryId || null,
      reorder_threshold: input.reorderThreshold,
      updated_at: new Date().toISOString(),
    })
    .eq("id", productId)
    .eq("business_id", businessId)

  if (error) {
    throw new Error(error.message)
  }
}

export async function deleteProduct(productId: string, businessId: string) {
  const serviceClient = createServiceClient()

  const { error } = await serviceClient
    .from("products")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", productId)
    .eq("business_id", businessId)

  if (error) {
    throw new Error(error.message)
  }
}

export interface CategoryInput {
  name: string
}

export interface Category {
  id: string
  name: string
}

export async function getCategories(businessId: string): Promise<Category[]> {
  const serviceClient = createServiceClient()
  const { data, error } = await serviceClient
    .from("categories")
    .select("id, name")
    .eq("business_id", businessId)
    .order("name")

  if (error) {
    throw new Error(error.message)
  }

  return (data ?? []) as Category[]
}

export async function createCategory(businessId: string, input: CategoryInput) {
  const serviceClient = createServiceClient()
  const { data, error } = await serviceClient
    .from("categories")
    .insert({ business_id: businessId, name: input.name })
    .select("id")
    .single()

  if (error) {
    throw new Error(error.message)
  }

  return data
}

export async function deleteCategory(categoryId: string, businessId: string) {
  const serviceClient = createServiceClient()
  const { error } = await serviceClient
    .from("categories")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", categoryId)
    .eq("business_id", businessId)

  if (error) {
    throw new Error(error.message)
  }
}

export async function getCurrentBusinessContext() {
  const userClient = await createServerClientForUser()
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser()

  if (userError || !user) {
    throw new Error("Unauthorized")
  }

  const context = await getBusinessContext(user.id)
  if (!context) {
    throw new Error("No business context")
  }

  return context
}
