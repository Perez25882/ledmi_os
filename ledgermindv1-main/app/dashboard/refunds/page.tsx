import { requirePageAccess } from "@/lib/supabase/guards"
import { RefundsClient } from "./refunds-client"

export default async function RefundsPage() {
  await requirePageAccess("refunds")
  return <RefundsClient />
}
