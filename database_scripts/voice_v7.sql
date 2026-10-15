-- نتونس — التحديث 7: الجواهر 💎، المتجر (موافقة يدوية بعد الدفع)، بدون إعلانات، شراء المستوى،
-- هدايا الغرف، والروم الترند. شغّله بعد voice_v6.sql (آمن لو أعدت تشغيله).

-- ===== 1) المحفظة (رصيد الجواهر وحالة «بدون إعلانات») — خاصة بصاحبها =====
CREATE TABLE IF NOT EXISTS public.wallets (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  gems int NOT NULL DEFAULT 0 CHECK (gems >= 0),
  ads_free boolean NOT NULL DEFAULT false
);
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS wallets_own ON public.wallets;
CREATE POLICY wallets_own ON public.wallets FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
GRANT SELECT ON public.wallets TO authenticated;   -- الكتابة عبر الدوال فقط

DROP FUNCTION IF EXISTS public.my_wallet();
CREATE FUNCTION public.my_wallet()
RETURNS TABLE(gems int, ads_free boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT w.gems FROM wallets w WHERE w.user_id = auth.uid()), 0),
         coalesce((SELECT w.ads_free FROM wallets w WHERE w.user_id = auth.uid()), false);
$$;

-- ===== 2) الإعدادات الافتراضية للمتجر (يعدّلها المدير) =====
INSERT INTO public.app_settings(key, value) VALUES
  ('pay_asiacell', ''), ('pay_atheer', ''),
  ('ads_free_price', '3000'), ('trend_threshold', '700'), ('trend_hours', '3'), ('xp_per_gem', '5')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.setting_int(p_key text, p_def int) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT nullif(value, '')::int FROM app_settings WHERE key = p_key), p_def);
$$;

-- ===== 3) باقات الجواهر =====
CREATE TABLE IF NOT EXISTS public.gem_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gems int NOT NULL CHECK (gems > 0),
  price_iqd int NOT NULL CHECK (price_iqd > 0),
  sort int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);
ALTER TABLE public.gem_packages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gp_read ON public.gem_packages;
DROP POLICY IF EXISTS gp_admin ON public.gem_packages;
CREATE POLICY gp_read ON public.gem_packages FOR SELECT TO authenticated USING (active OR public.is_admin());
CREATE POLICY gp_admin ON public.gem_packages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gem_packages TO authenticated;
INSERT INTO public.gem_packages(gems, price_iqd, sort)
SELECT v.g, v.p, v.s FROM (VALUES (100, 1000, 1), (300, 2500, 2), (700, 5500, 3),
                                  (1500, 11000, 4), (3500, 25000, 5), (7500, 50000, 6)) AS v(g, p, s)
WHERE NOT EXISTS (SELECT 1 FROM public.gem_packages);

