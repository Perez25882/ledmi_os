"use server"

import { revalidatePath } from "next/cache"
import {
  createProduct,
  updateProduct,
  deleteProduct,
  createCategory,
  deleteCategory,
  getCurrentBusinessContext,
  ProductInput,
} from "@/lib/supabase/data/catalog"

export async function createProductAction(formData: FormData) {
  const context = await getCurrentBusinessContext()

  const input: ProductInput = {
    name: formData.get("name") as string,
    sku: (formData.get("sku") as string) || "",
    barcode: (formData.get("barcode") as string) || "",
    sellingPrice: parseFloat(formData.get("sellingPrice") as string),
    costPrice: parseFloat(formData.get("costPrice") as string),
    categoryId: (formData.get("categoryId") as string) || undefined,
    reorderThreshold: parseInt((formData.get("reorderThreshold") as string) || "10", 10),
  }

  await createProduct(context.businessId, input)
  revalidatePath("/dashboard/catalog")
}

export async function updateProductAction(formData: FormData) {
  const context = await getCurrentBusinessContext()
  const id = formData.get("id") as string

  const input: Partial<ProductInput> = {
    name: (formData.get("name") as string) || undefined,
    sku: (formData.get("sku") as string) || undefined,
    barcode: (formData.get("barcode") as string) || undefined,
    sellingPrice: formData.get("sellingPrice")
      ? parseFloat(formData.get("sellingPrice") as string)
      : undefined,
    costPrice: formData.get("costPrice")
      ? parseFloat(formData.get("costPrice") as string)
      : undefined,
    categoryId: (formData.get("categoryId") as string) || undefined,
    reorderThreshold: formData.get("reorderThreshold")
      ? parseInt(formData.get("reorderThreshold") as string, 10)
      : undefined,
  }

  await updateProduct(id, context.businessId, input)
  revalidatePath("/dashboard/catalog")
}

export async function deleteProductAction(id: string) {
  const context = await getCurrentBusinessContext()
  await deleteProduct(id, context.businessId)
  revalidatePath("/dashboard/catalog")
}

export async function createCategoryAction(formData: FormData) {
  const context = await getCurrentBusinessContext()
  const name = formData.get("name") as string
  await createCategory(context.businessId, { name })
  revalidatePath("/dashboard/catalog")
}

export async function deleteCategoryAction(id: string) {
  const context = await getCurrentBusinessContext()
  await deleteCategory(id, context.businessId)
  revalidatePath("/dashboard/catalog")
}
