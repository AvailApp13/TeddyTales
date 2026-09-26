// verify-purchase — проверка чека App Store / Google Play (КП 11.3).
//
// ⚠ ЖДЁТ НАСТРОЙКИ: ключи магазинов (секреты функции) и товары в App Store
// Connect / Google Play Console. Без ключей отвечает 503 not_configured —
// приложение покупку не закрывает (completePurchase не зовётся), магазин
// пришлёт её снова при следующем запуске, когда ключи появятся.
//
// Секреты (Supabase → Edge Functions → Secrets):
//   APPSTORE_ISSUER_ID, APPSTORE_KEY_ID, APPSTORE_PRIVATE_KEY (.p8 целиком),
//   APPSTORE_BUNDLE_ID = com.teddytales.app
//   GOOGLE_SERVICE_ACCOUNT (JSON ключа сервисного аккаунта с доступом к
//   Google Play Console), GOOGLE_PACKAGE_NAME
//
// Развернуть: supabase functions deploy verify-purchase
//
// Вход (POST, с токеном игрока):
//   { platform: "apple" | "google", productId, transactionId,
//     verificationData }  — у Google verificationData = purchaseToken.
// Выход: { status: "granted" | "already", item, coins, balance }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const env = (name: string) => Deno.env.get(name) ?? "";

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}

async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  pem: string,
  alg: "ES256" | "RS256",
): Promise<string> {
  const input = `${b64url(JSON.stringify(header))}.${
    b64url(JSON.stringify(payload))
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    alg === "ES256"
      ? { name: "ECDSA", namedCurve: "P-256" }
      : { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    alg === "ES256" ? { name: "ECDSA", hash: "SHA-256" } : "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(input),
  );
  return `${input}.${b64url(sig)}`;
}

function jwsPayload(jws: string): Record<string, unknown> {
  const part = jws.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(part));
}

// App Store Server API: транзакция по id. Ответ подписан Apple и получен
// напрямую от Apple по TLS — полезную нагрузку читаем как есть.
async function verifyApple(transactionId: string, productId: string) {
  const issuer = env("APPSTORE_ISSUER_ID");
  const keyId = env("APPSTORE_KEY_ID");
  const pem = env("APPSTORE_PRIVATE_KEY");
  const bundle = env("APPSTORE_BUNDLE_ID");
  if (!issuer || !keyId || !pem || !bundle) return null;
  const now = Math.floor(Date.now() / 1000);
  const token = await signJwt(
    { alg: "ES256", kid: keyId, typ: "JWT" },
    { iss: issuer, iat: now, exp: now + 600, aud: "appstoreconnect-v1", bid: bundle },
    pem,
    "ES256",
  );
  for (const host of ["api.storekit.itunes.apple.com", "api.storekit-sandbox.itunes.apple.com"]) {
    const res = await fetch(
      `https://${host}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (res.status === 404) continue; // нет в боевом — ищем в песочнице (TestFlight)
    if (!res.ok) throw new Error(`apple ${res.status}`);
    const info = jwsPayload((await res.json()).signedTransactionInfo);
    const ok = info.bundleId === bundle && info.productId === productId &&
      !info.revocationDate;
    return { ok, receipt: info, transaction: String(info.originalTransactionId ?? transactionId) };
  }
  return { ok: false, receipt: { error: "not_found" }, transaction: transactionId };
}

async function googleToken(): Promise<string | null> {
  const raw = env("GOOGLE_SERVICE_ACCOUNT");
  if (!raw) return null;
  const sa = JSON.parse(raw);
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 600,
    },
    sa.private_key,
    "RS256",
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`google oauth ${res.status}`);
  return (await res.json()).access_token;
}

async function verifyGoogle(productId: string, purchaseToken: string) {
  const pkg = env("GOOGLE_PACKAGE_NAME");
  const token = await googleToken();
  if (!pkg || !token) return null;
  const base =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/purchases/products/${
      encodeURIComponent(productId)
    }/tokens/${encodeURIComponent(purchaseToken)}`;
  const res = await fetch(base, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`google ${res.status}`);
  const info = await res.json();
  const ok = info.purchaseState === 0;
  if (ok && info.acknowledgementState === 0) {
    // Не подтверждённую за 3 дня покупку Google возвращает покупателю.
    await fetch(`${base}:acknowledge`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    });
  }
  return { ok, receipt: info, transaction: String(info.orderId ?? purchaseToken) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  const url = env("SUPABASE_URL");
  const userClient = createClient(url, env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "auth" }, 401);

  const { platform, productId, transactionId, verificationData } = await req
    .json();
  if (!productId || (platform !== "apple" && platform !== "google")) {
    return json({ error: "bad_request" }, 400);
  }

  let check;
  try {
    check = platform === "apple"
      ? await verifyApple(String(transactionId), String(productId))
      : await verifyGoogle(String(productId), String(verificationData));
  } catch (error) {
    return json({ error: "store", detail: String(error) }, 502);
  }
  if (check === null) return json({ error: "not_configured" }, 503);
  if (!check.ok) return json({ error: "invalid" }, 402);

  const admin = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"));
  const { data, error } = await admin.rpc("grant_store_purchase", {
    p_player: user.id,
    p_platform: platform,
    p_product: productId,
    p_transaction: check.transaction,
    p_receipt: check.receipt,
  });
  if (error) return json({ error: "grant", detail: error.message }, 409);
  return json(data);
});
