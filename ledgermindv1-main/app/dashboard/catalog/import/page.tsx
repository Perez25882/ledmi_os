import { requirePageAccess } from "@/lib/supabase/guards"
import { getCategories } from "@/lib/supabase/data/catalog"
import { ImportClient } from "./import-client"

export default async function ImportCatalogPage() {
  const context = await requirePageAccess("catalog")
  const categories = await getCategories(context.businessId)

  return <ImportClient categories={categories} />
}
