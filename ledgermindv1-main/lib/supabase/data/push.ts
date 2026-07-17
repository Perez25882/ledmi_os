import "server-only"
import { createServiceClient } from "@/lib/supabase/server"

export interface PushSubscriptionInput {
  endpoint: string
  p256dh: string
  auth: string
}

export async function savePushSubscription(
  userId: string,
  businessId: string,
  input: PushSubscriptionInput
) {
  const serviceClient = createServiceClient()
  const { error } = await serviceClient.from("push_subscriptions").upsert(
    {
      user_id: userId,
      business_id: businessId,
      endpoint: input.endpoint,
      p256dh: input.p256dh,
      auth: input.auth,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,endpoint" }
  )

  if (error) {
    throw new Error(error.message)
  }
}

export async function getPushSubscriptionsForBusiness(businessId: string) {
  const serviceClient = createServiceClient()
  const { data, error } = await serviceClient
    .from("push_subscriptions")
    .select("endpoint, p256dh, auth")
    .eq("business_id", businessId)

  if (error) {
    throw new Error(error.message)
  }

  return (data ?? []) as PushSubscriptionInput[]
}
