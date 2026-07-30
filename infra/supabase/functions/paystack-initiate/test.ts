import { assertEquals, assertExists } from "https://deno.land/std@0.200.0/assert/mod.ts";
import { handleInitiate } from "./index.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

Deno.env.set("SUPABASE_URL", "http://localhost:54321");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-key");
Deno.env.set("SUPABASE_ANON_KEY", "anon-key");
Deno.env.set("PAYSTACK_SECRET_KEY", "sk_test_secret");

const getEnv = (key: string) => Deno.env.get(key);

let capturedPaystackRequest: any = null;

const mockFetch = (
  _input: string | Request | URL,
  init?: RequestInit,
): Promise<Response> => {
  const requestBody = init?.body ? String(init.body) : "";
  const headers: Record<string, string> = {};
  if (init?.headers) {
    for (const [k, v] of new Headers(init.headers).entries()) {
      headers[k] = v;
    }
  }
  capturedPaystackRequest = { url: String(_input), body: requestBody, headers };

  return Promise.resolve(
    new Response(
      JSON.stringify({
        status: true,
        message: "Authorization URL created",
        data: {
          authorization_url: "https://checkout.paystack.com/abc123",
          access_code: "abc123",
          reference: "paystack-ref-1",
        },
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    ),
  );
};

globalThis.fetch = mockFetch as typeof fetch;

function buildFakeClients(opts: { userId: string; intentStatus?: string; createdBy?: string }) {
  const updates: Record<string, unknown>[] = [];
  const intent = {
    id: "pi-1",
    business_id: "b-1",
    amount: 50.0,
    currency: "GHS",
    provider_reference: "idemp-1",
    status: opts.intentStatus || "initiated",
    created_by: opts.createdBy || opts.userId,
  };

  const serviceClient = {
    from: (table: string) => ({
      select: (_columns: string) => {
        const chain = {
          eq: () => chain,
          single: () => {
            if (table === "payment_intents") {
              return Promise.resolve({ data: intent, error: null });
            }
            return Promise.resolve({ data: null, error: { message: "Not found" } });
          },
        };
        return chain;
      },
      update: (data: Record<string, unknown>) => {
        updates.push(data);
        return {
          eq: () => Promise.resolve({ data: null, error: null }),
        };
      },
    }),
  } as unknown as SupabaseClient;

  const authClient = {
    auth: {
      getUser: (token: string) => {
        if (token === "valid-token") {
          return Promise.resolve({ data: { user: { id: opts.userId } }, error: null });
        }
        return Promise.resolve({ data: { user: null }, error: { message: "bad token" } });
      },
    },
  } as unknown as SupabaseClient;

  return { authClient, serviceClient, updates };
}

Deno.test("returns authorization URL and updates intent", async () => {
  const userId = "user-1";
  const { authClient, serviceClient } = buildFakeClients({ userId });
  capturedPaystackRequest = null;

  const res = await handleInitiate(
    new Request("http://localhost/paystack-initiate", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token", "Content-Type": "application/json" },
      body: JSON.stringify({ intent_id: "pi-1", callback_url: "https://app.example.com/callback" }),
    }),
    { authClient, serviceClient, fetch: mockFetch, getEnv },
  );

  assertEquals(res.status, 200);
  const json = await res.json();
  assertEquals(json.authorization_url, "https://checkout.paystack.com/abc123");
  assertEquals(json.reference, "paystack-ref-1");
  assertExists(capturedPaystackRequest);
  assertEquals(capturedPaystackRequest!.headers["authorization"], "Bearer sk_test_secret");
  const paystackBody = JSON.parse(capturedPaystackRequest!.body);
  assertEquals(paystackBody.amount, 5000); // 50 GHS in pesewas
  assertEquals(paystackBody.email, `cashier-${userId}@ledgermind.app`);
  assertEquals(paystackBody.callback_url, "https://app.example.com/callback");
  // Card flow restricts the channel to "card".
  assertEquals(paystackBody.channel, "card");
});

Deno.test("MoMo flow sends mobile_money channel and phone", async () => {
  const userId = "user-1";
  const { authClient, serviceClient } = buildFakeClients({ userId });
  capturedPaystackRequest = null;

  const res = await handleInitiate(
    new Request("http://localhost/paystack-initiate", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token", "Content-Type": "application/json" },
      body: JSON.stringify({
        intent_id: "pi-1",
        momo_provider: "mtn",
        momo_phone: "0241234567",
      }),
    }),
    { authClient, serviceClient, fetch: mockFetch, getEnv },
  );

  assertEquals(res.status, 200);
  assertExists(capturedPaystackRequest);
  const paystackBody = JSON.parse(capturedPaystackRequest!.body);
  assertEquals(paystackBody.channel, "mobile_money");
  assertEquals(paystackBody.currency, "GHS");
  assertEquals(paystackBody.mobile_money.phone, "0241234567");
});

Deno.test("rejects missing intent_id", async () => {
  const { authClient, serviceClient } = buildFakeClients({ userId: "user-1" });
  const res = await handleInitiate(
    new Request("http://localhost/paystack-initiate", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token", "Content-Type": "application/json" },
      body: JSON.stringify({}),
    }),
    { authClient, serviceClient, fetch: mockFetch, getEnv },
  );
  assertEquals(res.status, 400);
});

Deno.test("rejects non-owner caller", async () => {
  const { authClient, serviceClient } = buildFakeClients({ userId: "user-1", createdBy: "user-2" });
  const res = await handleInitiate(
    new Request("http://localhost/paystack-initiate", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token", "Content-Type": "application/json" },
      body: JSON.stringify({ intent_id: "pi-1" }),
    }),
    { authClient, serviceClient, fetch: mockFetch, getEnv },
  );
  assertEquals(res.status, 403);
});

Deno.test("rejects already-processed intent", async () => {
  const { authClient, serviceClient } = buildFakeClients({ userId: "user-1", intentStatus: "pending" });
  const res = await handleInitiate(
    new Request("http://localhost/paystack-initiate", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token", "Content-Type": "application/json" },
      body: JSON.stringify({ intent_id: "pi-1" }),
    }),
    { authClient, serviceClient, fetch: mockFetch, getEnv },
  );
  assertEquals(res.status, 409);
});
