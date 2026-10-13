// livekit-token — يصدر توكن LiveKit للمستخدم المسجّل فقط.
// الأسرار المطلوبة (Edge Functions > Secrets): LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
// SUPABASE_URL و SUPABASE_ANON_KEY يضيفهما Supabase تلقائياً.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signJwt(payload: Record<string, unknown>, secret: string): Promise<string> {
  const head = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${head}.${body}`)));
  return `${head}.${body}.${b64url(sig)}`;
}

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const supaUrl = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const lkUrl = Deno.env.get("LIVEKIT_URL");
    const lkKey = Deno.env.get("LIVEKIT_API_KEY");
    const lkSecret = Deno.env.get("LIVEKIT_API_SECRET");
    if (!lkUrl || !lkKey || !lkSecret) return json({ error: "LiveKit secrets missing" }, 500);

    // تحقّق من المستخدم عبر Supabase Auth
    const u = await fetch(`${supaUrl}/auth/v1/user`, { headers: { Authorization: auth, apikey: anon } });
    if (!u.ok) return json({ error: "unauthorized" }, 401);
    const user = await u.json();

    const { room_id } = await req.json();
    if (!room_id || typeof room_id !== "string") return json({ error: "room_id required" }, 400);

    const rest = (path: string) =>
      fetch(`${supaUrl}/rest/v1/${path}`, { headers: { Authorization: auth, apikey: anon } }).then((r) => r.json());

    const rooms = await rest(`rooms?id=eq.${encodeURIComponent(room_id)}&select=id,is_live`);
    if (!Array.isArray(rooms) || rooms.length === 0 || !rooms[0].is_live) return json({ error: "room not live" }, 404);

    const profs = await rest(`profiles?id=eq.${user.id}&select=name`);
    const name = (Array.isArray(profs) && profs[0]?.name) || "ضيف";

    const now = Math.floor(Date.now() / 1000);
    const token = await signJwt({
      iss: lkKey, sub: user.id, name, nbf: now, iat: now, exp: now + 6 * 3600,
      video: { room: room_id, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true },
    }, lkSecret);

    return json({ token, url: lkUrl });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