-- ===== 4) طلبات الشحن (يدفع المستخدم ثم يرسل رقم العملية، والمدير يوافق) =====
CREATE TABLE IF NOT EXISTS public.topup_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('gems', 'ads_free')),
  gems int NOT NULL DEFAULT 0,
  price_iqd int NOT NULL,
  method text NOT NULL CHECK (method IN ('asiacell', 'atheer')),
  ref text NOT NULL CHECK (char_length(ref) BETWEEN 3 AND 60),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz
);
CREATE INDEX IF NOT EXISTS topup_status_idx ON public.topup_requests (status, created_at DESC);
ALTER TABLE public.topup_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS topup_read ON public.topup_requests;
CREATE POLICY topup_read ON public.topup_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
GRANT SELECT ON public.topup_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.request_topup(p_kind text, p_package uuid, p_method text, p_ref text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g int := 0; price int; rid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF (SELECT count(*) FROM topup_requests WHERE user_id = auth.uid() AND status = 'pending') >= 5 THEN
    RAISE EXCEPTION 'too many pending';
  END IF;
  IF p_kind = 'gems' THEN
    SELECT gems, price_iqd INTO g, price FROM gem_packages WHERE id = p_package AND active;
    IF NOT FOUND THEN RAISE EXCEPTION 'bad package'; END IF;
  ELSIF p_kind = 'ads_free' THEN
    price := setting_int('ads_free_price', 3000);
  ELSE
    RAISE EXCEPTION 'bad kind';
  END IF;
  INSERT INTO topup_requests(user_id, kind, gems, price_iqd, method, ref)
  VALUES (auth.uid(), p_kind, g, price, p_method, btrim(p_ref)) RETURNING id INTO rid;
  RETURN rid;
END $$;

CREATE OR REPLACE FUNCTION public.admin_topups(p_status text DEFAULT 'pending')
RETURNS TABLE(id uuid, user_id uuid, name text, username text, kind text, gems int, price_iqd int,
              method text, ref text, status text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
  SELECT t.id, t.user_id, p.name, p.username, t.kind, t.gems, t.price_iqd, t.method, t.ref, t.status, t.created_at
  FROM topup_requests t JOIN profiles p ON p.id = t.user_id
  WHERE t.status = p_status ORDER BY t.created_at DESC LIMIT 100;
END $$;

CREATE OR REPLACE FUNCTION public.admin_decide_topup(p_id uuid, p_approve boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t topup_requests%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO t FROM topup_requests WHERE id = p_id AND status = 'pending' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not pending'; END IF;
  IF p_approve THEN
    INSERT INTO wallets(user_id) VALUES (t.user_id) ON CONFLICT DO NOTHING;
    IF t.kind = 'gems' THEN
      UPDATE wallets SET gems = gems + t.gems WHERE user_id = t.user_id;
    ELSE
      UPDATE wallets SET ads_free = true WHERE user_id = t.user_id;
    END IF;
  END IF;
  UPDATE topup_requests SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
                            decided_at = now() WHERE id = p_id;
END $$;

-- شحن يدوي مباشر من المدير (بدون طلب)
CREATE OR REPLACE FUNCTION public.admin_grant_gems(p_user uuid, p_amount int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_amount = 0 OR abs(p_amount) > 1000000 THEN RAISE EXCEPTION 'bad amount'; END IF;
  INSERT INTO wallets(user_id) VALUES (p_user) ON CONFLICT DO NOTHING;
  UPDATE wallets SET gems = greatest(0, gems + p_amount) WHERE user_id = p_user;
END $$;

-- ===== 5) شراء المستوى بالجواهر =====
-- كل جوهرة = xp_per_gem نقطة (افتراضي 5). يشتري المستخدم المستوى التالي (أو عدة مستويات).
CREATE OR REPLACE FUNCTION public.buy_level_cost(p_levels int) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT ceil((50.0 * power(floor(sqrt(p.xp / 50.0)) + p_levels, 2) - p.xp) / greatest(setting_int('xp_per_gem', 5), 1))::int
  FROM profiles p WHERE p.id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.buy_level(p_levels int DEFAULT 1) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cur int; lv int; target_lv int; cost int; per int; w int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_levels < 1 OR p_levels > 10 THEN RAISE EXCEPTION 'bad levels'; END IF;
  SELECT xp INTO cur FROM profiles WHERE id = auth.uid() FOR UPDATE;
  lv := floor(sqrt(cur / 50.0))::int + 1;
  target_lv := lv + p_levels;
  IF target_lv > 100 THEN RAISE EXCEPTION 'max level'; END IF;
  per := greatest(setting_int('xp_per_gem', 5), 1);
  cost := ceil((50.0 * (target_lv - 1) * (target_lv - 1) - cur) / per)::int;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < cost THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - cost WHERE user_id = auth.uid();
  UPDATE profiles SET xp = 50 * (target_lv - 1) * (target_lv - 1) WHERE id = auth.uid();
  RETURN target_lv;
END $$;

-- ===== 6) الهدايا =====
CREATE TABLE IF NOT EXISTS public.gifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  price int NOT NULL CHECK (price > 0),
  emoji text NOT NULL DEFAULT '🎁',
  image_url text,
  sort int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);
ALTER TABLE public.gifts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gifts_read ON public.gifts;
DROP POLICY IF EXISTS gifts_admin ON public.gifts;
CREATE POLICY gifts_read ON public.gifts FOR SELECT TO authenticated USING (active OR public.is_admin());
CREATE POLICY gifts_admin ON public.gifts FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gifts TO authenticated;
INSERT INTO public.gifts(name, price, emoji, sort)
SELECT v.n, v.p, v.e, v.s FROM (VALUES ('وردة', 10, '🌹', 1), ('قلب', 50, '💖', 2), ('كأس', 100, '🏆', 3),
                                       ('تاج', 300, '👑', 4), ('سيارة', 700, '🏎️', 5), ('قصر', 1500, '🏰', 6)) AS v(n, p, e, s)
WHERE NOT EXISTS (SELECT 1 FROM public.gifts);

CREATE TABLE IF NOT EXISTS public.gift_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id uuid REFERENCES public.rooms(id) ON DELETE SET NULL,
  from_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  gift_id uuid REFERENCES public.gifts(id) ON DELETE SET NULL,
  qty int NOT NULL,
  gems int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.gift_log ENABLE ROW LEVEL SECURITY;   -- بدون سياسات: للمدير عبر SQL فقط

-- رسائل الغرفة: نوع الرسالة (msg عادية / gift هدية) — الهدايا تُنشأ من الدالة فقط
ALTER TABLE public.room_messages ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'msg';
ALTER TABLE public.room_messages ADD COLUMN IF NOT EXISTS meta jsonb;
DROP POLICY IF EXISTS messages_insert ON public.room_messages;
CREATE POLICY messages_insert ON public.room_messages FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND kind = 'msg' AND meta IS NULL
    AND EXISTS (SELECT 1 FROM public.rooms r WHERE r.id = room_id AND r.is_live)
    AND NOT EXISTS (SELECT 1 FROM public.room_flags f
                    WHERE f.room_id = room_messages.room_id AND f.user_id = auth.uid()
                      AND (f.chat_banned OR f.kicked_until > now()))
  );

