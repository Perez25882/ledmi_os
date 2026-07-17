import { createClient, SupabaseClient } from "@supabase/supabase-js";

// LedgerMind OS — Paystack webhook Edge Function
// Reads PAYSTACK_WEBHOOK_SECRET and PAYSTACK_SECRET_KEY from env.
// Verifies the x-paystack-signature HMAC-SHA512, stores the raw webhook,
// appends the matching payment_event, and finalizes the sale atomically.

const textEncoder = new TextEncoder();

// Environment ----------------------------------------------------------------
function getEnv(key: string): string | undefined {
  return Deno.env.get(key);
}

function requiredEnv(key: string): string {
  const value = getEnv(key);
  if (!value) {
    throw new Error(`Missing environment variable: ${key}`);
  }
  return value;
}

// Cryptographic helpers ------------------------------------------------------
async function hmacSha512Hex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, textEncoder.encode(message));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  const aBuf = textEncoder.encode(a);
  const bBuf = textEncoder.encode(b);
  if (aBuf.length !== bBuf.length) return false;
  let diff = 0;
  for (let i = 0; i < aBuf.length; i++) {
    diff |= aBuf[i] ^ bBuf[i];
  }
  return diff === 0;
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", textEncoder.encode(input));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Exported for tests ---------------------------------------------------------
export async function computePaystackSignature(body: string, secret: string): Promise<string> {
  return hmacSha512Hex(body, secret);
}

// Paystack event -> canonical payment_events.event_type mapping
export function mapPaystackEvent(event: string, data: Record<string, unknown>): string {
  switch (event) {
    case "charge.success":
      return "payment_captured";
    case "charge.failed":
      return "payment_failed";
    case "refund.success": {
      const refundAmount = Number(data?.amount ?? 0);
      const txAmount = Number(
        (data?.transaction as Record<string, unknown>)?.amount ??
          data?.transaction_amount ??
          refundAmount,
      );
      return txAmount > 0 && refundAmount < txAmount
        ? "payment_partially_refunded"
        : "payment_refunded";
    }
    case "refund.pending":
    case "refund.failed":
    case "transfer.success":
    case "transfer.failed":
    case "transfer.reversed":
      return "webhook_received";
    case "chargeback.created":
    case "chargeback.pending":
    case "dispute.create":
      return "chargeback_created";
    case "chargeback.success":
    case "dispute.resolve": {
      const resolution = String(data?.resolution ?? "");
      if (
        resolution === "merchant-accepted" ||
        resolution === "lost"
      ) {
        return "chargeback_lost";
      }
      if (
        resolution === "merchant-declined" ||
        resolution === "won"
      ) {
        return "chargeback_won";
      }
      return "chargeback_created";
    }
    case "chargeback.failed":
      return "chargeback_lost";
    default:
      return "webhook_received";
  }
}

