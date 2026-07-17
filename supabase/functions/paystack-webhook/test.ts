import {
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.200.0/assert/mod.ts";
import {
  computePaystackSignature,
  handleWebhook,
  mapPaystackEvent,
} from "./index.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

// Set the environment variables the handler expects.
Deno.env.set("SUPABASE_URL", "http://localhost:54321");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-key");
Deno.env.set("PAYSTACK_WEBHOOK_SECRET", "whsec_test_secret");
Deno.env.set("PAYSTACK_SECRET_KEY", "sk_test_secret");

function buildPayload(event = "charge.success") {
  return {
    event,
    data: {
      id: 123_456,
      reference: "LM-ORDER-001",
      amount: 50_000,
      paid_at: "2026-07-13T12:00:00Z",
      transaction: { id: 999, amount: 50_000 },
    },
  };
}

function createFakeClient(
  opts: { duplicateEvent?: boolean; finalizeError?: string } = {},
) {
  const calls: any[] = [];
  const intent = {
    id: "pi-1",
    business_id: "b-1",
    amount: 50_000,
    cart_id: "cart-1",
  };

  const fakeClient = {
    from: (table: string) => ({
      insert: (data: unknown) => {
        calls.push({ op: "insert", table, data });
        const error =
          opts.duplicateEvent && table === "payment_events"
            ? { code: "23505", message: "duplicate key value" }
            : null;
        return {
          select: () =>
            Promise.resolve({
              data: table === "payment_events" ? [{ id: "ev-1" }] : [{ id: "wr-1" }],
              error,
            }),
        };
      },
      select: () => {
        const result =
          table === "payment_intents" ? [intent] : [{ id: "ev-existing" }];
        const chain = {
          eq: function () {
            return chain;
          },
          limit: function () {
            return Promise.resolve({ data: result, error: null });
          },
        };
        return chain;
      },
    }),
    rpc: (name: string, args: unknown) => {
      calls.push({ op: "rpc", name, args });
      if (name === "safe_finalize_sale" && opts.finalizeError) {
        return Promise.resolve({ data: null, error: { message: opts.finalizeError } });
      }
      return Promise.resolve({ data: "sale-uuid", error: null });
    },
  };

  return {
    client: fakeClient as unknown as SupabaseClient,
    calls,
  };
}

function makeRequest(body: string, signature: string): Request {
  return new Request("http://localhost/paystack-webhook", {
    method: "POST",
    headers: { "x-paystack-signature": signature, "Content-Type": "application/json" },
    body,
  });
}

Deno.test("charge.success is verified, stored, captured and finalized", async () => {
  const { client, calls } = createFakeClient();
  const payload = buildPayload("charge.success");
  const body = JSON.stringify(payload);
  const signature = await computePaystackSignature(body, "whsec_test_secret");

  const res = await handleWebhook(makeRequest(body, signature), {
    supabaseClient: client,
  });

  assertEquals(res.status, 200);
  const json = await res.json();
  assertEquals(json.ok, true);
  assertEquals(json.canonicalEvent, "payment_captured");

  // Webhook receipt stored.
  const receiptCall = calls.find((c: any) => c.op === "insert" && c.table === "webhook_receipts");
  assertEquals(receiptCall?.data?.provider, "paystack");
  assertEquals(receiptCall?.data?.signature_valid, true);

  // Canonical payment event inserted.
  const eventCall = calls.find((c: any) => c.op === "insert" && c.table === "payment_events");
  assertEquals(eventCall?.data?.event_type, "payment_captured");
  assertEquals(eventCall?.data?.provider_reference, "LM-ORDER-001");

  // Sale finalization RPC.
  const finalizeRpc = calls.find((c: any) => c.op === "rpc" && c.name === "safe_finalize_sale");
  assertEquals(finalizeRpc?.args?.p_payment_intent_id, "pi-1");
});

Deno.test("invalid signature returns 400 and does not touch the database", async () => {
  const { client, calls } = createFakeClient();
  const body = JSON.stringify(buildPayload());

  const res = await handleWebhook(
    makeRequest(body, "bad-signature"),
    { supabaseClient: client },
  );

  assertEquals(res.status, 400);
  assertEquals(calls.length, 0);
});

Deno.test("duplicate charge.success event is idempotent", async () => {
  const { client, calls } = createFakeClient({
    duplicateEvent: true,
    finalizeError: "Cart cart-1 is not active. Already processed?",
  });
  const body = JSON.stringify(buildPayload("charge.success"));
  const signature = await computePaystackSignature(body, "whsec_test_secret");

  const res = await handleWebhook(makeRequest(body, signature), {
    supabaseClient: client,
  });

  // Duplicate should not cause a 500; the already-finalized sale is ignored.
  assertEquals(res.status, 200);

  const finalizeRpc = calls.find((c: any) => c.op === "rpc" && c.name === "safe_finalize_sale");
  assertEquals(finalizeRpc?.args?.p_payment_intent_id, "pi-1");
});

Deno.test("Paystack event mapping", () => {
  assertEquals(mapPaystackEvent("charge.success", {}), "payment_captured");
  assertEquals(mapPaystackEvent("charge.failed", {}), "payment_failed");
  assertEquals(
    mapPaystackEvent("refund.success", { amount: 50_000, transaction: { amount: 50_000 } }),
    "payment_refunded",
  );
  assertEquals(
    mapPaystackEvent("refund.success", { amount: 20_000, transaction: { amount: 50_000 } }),
    "payment_partially_refunded",
  );
  assertEquals(mapPaystackEvent("chargeback.created", {}), "chargeback_created");
  assertEquals(
    mapPaystackEvent("dispute.resolve", { resolution: "won" }),
    "chargeback_won",
  );
  assertEquals(mapPaystackEvent("refund.pending", {}), "webhook_received");
});

Deno.test("signature helper produces Paystack-compatible HMAC", async () => {
  const body = '{"event":"charge.success"}';
  const sig = await computePaystackSignature(body, "whsec_secret");
  // HMAC-SHA512 hex is 128 characters.
  assertEquals(sig.length, 128);
  assertMatch(sig, /^[0-9a-f]+$/);
});