-- الروم الترند
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS support_total int NOT NULL DEFAULT 0;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS trend_until timestamptz;

-- إهداء هدية داخل الغرفة. دعم صاحب الغرفة فقط يُحسب للترند (700 جوهرة افتراضياً).
CREATE OR REPLACE FUNCTION public.send_gift(p_room uuid, p_to uuid, p_gift uuid, p_qty int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g gifts%ROWTYPE; r rooms%ROWTYPE; total int; w int; me_name text; to_name text; sup int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_qty < 1 OR p_qty > 99 THEN RAISE EXCEPTION 'bad qty'; END IF;
  IF p_to = auth.uid() THEN RAISE EXCEPTION 'not allowed'; END IF;
  SELECT * INTO g FROM gifts WHERE id = p_gift AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'bad gift'; END IF;
  SELECT * INTO r FROM rooms WHERE id = p_room AND is_live;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not live'; END IF;
  IF p_to <> r.host_id AND NOT EXISTS (
       SELECT 1 FROM room_members m WHERE m.room_id = p_room AND m.user_id = p_to
         AND m.last_seen > now() - interval '60 seconds') THEN
    RAISE EXCEPTION 'target not in room';
  END IF;
  total := g.price * p_qty;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < total THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - total WHERE user_id = auth.uid();
  INSERT INTO gift_log(room_id, from_id, to_id, gift_id, qty, gems) VALUES (p_room, auth.uid(), p_to, p_gift, p_qty, total);
  SELECT name INTO me_name FROM profiles WHERE id = auth.uid();
  SELECT name INTO to_name FROM profiles WHERE id = p_to;
  INSERT INTO room_messages(room_id, user_id, body, kind, meta)
  VALUES (p_room, auth.uid(),
          'أهدى ' || to_name || ' ' || g.name || ' ×' || p_qty, 'gift',
          jsonb_build_object('gift_id', g.id, 'name', g.name, 'emoji', g.emoji, 'image_url', g.image_url,
                             'qty', p_qty, 'gems', total, 'to_id', p_to, 'to_name', to_name));
  sup := r.support_total;
  IF p_to = r.host_id THEN
    sup := r.support_total + total;
    UPDATE rooms SET support_total = sup,
      trend_until = CASE WHEN sup >= setting_int('trend_threshold', 700)
                         THEN now() + make_interval(hours => setting_int('trend_hours', 3)) ELSE trend_until END
    WHERE id = p_room;
  END IF;
  RETURN sup;
END $$;

-- ===== 7) قائمة الغرف: الترند أولاً =====
DROP FUNCTION IF EXISTS public.list_rooms();
CREATE FUNCTION public.list_rooms()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text,
              listeners int, seated int, created_at timestamptz,
              host_xp int, friends int, bg_preset text, bg_url text, trending boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         (SELECT count(*)::int FROM room_seats s WHERE s.room_id = r.id),
         r.created_at,
         p.xp,
         (SELECT count(*)::int FROM room_members m JOIN follows f ON f.followee = m.user_id AND f.follower = auth.uid()
           WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         r.bg_preset, r.bg_url,
         coalesce(r.trend_until > now(), false)
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 14 DESC, 7 DESC, r.created_at DESC
  LIMIT 100;
$$;

-- ===== 8) الصلاحيات =====
REVOKE ALL ON FUNCTION public.my_wallet(), public.setting_int(text, int), public.request_topup(text, uuid, text, text),
  public.admin_topups(text), public.admin_decide_topup(uuid, boolean), public.admin_grant_gems(uuid, int),
  public.buy_level_cost(int), public.buy_level(int), public.send_gift(uuid, uuid, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_wallet(), public.request_topup(text, uuid, text, text),
  public.admin_topups(text), public.admin_decide_topup(uuid, boolean), public.admin_grant_gems(uuid, int),
  public.buy_level_cost(int), public.buy_level(int), public.send_gift(uuid, uuid, uuid, int),
  public.list_rooms() TO authenticated;
