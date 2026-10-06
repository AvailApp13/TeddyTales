// send-push — push-уведомления с сервера (КП 13.1): «Событие» и «Новинки
// магазина». Отправляет администратор из панели управления (КП 15.5).
//
// iPhone — напрямую через Apple (APNs, HTTP/2): работает везде, в том
// числе в Китае. Ключ APNs лежит в Vault (apns_key_p8, apns_key_id,
// apns_team_id), читается через public.apns_config() под service_role.
// ⚠ Android (FCM) — после проекта Firebase; пока токены Android
// пропускаются.
//
// Вход (POST, с токеном сотрудника-администратора):
//   { kind: "event" | "shop",
//     title: { ru, en, zh }, body: { ru, en, zh },
//     dryRun?: true }            — dryRun только считает получателей.
// Выход: { recipients, sent, failed, removed, configured }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUNDLE_ID = "com.teddytales.app";
const KINDS = new Set(["event", "shop"]);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

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

/// Подпись для APNs: ES256, живёт до часа — делаем одну на вызов.
async function apnsJwt(pem: string, keyId: string, teamId: string) {
  const input = `${b64url(JSON.stringify({ alg: "ES256", kid: keyId }))}.${
    b64url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }))
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(input),
  );
  return `${input}.${b64url(sig)}`;
}

type Texts = { ru: string; en: string; zh: string };
type Lang = keyof Texts;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Только администратор (КП 15.7).
  const asUser = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: isAdmin } = await asUser.rpc("is_staff", { p_role: "admin" });
  if (isAdmin !== true) return json({ error: "forbidden" }, 403);
  const { data: who } = await asUser.auth.getUser();

  let input: { kind?: string; title?: Texts; body?: Texts; dryRun?: boolean };
  try {
    input = await req.json();
  } catch {
    return json({ error: "bad_json" }, 400);
  }
  const kind = input.kind ?? "";
  const title = input.title;
  const body = input.body;
  if (!KINDS.has(kind) || !title?.ru || !body?.ru) {
    return json({ error: "bad_input" }, 400);
  }
  const pick = (t: Texts, lang: Lang) => (t[lang] || t.ru).trim();

  const db = createClient(url, service);
  const { data: tokens, error } = await db
    .from("push_tokens")
    .select("token, platform, locale")
    .contains("kinds", [kind]);
  if (error) return json({ error: "db", detail: error.message }, 500);

  const ios = (tokens ?? []).filter((t) => t.platform === "ios");
  const { data: cfg } = await db.rpc("apns_config");
  const configured = Boolean(
    cfg?.apns_key_p8 && cfg?.apns_key_id && cfg?.apns_team_id,
  );

  if (input.dryRun || !configured) {
    return json({
      recipients: ios.length,
      android: (tokens ?? []).length - ios.length,
      sent: 0,
      failed: 0,
      removed: 0,
      configured,
    });
  }

  const jwt = await apnsJwt(cfg.apns_key_p8, cfg.apns_key_id, cfg.apns_team_id);
  let sent = 0, failed = 0, removed = 0;
  const dead: string[] = [];

  for (const t of ios) {
    const lang = (["ru", "en", "zh"].includes(t.locale) ? t.locale : "ru") as Lang;
    const res = await fetch(`https://api.push.apple.com/3/device/${t.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: { title: pick(title, lang), body: pick(body, lang) },
          sound: "default",
        },
        kind,
      }),
    });
    if (res.ok) {
      sent++;
    } else {
      failed++;
      const reason = (await res.json().catch(() => ({})))?.reason ?? "";
      // Приложение удалено или токен устарел — больше не шлём.
      if (res.status === 410 || reason === "BadDeviceToken" ||
          reason === "Unregistered") {
        dead.push(t.token);
      }
    }
  }

  if (dead.length) {
    await db.from("push_tokens").delete().in("token", dead);
    removed = dead.length;
  }

  await db.from("push_log").insert({
    kind,
    title_ru: title.ru,
    sent,
    failed,
    note: removed ? `удалено устаревших адресов: ${removed}` : null,
    created_by: who?.user?.id ?? null,
  });

  return json({ recipients: ios.length, sent, failed, removed, configured });
});