// Webhook handling -----------------------------------------------------------
function createServiceClient(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

function isPostgresUniqueViolation(err: { code?: string }): boolean {
  return err?.code === "23505";
}

export async function handleWebhook(
  req: Request,
  options?: { supabaseClient?: SupabaseClient },
): Promise<Response> {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // Read secrets; PAYSTACK_SECRET_KEY is read from env (it belongs to the
  // dashboard charge init flow) and is not stored or logged here.
  const webhookSecret = getEnv("PAYSTACK_WEBHOOK_SECRET");
  if (!webhookSecret) {
    console.error("PAYSTACK_WEBHOOK_SECRET is not set");
    return new Response("webhook secret not configured", { status: 500 });
  }
  if (!getEnv("PAYSTACK_SECRET_KEY")) {
    console.warn("PAYSTACK_SECRET_KEY is not set");
  }

  const signature = req.headers.get("x-paystack-signature");
  if (!signature) {
    return new Response("missing signature", { status: 400 });
  }

  const rawBody = await req.text();
  const expectedSignature = await computePaystackSignature(rawBody, webhookSecret);
  if (!timingSafeEqual(signature, expectedSignature)) {
    console.warn("Paystack signature mismatch");
    return new Response("invalid signature", { status: 400 });
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response("invalid json", { status: 400 });
  }

  const eventType = String(payload.event ?? "");
  const data = (payload.data ?? {}) as Record<string, unknown>;
  const transactionData = (data.transaction ?? {}) as Record<string, unknown>;

  if (!eventType) {
    return new Response("missing event type", { status: 400 });
  }

  const providerReference =
    String(data.reference ?? "") ||
    String(data.transaction_reference ?? "") ||
    String(transactionData.reference ?? "");

  if (!providerReference) {
    return new Response("missing provider reference", { status: 400 });
  }

  const providerEventId =
    String(data.id ?? "") ||
    String(transactionData.id ?? "") ||
    `${providerReference}:${eventType}`;

  const supabase = options?.supabaseClient ?? createServiceClient();

  // 1. Store the raw webhook receipt (idempotent on provider + event id + type)
  const receipt = {
    provider: "paystack",
    provider_event_id: providerEventId,
    event_type: eventType,
    signature_valid: true,
    payload_hash: await sha256Hex(rawBody),
    raw_payload: payload,
  };

  const { error: receiptErr } = await supabase
    .from("webhook_receipts")
    .insert(receipt)
    .select("id");

  if (receiptErr && !isPostgresUniqueViolation(receiptErr)) {
    console.error("Failed to store webhook receipt:", receiptErr);
    return new Response("failed to store receipt", { status: 500 });
  }

  // 2. Find the matching payment intent by Paystack reference.
  const { data: intents, error: intentErr } = await supabase
    .from("payment_intents")
    .select("id, business_id, amount, cart_id")
    .eq("provider_reference", providerReference)
    .limit(1);

  if (intentErr) {
    console.error("Failed to load payment intent:", intentErr);
    return new Response("failed to load payment intent", { status: 500 });
  }

  if (!intents || intents.length === 0) {
    // Acknowledge the webhook so Paystack stops retrying; the receipt is kept.
    console.warn(`No payment intent found for reference ${providerReference}`);
    return new Response("no matching intent", { status: 200 });
  }

  const intent = intents[0];
  const canonicalEventType = mapPaystackEvent(eventType, data);
  const occurredAt =
    String(data.paid_at ?? "") ||
    String(data.created_at ?? "") ||
    String(transactionData.paid_at ?? "") ||
    new Date().toISOString();

  // 3. Append the canonical payment event. Duplicate provider_event_id is safe
  //    because of the partial unique index.
  const eventPayload = {
    payment_intent_id: intent.id,
    event_type: canonicalEventType,
    provider: "paystack",
    provider_event_id: providerEventId,
    provider_reference: providerReference,
    payload,
    occurred_at: occurredAt,
  };

  const { data: newEvents, error: eventInsertErr } = await supabase
    .from("payment_events")
    .insert(eventPayload)
    .select("id");

  let eventId: string | null = null;
  let isNewEvent = true;

  if (eventInsertErr && isPostgresUniqueViolation(eventInsertErr)) {
    // Fetch the existing event id so we can still attempt finalization.
    const { data: existingEvents, error: existingErr } = await supabase
      .from("payment_events")
      .select("id")
      .eq("provider", "paystack")
      .eq("provider_event_id", providerEventId)
      .limit(1);

    if (existingErr) {
      console.error("Failed to resolve duplicate event:", existingErr);
      return new Response("failed to resolve duplicate event", { status: 500 });
    }

    eventId = (existingEvents?.[0] as { id?: string } | undefined)?.id ?? null;
    isNewEvent = false;
  } else if (eventInsertErr) {
    console.error("Failed to insert payment event:", eventInsertErr);
    return new Response("failed to insert payment event", { status: 500 });
  } else {
    eventId = (newEvents?.[0] as { id?: string } | undefined)?.id ?? null;
  }

  // 4. For captured payments, finalize the sale atomically.
  // safe_finalize_sale attaches the capture marker, decrements inventory, creates
  // the legacy payment/invoice/sale, and raises if the cart is not active. All
  // side-effects happen in one transaction, so a failure rolls back cleanly.
  if (canonicalEventType === "payment_captured" && eventId) {
    const { data: saleId, error: finalizeErr } = await supabase.rpc(
      "safe_finalize_sale",
      { p_payment_intent_id: intent.id },
    );

    if (finalizeErr) {
      const msg = String(finalizeErr.message ?? finalizeErr).toLowerCase();
      if (
        msg.includes("not active") ||
        msg.includes("already processed") ||
        msg.includes("no payment_captured event found")
      ) {
        console.info("Sale already finalized or not capturable; ignoring.", {
          intentId: intent.id,
          eventId,
        });
      } else {
        console.error("safe_finalize_sale failed:", finalizeErr);
        return new Response("failed to finalize sale", { status: 500 });
      }
    } else {
      console.info("Sale finalized", { saleId, intentId: intent.id, eventId });
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      event: eventType,
      canonicalEvent: canonicalEventType,
      intentId: intent.id,
      eventId,
      newEvent: isNewEvent,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
}

// Production entry point ------------------------------------------------------
if (import.meta.main) {
  Deno.serve((req: Request) => handleWebhook(req));
}
