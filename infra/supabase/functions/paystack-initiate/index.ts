import { createClient, SupabaseClient } from "@supabase/supabase-js";

// LedgerMind OS — Paystack transaction initialization Edge Function.
// Called by the Flutter POS after creating a checkout payment intent.
// Verifies the caller, fetches the intent, and initializes a Paystack
// transaction. Returns the authorization_url for the cashier to show
// the customer (MoMo / card).

interface Dependencies {
  getEnv?: (key: string) => string | undefined;
  authClient?: SupabaseClient;
  serviceClient?: SupabaseClient;
  fetch?: typeof globalThis.fetch;
}

interface InitiatePayload {
  intent_id?: string;
  callback_url?: string;
  momo_provider?: string; // 'mtn' | 'vod' | 'atl'
  momo_phone?: string;
}

interface PaystackInitResponse {
  status: boolean;
  message: string;
  data?: {
    authorization_url: string;
    access_code: string;
    reference: string;
  };
}

function getEnv(key: string): string | undefined {
  return Deno.env.get(key);
}

function requiredEnvFrom(env: (key: string) => string | undefined, key: string): string {
  const value = env(key);
  if (!value) {
    throw new Error(`Missing environment variable: ${key}`);
  }
  return value;
}

function createServiceClient(env: (key: string) => string | undefined = getEnv): SupabaseClient {
  return createClient(
    requiredEnvFrom(env, "SUPABASE_URL"),
    requiredEnvFrom(env, "SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );
}

function createAuthClient(env: (key: string) => string | undefined = getEnv): SupabaseClient {
  return createClient(
    requiredEnvFrom(env, "SUPABASE_URL"),
    requiredEnvFrom(env, "SUPABASE_ANON_KEY"),
    {
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );
}

async function parseRequestBody(request: Request): Promise<InitiatePayload> {
  try {
    return (await request.json()) as InitiatePayload;
  } catch {
    return {};
  }
}

async function verifyCaller(request: Request, authClient: SupabaseClient): Promise<string> {
  const authHeader = request.headers.get("authorization");
  if (!authHeader) {
    throw new Error("Missing authorization header");
  }

  const { data, error } = await authClient.auth.getUser(authHeader.replace(/^Bearer\s+/i, ""));
  if (error || !data.user) {
    throw new Error(error?.message || "Invalid token");
  }
  return data.user.id;
}

async function paystackInitialize(
  secretKey: string,
  payload: {
    email: string;
    amount: number; // in pesewas
    reference: string;
    callback_url?: string;
    currency?: string;
    momo_provider?: string; // 'mtn' | 'vod' | 'atl'
    momo_phone?: string;
  },
  fetchFn: typeof globalThis.fetch = fetch,
): Promise<PaystackInitResponse> {
  const body: Record<string, unknown> = {
    email: payload.email,
    amount: payload.amount,
    reference: payload.reference,
  };
  if (payload.callback_url) {
    body.callback_url = payload.callback_url;
  }

  // Mobile money (MoMo) flow. Paystack requires the `channel` set to
  // `mobile_money` and the customer's phone number under `mobile_money.phone`.
  // All Ghanaian MoMo providers (MTN, Vodafone/Cash, AirtelTigo) are served by
  // the single `mobile_money` channel — Paystack auto-detects the network.
  if (payload.momo_phone) {
    body.currency = payload.currency ?? "GHS";
    body.channel = "mobile_money";
    body.mobile_money = { phone: payload.momo_phone };
  } else {
    // Card flow — restrict to card channel so Paystack does not surface MoMo.
    body.channel = "card";
  }

  const response = await fetchFn("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  return (await response.json()) as PaystackInitResponse;
}

export async function handleInitiate(request: Request, deps: Dependencies = {}): Promise<Response> {
  try {
    const method = request.method;
    if (method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    const envGet = deps.getEnv ?? getEnv;
    const authClient = deps.authClient ?? createAuthClient(envGet);
    const serviceClient = deps.serviceClient ?? createServiceClient(envGet);
    const fetchFn = deps.fetch ?? fetch;

    const userId = await verifyCaller(request, authClient);
    const body = await parseRequestBody(request);
    const intentId = body.intent_id;

    if (!intentId) {
      return new Response(JSON.stringify({ error: "intent_id is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: intent, error: intentError } = await serviceClient
      .from("payment_intents")
      .select("id, business_id, amount, currency, provider_reference, status, created_by")
      .eq("id", intentId)
      .single();

    if (intentError || !intent) {
      return new Response(JSON.stringify({ error: "Payment intent not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (intent.created_by !== userId) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (intent.status !== "initiated") {
      return new Response(
        JSON.stringify({ error: `Intent is already ${intent.status}` }),
        { status: 409, headers: { "Content-Type": "application/json" } },
      );
    }

    const reference = intent.provider_reference || intentId;
    const amountInPesewas = Math.round(Number(intent.amount) * 100);
    const email = `cashier-${userId}@ledgermind.app`;

    const paystackResponse = await paystackInitialize(
      requiredEnvFrom(envGet, "PAYSTACK_SECRET_KEY"),
      {
        email,
        amount: amountInPesewas,
        reference,
        callback_url: body.callback_url,
        momo_provider: body.momo_provider,
        momo_phone: body.momo_phone,
      },
      fetchFn,
    );

    if (!paystackResponse.status || !paystackResponse.data) {
      return new Response(
        JSON.stringify({ error: paystackResponse.message || "Paystack initialization failed" }),
        { status: 502, headers: { "Content-Type": "application/json" } },
      );
    }

    // Store Paystack's reference and move intent to pending.
    const { error: updateError } = await serviceClient
      .from("payment_intents")
      .update({
        provider_reference: paystackResponse.data.reference,
        status: "pending",
        updated_at: new Date().toISOString(),
      })
      .eq("id", intentId);

    if (updateError) {
      console.error("Failed to update payment_intent after Paystack init:", updateError);
    }

    return new Response(
      JSON.stringify({
        authorization_url: paystackResponse.data.authorization_url,
        access_code: paystackResponse.data.access_code,
        reference: paystackResponse.data.reference,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("paystack-initiate error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
}

if (import.meta.main) {
  Deno.serve((req: Request) => handleInitiate(req));
}
