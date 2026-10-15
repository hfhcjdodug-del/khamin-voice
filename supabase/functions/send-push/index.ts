// send-push — يرسل إشعاراً من لوحة المدير: يحفظه داخل التطبيق ويرسله كإشعار نظام (FCM) لكل من ثبّت التطبيق.
// الأسرار (Edge Functions > Secrets): FCM_SERVICE_ACCOUNT = محتوى ملف JSON الخاص بحساب خدمة Firebase كاملاً.
// SUPABASE_URL و SUPABASE_ANON_KEY يضيفهما Supabase تلقائياً.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function googleAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${body}`)));
  const jwt = `${head}.${body}.${b64url(sig)}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("google token: " + JSON.stringify(j).slice(0, 200));
  return j.access_token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const supaUrl = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const h = { Authorization: auth, apikey: anon, "Content-Type": "application/json" };

    // المدير فقط
    const adm = await fetch(`${supaUrl}/rest/v1/rpc/am_i_admin`, { method: "POST", headers: h, body: "{}" });
    if (!adm.ok || (await adm.json()) !== true) return json({ error: "admin only" }, 403);

    const b = await req.json();
    const title = String(b.title ?? "").trim().slice(0, 80);
    const text = String(b.body ?? "").trim().slice(0, 400);
    const kind = ["info", "update", "alert"].includes(b.kind) ? b.kind : "info";
    const url = typeof b.url === "string" && b.url.startsWith("http") ? b.url : null;
    if (!title) return json({ error: "title required" }, 400);

    // 1) داخل التطبيق (يظهر فوراً لمن هو داخله وفي صندوق «إشعارات التطبيق»)
    const ins = await fetch(`${supaUrl}/rest/v1/app_notifications`, {
      method: "POST",
      headers: { ...h, Prefer: "return=minimal" },
      body: JSON.stringify({ title, body: text, kind, url }),
    });
    if (!ins.ok) return json({ error: "insert failed: " + (await ins.text()).slice(0, 200) }, 500);

    // 2) خارج التطبيق عبر FCM (موضوع all)
    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!saRaw) return json({ inApp: true, push: false, note: "FCM_SERVICE_ACCOUNT غير مضاف" });
    const sa = JSON.parse(saRaw);
    const token = await googleAccessToken(sa);
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          topic: "all",
          notification: { title, body: text },
          data: { kind, url: url ?? "" },
          android: { priority: "HIGH" },
        },
      }),
    });
    if (!r.ok) return json({ inApp: true, push: false, error: (await r.text()).slice(0, 300) });
    return json({ inApp: true, push: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
