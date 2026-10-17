-- =====================================================================
-- voice_v4.sql : غلاف الملف، المستوى (XP)، الزوار، الهوايات، المهام اليومية
-- شغّله مرة واحدة في Supabase → SQL Editor (آمن لو أعدته)
-- =====================================================================

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cover_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS hobbies text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS interests text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS xp int NOT NULL DEFAULT 0;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_hobbies_len CHECK (coalesce(array_length(hobbies,1),0) <= 8);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_interests_len CHECK (char_length(interests) <= 100);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (name, username, bio, avatar_url, cover_url, hobbies, interests) ON public.profiles TO authenticated;

-- ===== الزوار =====
CREATE TABLE IF NOT EXISTS public.profile_visits (
  id bigserial PRIMARY KEY,
  visitor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  visited_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS profile_visits_profile_idx ON public.profile_visits(profile_id, visited_at DESC);
ALTER TABLE public.profile_visits ENABLE ROW LEVEL SECURITY;  -- بدون سياسات: عبر الدوال فقط

CREATE OR REPLACE FUNCTION public.visit_profile(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR p_id = auth.uid() THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM profile_visits WHERE visitor_id = auth.uid() AND profile_id = p_id
             AND visited_at > now() - interval '30 minutes') THEN RETURN; END IF;
  INSERT INTO profile_visits(visitor_id, profile_id) VALUES (auth.uid(), p_id);
END $$;

-- p_kind: all = كل الزوار، viewers = زوار لا يتابعونني، fans = المتابعون (المعجبون)
CREATE OR REPLACE FUNCTION public.my_visitors(p_kind text DEFAULT 'all')
RETURNS TABLE(id uuid, name text, username text, avatar_url text, num bigint, verified boolean,
              last_at timestamptz, is_following boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_kind = 'fans' THEN
    RETURN QUERY
    SELECT p.id, p.name, p.username, p.avatar_url, p.num, p.verified, f.created_at,
           EXISTS (SELECT 1 FROM follows x WHERE x.follower = auth.uid() AND x.followee = p.id)
    FROM follows f JOIN profiles p ON p.id = f.follower
    WHERE f.followee = auth.uid() ORDER BY f.created_at DESC LIMIT 100;
  ELSE
    RETURN QUERY
    SELECT p.id, p.name, p.username, p.avatar_url, p.num, p.verified, v.last_at,
           EXISTS (SELECT 1 FROM follows x WHERE x.follower = auth.uid() AND x.followee = p.id)
    FROM (SELECT visitor_id, max(visited_at) AS last_at FROM profile_visits
          WHERE profile_id = auth.uid() GROUP BY visitor_id) v
    JOIN profiles p ON p.id = v.visitor_id
    WHERE p_kind <> 'viewers'
       OR NOT EXISTS (SELECT 1 FROM follows y WHERE y.follower = p.id AND y.followee = auth.uid())
    ORDER BY v.last_at DESC LIMIT 100;
  END IF;
END $$;

-- ===== المستوى: يزيد ببطء مع دخول الغرف واللعب =====
CREATE TABLE IF NOT EXISTS public.xp_log (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL,
  amount int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS xp_log_user_idx ON public.xp_log(user_id, kind, created_at DESC);
ALTER TABLE public.xp_log ENABLE ROW LEVEL SECURITY;

-- room: +2 كل 10 دقائق، game: +8 كل 3 دقائق، وسقف يومي 150 نقطة
CREATE OR REPLACE FUNCTION public.add_xp(p_kind text) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE amt int; cd interval; today int; cur int;
BEGIN
  IF auth.uid() IS NULL THEN RETURN 0; END IF;
  IF p_kind = 'room' THEN amt := 2; cd := interval '10 minutes';
  ELSIF p_kind = 'game' THEN amt := 8; cd := interval '3 minutes';
  ELSE RAISE EXCEPTION 'bad kind'; END IF;
  SELECT xp INTO cur FROM profiles WHERE id = auth.uid();
  IF EXISTS (SELECT 1 FROM xp_log WHERE user_id = auth.uid() AND kind = p_kind AND created_at > now() - cd) THEN
    RETURN cur;
  END IF;
  SELECT coalesce(sum(amount),0) INTO today FROM xp_log
   WHERE user_id = auth.uid() AND created_at > date_trunc('day', now());
  IF today + amt > 150 THEN RETURN cur; END IF;
  INSERT INTO xp_log(user_id, kind, amount) VALUES (auth.uid(), p_kind, amt);
  UPDATE profiles SET xp = xp + amt WHERE id = auth.uid() RETURNING xp INTO cur;
  RETURN cur;
END $$;

-- مهام اليوم (تقدّم المستخدم الحالي)
CREATE OR REPLACE FUNCTION public.my_daily()
RETURNS TABLE(rooms_today int, games_today int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (SELECT count(*)::int FROM xp_log WHERE user_id = auth.uid() AND kind = 'room'
            AND created_at > date_trunc('day', now())),
         (SELECT count(*)::int FROM xp_log WHERE user_id = auth.uid() AND kind = 'game'
            AND created_at > date_trunc('day', now()));
$$;

-- ===== الملف الشخصي الموسّع =====
DROP FUNCTION IF EXISTS public.get_profile(uuid);
CREATE FUNCTION public.get_profile(p_id uuid)
RETURNS TABLE(id uuid, name text, username text, num bigint, avatar_url text, bio text,
              followers int, following int, is_following boolean, verified boolean,
              cover_url text, hobbies text[], interests text, xp int, visits int,
              rooms_count int, games_count int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.name, p.username, p.num, p.avatar_url, p.bio,
         (SELECT count(*)::int FROM follows f WHERE f.followee = p.id),
         (SELECT count(*)::int FROM follows f WHERE f.follower = p.id),
         EXISTS (SELECT 1 FROM follows f WHERE f.follower = auth.uid() AND f.followee = p.id),
         p.verified, p.cover_url, p.hobbies, p.interests, p.xp,
         (SELECT count(*)::int FROM profile_visits v WHERE v.profile_id = p.id),
         (SELECT count(*)::int FROM xp_log l WHERE l.user_id = p.id AND l.kind = 'room'),
         (SELECT count(*)::int FROM xp_log l WHERE l.user_id = p.id AND l.kind = 'game')
  FROM profiles p WHERE p.id = p_id;
$$;

REVOKE ALL ON FUNCTION public.visit_profile(uuid), public.my_visitors(text), public.add_xp(text), public.my_daily() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.visit_profile(uuid), public.my_visitors(text), public.add_xp(text), public.my_daily(),
  public.get_profile(uuid) TO authenticated;
-- نتونس — التحديث 5: صلاحيات الغرف (كتم/إشراف/طرد/حظر كتابة)، خلفيات الغرفة والمايكات،
-- قوائم المتابعين، VIP، حقول الملف الشخصي، وإغلاق ثغرة تعديل الحساب.
-- شغّله مرة واحدة في Supabase > SQL Editor (آمن لو أعدت تشغيله).

-- ===== 1) حقول الملف الشخصي الجديدة + VIP =====
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS nationality text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS age int;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS region text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS marital text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vip_start timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS vip_end timestamptz;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_age_rng CHECK (age IS NULL OR age BETWEEN 13 AND 99);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT profiles_info_len CHECK (
    char_length(nationality) <= 30 AND char_length(region) <= 30 AND char_length(gender) <= 20
    AND char_length(language) <= 30 AND char_length(marital) <= 20);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- إغلاق ثغرة: كان أي مستخدم يقدر يعدّل xp و verified لحسابه. الآن يعدّل الحقول الآمنة فقط.
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (name, avatar_url, username, bio, cover_url, hobbies, interests,
              nationality, age, region, gender, language, marital) ON public.profiles TO authenticated;

-- منح/سحب VIP (للمدير فقط). p_days > 0 يمدّد، 0 أو أقل ينهي الاشتراك الآن.
CREATE OR REPLACE FUNCTION public.admin_set_vip(p_id uuid, p_days int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_days > 0 THEN
    UPDATE profiles SET
      vip_start = CASE WHEN vip_end IS NULL OR vip_end < now() THEN now() ELSE coalesce(vip_start, now()) END,
      vip_end = greatest(now(), coalesce(vip_end, now())) + make_interval(days => p_days)
    WHERE id = p_id;
  ELSE
    UPDATE profiles SET vip_end = now() WHERE id = p_id AND vip_end IS NOT NULL;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.get_profile(uuid);
CREATE FUNCTION public.get_profile(p_id uuid)
RETURNS TABLE(id uuid, name text, username text, num bigint, avatar_url text, bio text,
              followers int, following int, is_following boolean, verified boolean,
              cover_url text, hobbies text[], interests text, xp int, visits int,
              rooms_count int, games_count int,
              nationality text, age int, region text, gender text, language text, marital text,
              vip_start timestamptz, vip_end timestamptz, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.name, p.username, p.num, p.avatar_url, p.bio,
         (SELECT count(*)::int FROM follows f WHERE f.followee = p.id),
         (SELECT count(*)::int FROM follows f WHERE f.follower = p.id),
         EXISTS (SELECT 1 FROM follows f WHERE f.follower = auth.uid() AND f.followee = p.id),
         p.verified, p.cover_url, p.hobbies, p.interests, p.xp,
         (SELECT count(*)::int FROM profile_visits v WHERE v.profile_id = p.id),
         (SELECT count(*)::int FROM xp_log l WHERE l.user_id = p.id AND l.kind = 'room'),
         (SELECT count(*)::int FROM xp_log l WHERE l.user_id = p.id AND l.kind = 'game'),
         p.nationality, p.age, p.region, p.gender, p.language, p.marital,
         p.vip_start, p.vip_end, p.created_at
  FROM profiles p WHERE p.id = p_id;
$$;

-- قائمة المتابعين / من يتابعهم لأي مستخدم
CREATE OR REPLACE FUNCTION public.user_follows(p_id uuid, p_kind text)
RETURNS TABLE(id uuid, name text, username text, avatar_url text, num bigint, verified boolean,
              xp int, is_following boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.name, p.username, p.avatar_url, p.num, p.verified, p.xp,
         EXISTS (SELECT 1 FROM follows x WHERE x.follower = auth.uid() AND x.followee = p.id)
  FROM follows f
  JOIN profiles p ON p.id = CASE WHEN p_kind = 'followers' THEN f.follower ELSE f.followee END
  WHERE CASE WHEN p_kind = 'followers' THEN f.followee = p_id ELSE f.follower = p_id END
  ORDER BY f.created_at DESC LIMIT 200;
$$;

-- ===== 2) مظهر الغرفة (خلفية الغرفة + خلفية المايكات) =====
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS bg_preset text NOT NULL DEFAULT 'violet';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS bg_url text;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS mic_skin text NOT NULL DEFAULT 'none';
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS mic_skin_url text;

-- ===== 3) صلاحيات الغرفة: مشرف / كتم / حظر كتابة / طرد =====
CREATE TABLE IF NOT EXISTS public.room_flags (
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_mod boolean NOT NULL DEFAULT false,
  muted boolean NOT NULL DEFAULT false,
  chat_banned boolean NOT NULL DEFAULT false,
  kicked_until timestamptz,
  PRIMARY KEY (room_id, user_id)
);
ALTER TABLE public.room_flags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS flags_read ON public.room_flags;
CREATE POLICY flags_read ON public.room_flags FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.room_flags TO authenticated;

-- رتبة المستخدم في الغرفة: 3 مالك، 2 مشرف، 1 عضو
CREATE OR REPLACE FUNCTION public.room_rank(p_room uuid, p_user uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM rooms r WHERE r.id = p_room AND r.host_id = p_user) THEN 3
    WHEN EXISTS (SELECT 1 FROM room_flags f WHERE f.room_id = p_room AND f.user_id = p_user AND f.is_mod) THEN 2
    ELSE 1 END;
$$;

-- p_action: mod (مالك فقط) | mute (مالك فقط) | chatban (مالك/مشرف على من هو أقل رتبة) | kick (نفس القاعدة)
CREATE OR REPLACE FUNCTION public.room_moderate(p_room uuid, p_user uuid, p_action text, p_on boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE me int; them int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_user = auth.uid() THEN RAISE EXCEPTION 'not allowed'; END IF;
  me := room_rank(p_room, auth.uid());
  them := room_rank(p_room, p_user);
  IF p_action IN ('mod', 'mute') THEN
    IF me < 3 THEN RAISE EXCEPTION 'owner only'; END IF;
  ELSIF p_action IN ('chatban', 'kick') THEN
    IF me < 2 OR me <= them THEN RAISE EXCEPTION 'not allowed'; END IF;
  ELSE
    RAISE EXCEPTION 'bad action';
  END IF;
  IF them = 3 THEN RAISE EXCEPTION 'not allowed'; END IF;

  INSERT INTO room_flags(room_id, user_id) VALUES (p_room, p_user) ON CONFLICT DO NOTHING;
  IF p_action = 'mod' THEN
    UPDATE room_flags SET is_mod = p_on WHERE room_id = p_room AND user_id = p_user;
  ELSIF p_action = 'mute' THEN
    UPDATE room_flags SET muted = p_on WHERE room_id = p_room AND user_id = p_user;
  ELSIF p_action = 'chatban' THEN
    UPDATE room_flags SET chat_banned = p_on WHERE room_id = p_room AND user_id = p_user;
  ELSE
    IF p_on THEN
      UPDATE room_flags SET kicked_until = now() + interval '1 hour' WHERE room_id = p_room AND user_id = p_user;
      DELETE FROM room_seats WHERE room_id = p_room AND user_id = p_user;
      DELETE FROM room_members WHERE room_id = p_room AND user_id = p_user;
    ELSE
      UPDATE room_flags SET kicked_until = NULL WHERE room_id = p_room AND user_id = p_user;
    END IF;
  END IF;
END $$;

-- المالك يغيّر مظهر الغرفة
CREATE OR REPLACE FUNCTION public.room_set_look(p_room uuid, p_bg_preset text, p_bg_url text,
                                                p_mic_skin text, p_mic_skin_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE rooms SET bg_preset = coalesce(nullif(p_bg_preset, ''), 'violet'),
                   bg_url = nullif(p_bg_url, ''),
                   mic_skin = coalesce(nullif(p_mic_skin, ''), 'none'),
                   mic_skin_url = nullif(p_mic_skin_url, '')
  WHERE id = p_room AND host_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'owner only'; END IF;
END $$;

-- المطرود لا يعود للغرفة (ساعة واحدة): النبضة ترفض دخوله
CREATE OR REPLACE FUNCTION public.room_heartbeat(p_room uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE live boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF EXISTS (SELECT 1 FROM room_flags WHERE room_id = p_room AND user_id = auth.uid() AND kicked_until > now()) THEN
    RAISE EXCEPTION 'kicked';
  END IF;
  SELECT is_live INTO live FROM rooms WHERE id = p_room;
  IF live IS NOT TRUE THEN RETURN false; END IF;
  INSERT INTO room_members(room_id, user_id, last_seen) VALUES (p_room, auth.uid(), now())
  ON CONFLICT (room_id, user_id) DO UPDATE SET last_seen = now();
  DELETE FROM room_seats s WHERE s.room_id = p_room AND NOT EXISTS (
    SELECT 1 FROM room_members m WHERE m.room_id = s.room_id AND m.user_id = s.user_id
      AND m.last_seen > now() - interval '45 seconds');
  RETURN true;
END $$;

-- المحظور من الكتابة أو المطرود لا يستطيع إرسال رسائل (يُفرض من السيرفر)
DROP POLICY IF EXISTS messages_insert ON public.room_messages;
CREATE POLICY messages_insert ON public.room_messages FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.rooms r WHERE r.id = room_id AND r.is_live)
    AND NOT EXISTS (SELECT 1 FROM public.room_flags f
                    WHERE f.room_id = room_messages.room_id AND f.user_id = auth.uid()
                      AND (f.chat_banned OR f.kicked_until > now()))
  );

-- ===== 4) قائمة الغرف: مستوى المضيف + عدد أصدقائي داخل الغرفة + خلفية الغرفة =====
DROP FUNCTION IF EXISTS public.list_rooms();
CREATE FUNCTION public.list_rooms()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text,
              listeners int, seated int, created_at timestamptz,
              host_xp int, friends int, bg_preset text, bg_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         (SELECT count(*)::int FROM room_seats s WHERE s.room_id = r.id),
         r.created_at,
         p.xp,
         (SELECT count(*)::int FROM room_members m JOIN follows f ON f.followee = m.user_id AND f.follower = auth.uid()
           WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         r.bg_preset, r.bg_url
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 7 DESC, r.created_at DESC
  LIMIT 100;
$$;

-- ===== 5) الصلاحيات والوقت الحقيقي =====
REVOKE ALL ON FUNCTION public.admin_set_vip(uuid, int), public.user_follows(uuid, text),
  public.room_rank(uuid, uuid), public.room_moderate(uuid, uuid, text, boolean),
  public.room_set_look(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_vip(uuid, int), public.user_follows(uuid, text),
  public.room_rank(uuid, uuid), public.room_moderate(uuid, uuid, text, boolean),
  public.room_set_look(uuid, text, text, text, text), public.get_profile(uuid),
  public.list_rooms(), public.room_heartbeat(uuid) TO authenticated;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.room_flags; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms; EXCEPTION WHEN OTHERS THEN NULL; END $$;
-- نتونس — التحديث 6: إشعارات التطبيق، إعدادات عامة (غلاف/اسم «منوّع»)، رفع مستوى أي حساب.
-- شغّله في Supabase > SQL Editor (آمن لو أعدت تشغيله).

-- ===== 1) إشعارات التطبيق =====
CREATE TABLE IF NOT EXISTS public.app_notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  body text NOT NULL DEFAULT '' CHECK (char_length(body) <= 400),
  kind text NOT NULL DEFAULT 'info' CHECK (kind IN ('info', 'update', 'alert')),
  url text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notif_read ON public.app_notifications;
DROP POLICY IF EXISTS notif_admin ON public.app_notifications;
CREATE POLICY notif_read ON public.app_notifications FOR SELECT TO authenticated USING (true);
CREATE POLICY notif_admin ON public.app_notifications FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, DELETE ON public.app_notifications TO authenticated;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.app_notifications; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ===== 2) إعدادات عامة (مثلاً غلاف واسم «منوّع») =====
CREATE TABLE IF NOT EXISTS public.app_settings (
  key text PRIMARY KEY,
  value text NOT NULL DEFAULT ''
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS settings_read ON public.app_settings;
DROP POLICY IF EXISTS settings_admin ON public.app_settings;
CREATE POLICY settings_read ON public.app_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY settings_admin ON public.app_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_settings TO authenticated;

-- ===== 3) رفع/تغيير مستوى أي حساب (للمدير) =====
-- المستوى L يبدأ عند 50*(L-1)^2 نقطة، فنضبط النقاط على بداية المستوى المطلوب.
CREATE OR REPLACE FUNCTION public.admin_set_level(p_id uuid, p_level int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_level < 1 OR p_level > 100 THEN RAISE EXCEPTION 'bad level'; END IF;
  UPDATE profiles SET xp = 50 * (p_level - 1) * (p_level - 1) WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.admin_set_level(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_level(uuid, int) TO authenticated;

-- ===== كود جاهز تنفّذه يدوياً في SQL Editor (غيّر اليوزر والمستوى) =====
-- رفع حساب إلى المستوى 30 باليوزر:
--   UPDATE public.profiles SET xp = 50 * (30 - 1) * (30 - 1) WHERE username = 'mustafa';
-- أو بالرقم (ID الظاهر في الملف الشخصي):
--   UPDATE public.profiles SET xp = 50 * (50 - 1) * (50 - 1) WHERE num = 100004;
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
-- نتونس — التحديث 8: هدايا مصوّرة بأسعارها، مستوى للمُهدي والمستلم، إعلان عام للدعم الكبير،
-- سجل الهدايا في الشرف، وترتيب الغرف حسب الدعم. شغّله بعد voice_v7.sql (آمن لو أعدت تشغيله).

-- ===== 1) الإعدادات =====
INSERT INTO public.app_settings(key, value) VALUES
  ('gift_xp_sender', '2'),     -- نقاط خبرة لكل جوهرة يرسلها
  ('gift_xp_receiver', '1'),   -- نقاط خبرة لكل جوهرة يستلمها
  ('bcast_t1', '500'), ('bcast_t2', '2000'), ('bcast_t3', '5000')   -- حدود الإعلان العام (جواهر في إهداء واحد)
ON CONFLICT (key) DO NOTHING;

-- ===== 2) الهدايا المصوّرة (الصور داخل التطبيق: assets/gifts) =====
DELETE FROM public.gifts WHERE image_url IS NULL AND name IN ('وردة', 'قلب', 'كأس', 'تاج', 'سيارة', 'قصر');
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS code int;   -- رقم الصورة الداخلية
INSERT INTO public.gifts(name, price, image_url, sort, emoji, code)
SELECT v.n, v.p, v.u, v.s, '🎁', v.s
FROM (VALUES
  ('دب', 1, 'asset:gifts/1.png', 1),
  ('وردة', 1, 'asset:gifts/2.png', 2),
  ('إعجاب', 2, 'asset:gifts/3.png', 3),
  ('قلب', 2, 'asset:gifts/4.png', 4),
  ('حلوى النجوم', 3, 'asset:gifts/5.png', 5),
  ('قلب الإصبع', 3, 'asset:gifts/6.png', 6),
  ('عصير ليمون', 4, 'asset:gifts/7.png', 7),
  ('كوك', 4, 'asset:gifts/8.png', 8),
  ('السلام', 5, 'asset:gifts/9.png', 9),
  ('عصير برتقال', 5, 'asset:gifts/10.png', 10),
  ('قبلة', 5, 'asset:gifts/11.png', 11),
  ('قهوة', 6, 'asset:gifts/12.png', 12),
  ('دونات', 8, 'asset:gifts/13.png', 13),
  ('فراشة', 8, 'asset:gifts/14.png', 14),
  ('كعكة', 9, 'asset:gifts/15.png', 15),
  ('برطمان العسل', 10, 'asset:gifts/16.png', 16),
  ('بودينغ الكرز', 10, 'asset:gifts/17.png', 17),
  ('كعكة الفراولة', 10, 'asset:gifts/18.png', 18),
  ('رسالة الحب', 12, 'asset:gifts/19.png', 19),
  ('كباب', 15, 'asset:gifts/20.png', 20),
  ('مسدس الحب', 15, 'asset:gifts/21.png', 21),
  ('سنجاب الفطر', 20, 'asset:gifts/22.png', 22),
  ('نجمة الأحلام', 20, 'asset:gifts/23.png', 23),
  ('صديق البالونات', 25, 'asset:gifts/24.png', 24),
  ('قلبان متشابكان', 25, 'asset:gifts/25.png', 25),
  ('أيدٍ متشابكة', 30, 'asset:gifts/26.png', 26),
  ('غرامافون', 30, 'asset:gifts/27.png', 27),
  ('كرة سحرية', 35, 'asset:gifts/28.png', 28),
  ('أرجيلة', 40, 'asset:gifts/29.png', 29),
  ('قلب الورود', 40, 'asset:gifts/30.png', 30),
  ('قلادة الوردة', 45, 'asset:gifts/31.png', 31),
  ('فتاة القمر', 50, 'asset:gifts/32.png', 32),
  ('جمل', 55, 'asset:gifts/33.png', 33),
  ('قلعة وردية', 60, 'asset:gifts/34.png', 34),
  ('هلال الأحلام', 60, 'asset:gifts/35.png', 35),
  ('ساعة رملية', 65, 'asset:gifts/36.png', 36),
  ('صندوق القمر', 70, 'asset:gifts/37.png', 37),
  ('بساط الريح', 80, 'asset:gifts/38.png', 38),
  ('صندوق الكنز', 90, 'asset:gifts/39.png', 39),
  ('منطاد الحب', 100, 'asset:gifts/40.png', 40),
  ('نافورة الذهب', 100, 'asset:gifts/41.png', 41),
  ('صندوق الجواهر', 110, 'asset:gifts/42.png', 42),
  ('ساعة ذهبية', 120, 'asset:gifts/43.png', 43),
  ('خزنة الذهب', 130, 'asset:gifts/44.png', 44),
  ('قطار الذهب', 140, 'asset:gifts/45.png', 45),
  ('تاج الأجنحة', 150, 'asset:gifts/46.png', 46),
  ('العرش', 160, 'asset:gifts/47.png', 47),
  ('سفينة الذهب', 180, 'asset:gifts/48.png', 48),
  ('الأسد الملكي', 200, 'asset:gifts/49.png', 49),
  ('قصر الأحلام', 220, 'asset:gifts/50.png', 50),
  ('قلعة القمر', 250, 'asset:gifts/51.png', 51),
  ('أرجوحة الكابلز', 280, 'asset:gifts/52.png', 52),
  ('سيف الجليد', 300, 'asset:gifts/53.png', 53),
  ('جيب النمر', 350, 'asset:gifts/54.png', 54),
  ('منصة الدي جي', 400, 'asset:gifts/55.png', 55),
  ('موكب السيارات', 450, 'asset:gifts/56.png', 56),
  ('برج الألعاب النارية', 500, 'asset:gifts/57.png', 57),
  ('سيارة رياضية فخمة', 700, 'asset:gifts/58.png', 58),
  ('قصر الجليد', 1500, 'asset:gifts/59.png', 59),
  ('الملك والملكة', 2500, 'asset:gifts/60.png', 60),
  ('حفلة الزفاف', 3000, 'asset:gifts/61.png', 61),
  ('الحفل الراقي', 5000, 'asset:gifts/62.png', 62)
) AS v(n, p, u, s)
WHERE NOT EXISTS (SELECT 1 FROM public.gifts g WHERE g.name = v.n);

-- ===== 3) الإعلان العام للدعم الكبير =====
CREATE TABLE IF NOT EXISTS public.gift_broadcasts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id uuid REFERENCES public.rooms(id) ON DELETE SET NULL,
  from_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_name text NOT NULL,
  to_name text NOT NULL,
  gems int NOT NULL,
  tier int NOT NULL CHECK (tier BETWEEN 1 AND 3),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.gift_broadcasts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gb_read ON public.gift_broadcasts;
CREATE POLICY gb_read ON public.gift_broadcasts FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.gift_broadcasts TO authenticated;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.gift_broadcasts; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ===== 4) إهداء: خصم + نقاط خبرة للطرفين + إعلان عام + دعم الترند =====
CREATE OR REPLACE FUNCTION public.send_gift(p_room uuid, p_to uuid, p_gift uuid, p_qty int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g gifts%ROWTYPE; r rooms%ROWTYPE; total int; w int; me_name text; to_name text; sup int; tier int := 0;
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
  -- مستوى المُهدي والمستلم
  UPDATE profiles SET xp = xp + total * setting_int('gift_xp_sender', 2) WHERE id = auth.uid();
  UPDATE profiles SET xp = xp + total * setting_int('gift_xp_receiver', 1) WHERE id = p_to;
  -- إعلان عام في كل الغرف كلما كبر الدعم
  IF total >= setting_int('bcast_t3', 5000) THEN tier := 3;
  ELSIF total >= setting_int('bcast_t2', 2000) THEN tier := 2;
  ELSIF total >= setting_int('bcast_t1', 500) THEN tier := 1; END IF;
  IF tier > 0 THEN
    INSERT INTO gift_broadcasts(room_id, from_id, to_id, from_name, to_name, gems, tier)
    VALUES (p_room, auth.uid(), p_to, me_name, to_name, total, tier);
  END IF;
  -- دعم صاحب الغرفة فقط يرفع الروم (ترند + ترتيب)
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

-- ===== 5) الهدايا المستلمة (تظهر في الشرف) =====
CREATE OR REPLACE FUNCTION public.user_gifts(p_id uuid)
RETURNS TABLE(gift_id uuid, name text, emoji text, image_url text, qty bigint, gems bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT g.id, g.name, g.emoji, g.image_url, sum(l.qty), sum(l.gems)
  FROM gift_log l JOIN gifts g ON g.id = l.gift_id
  WHERE l.to_id = p_id
  GROUP BY g.id, g.name, g.emoji, g.image_url
  ORDER BY sum(l.gems) DESC LIMIT 60;
$$;

CREATE OR REPLACE FUNCTION public.user_gift_totals(p_id uuid)
RETURNS TABLE(received bigint, sent bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT sum(gems) FROM gift_log WHERE to_id = p_id), 0)::bigint,
         coalesce((SELECT sum(gems) FROM gift_log WHERE from_id = p_id), 0)::bigint;
$$;

-- ===== 6) قائمة الغرف: الترند أولاً مرتّبة حسب الدعم (المركز 1 ثم 2 ثم 3) =====
DROP FUNCTION IF EXISTS public.list_rooms();
CREATE FUNCTION public.list_rooms()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text,
              listeners int, seated int, created_at timestamptz,
              host_xp int, friends int, bg_preset text, bg_url text, trending boolean, support int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         (SELECT count(*)::int FROM room_seats s WHERE s.room_id = r.id),
         r.created_at,
         p.xp,
         (SELECT count(*)::int FROM room_members m JOIN follows f ON f.followee = m.user_id AND f.follower = auth.uid()
           WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         r.bg_preset, r.bg_url,
         coalesce(r.trend_until > now(), false),
         r.support_total
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 14 DESC, (CASE WHEN coalesce(r.trend_until > now(), false) THEN r.support_total ELSE 0 END) DESC, 7 DESC, r.created_at DESC
  LIMIT 100;
$$;

REVOKE ALL ON FUNCTION public.user_gifts(uuid), public.user_gift_totals(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_gifts(uuid), public.user_gift_totals(uuid), public.send_gift(uuid, uuid, uuid, int),
  public.list_rooms() TO authenticated;
-- نتونس — التحديث 9: الياقوت ♦ (يحصل عليه مستلم الهدايا ويحوّله إلى جواهر).
-- كل 20 جوهرة تُهدى لك = ياقوتة، وكل ياقوتة تُحوَّل إلى 10 جواهر. آمن لو أعدت تشغيله.

ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS ruby_pts int NOT NULL DEFAULT 0 CHECK (ruby_pts >= 0);

DROP FUNCTION IF EXISTS public.my_wallet();
CREATE FUNCTION public.my_wallet()
RETURNS TABLE(gems int, ads_free boolean, ruby_pts int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT w.gems FROM wallets w WHERE w.user_id = auth.uid()), 0),
         coalesce((SELECT w.ads_free FROM wallets w WHERE w.user_id = auth.uid()), false),
         coalesce((SELECT w.ruby_pts FROM wallets w WHERE w.user_id = auth.uid()), 0);
$$;

INSERT INTO public.app_settings(key, value) VALUES ('ruby_pts_per', '20'), ('ruby_to_gems', '10')
ON CONFLICT (key) DO NOTHING;

-- تحويل الياقوت إلى جواهر: p_count = 0 يعني تحويل الكل
CREATE OR REPLACE FUNCTION public.convert_rubies(p_count int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE per int := setting_int('ruby_pts_per', 20); mult int := setting_int('ruby_to_gems', 10); pts int; n int; g int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT ruby_pts INTO pts FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'no rubies'; END IF;
  n := pts / per;
  IF p_count > 0 THEN n := least(n, p_count); END IF;
  IF n < 1 THEN RAISE EXCEPTION 'no rubies'; END IF;
  g := n * mult;
  UPDATE wallets SET ruby_pts = ruby_pts - n * per, gems = gems + g WHERE user_id = auth.uid();
  RETURN g;
END $$;

CREATE OR REPLACE FUNCTION public.send_gift(p_room uuid, p_to uuid, p_gift uuid, p_qty int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g gifts%ROWTYPE; r rooms%ROWTYPE; total int; w int; me_name text; to_name text; sup int; tier int := 0;
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
  -- الياقوت: كل 20 جوهرة مستلمة = ياقوتة (تُحفظ كنقاط ليبقى الكسر)
  INSERT INTO wallets(user_id) VALUES (p_to) ON CONFLICT DO NOTHING;
  UPDATE wallets SET ruby_pts = ruby_pts + total WHERE user_id = p_to;
  INSERT INTO gift_log(room_id, from_id, to_id, gift_id, qty, gems) VALUES (p_room, auth.uid(), p_to, p_gift, p_qty, total);
  SELECT name INTO me_name FROM profiles WHERE id = auth.uid();
  SELECT name INTO to_name FROM profiles WHERE id = p_to;
  INSERT INTO room_messages(room_id, user_id, body, kind, meta)
  VALUES (p_room, auth.uid(),
          'أهدى ' || to_name || ' ' || g.name || ' ×' || p_qty, 'gift',
          jsonb_build_object('gift_id', g.id, 'name', g.name, 'emoji', g.emoji, 'image_url', g.image_url,
                             'qty', p_qty, 'gems', total, 'to_id', p_to, 'to_name', to_name));
  -- مستوى المُهدي والمستلم
  UPDATE profiles SET xp = xp + total * setting_int('gift_xp_sender', 2) WHERE id = auth.uid();
  UPDATE profiles SET xp = xp + total * setting_int('gift_xp_receiver', 1) WHERE id = p_to;
  -- إعلان عام في كل الغرف كلما كبر الدعم
  IF total >= setting_int('bcast_t3', 5000) THEN tier := 3;
  ELSIF total >= setting_int('bcast_t2', 2000) THEN tier := 2;
  ELSIF total >= setting_int('bcast_t1', 500) THEN tier := 1; END IF;
  IF tier > 0 THEN
    INSERT INTO gift_broadcasts(room_id, from_id, to_id, from_name, to_name, gems, tier)
    VALUES (p_room, auth.uid(), p_to, me_name, to_name, total, tier);
  END IF;
  -- دعم صاحب الغرفة فقط يرفع الروم (ترند + ترتيب)
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


REVOKE ALL ON FUNCTION public.my_wallet(), public.convert_rubies(int), public.send_gift(uuid, uuid, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_wallet(), public.convert_rubies(int), public.send_gift(uuid, uuid, uuid, int) TO authenticated;


-- نتونس — التحديث 10: قفل الروم 🔒، الرومات السابقة، وأغاني المستخدمين.
-- شغّله بعد voice_v9.sql (أو شغّل الملف الشامل voice_all_v4_to_v10.sql وحده). آمن لو أعدت تشغيله.

-- ===== 1) قفل الروم =====
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS locked boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.room_heartbeat(p_room uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE live boolean; lk boolean; hid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF EXISTS (SELECT 1 FROM room_flags WHERE room_id = p_room AND user_id = auth.uid() AND kicked_until > now()) THEN
    RAISE EXCEPTION 'kicked';
  END IF;
  SELECT is_live, locked, host_id INTO live, lk, hid FROM rooms WHERE id = p_room;
  IF live IS NOT TRUE THEN RETURN false; END IF;
  -- الروم المقفلة: لا يدخلها إلا صاحبها ومن كان داخلها قبل القفل
  IF lk AND hid <> auth.uid() AND NOT EXISTS (
       SELECT 1 FROM room_members m WHERE m.room_id = p_room AND m.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'room locked';
  END IF;
  INSERT INTO room_members(room_id, user_id, last_seen) VALUES (p_room, auth.uid(), now())
  ON CONFLICT (room_id, user_id) DO UPDATE SET last_seen = now();
  DELETE FROM room_seats s WHERE s.room_id = p_room AND NOT EXISTS (
    SELECT 1 FROM room_members m WHERE m.room_id = s.room_id AND m.user_id = s.user_id
      AND m.last_seen > now() - interval '45 seconds');
  RETURN true;
END $$;


DROP FUNCTION IF EXISTS public.list_rooms();
CREATE FUNCTION public.list_rooms()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text,
              listeners int, seated int, created_at timestamptz,
              host_xp int, friends int, bg_preset text, bg_url text, trending boolean, support int, locked boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         (SELECT count(*)::int FROM room_seats s WHERE s.room_id = r.id),
         r.created_at,
         p.xp,
         (SELECT count(*)::int FROM room_members m JOIN follows f ON f.followee = m.user_id AND f.follower = auth.uid()
           WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         r.bg_preset, r.bg_url,
         coalesce(r.trend_until > now(), false),
         r.support_total,
         r.locked
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 14 DESC, (CASE WHEN coalesce(r.trend_until > now(), false) THEN r.support_total ELSE 0 END) DESC, 7 DESC, r.created_at DESC
  LIMIT 100;
$$;


CREATE OR REPLACE FUNCTION public.set_room_locked(p_room uuid, p_locked boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  UPDATE rooms SET locked = p_locked WHERE id = p_room AND host_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'owner only'; END IF;
END $$;

-- ===== 2) الرومات السابقة (محفوظة لكل مستخدم حسب صاحب الروم) =====
CREATE TABLE IF NOT EXISTS public.room_history (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  host_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  room_title text NOT NULL DEFAULT '',
  last_visit timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, host_id)
);
ALTER TABLE public.room_history ENABLE ROW LEVEL SECURITY;
-- لا سياسات: القراءة والكتابة عبر الدوال فقط

CREATE OR REPLACE FUNCTION public.room_visited(p_room uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r rooms%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO r FROM rooms WHERE id = p_room;
  IF NOT FOUND OR r.host_id = auth.uid() THEN RETURN; END IF;
  INSERT INTO room_history(user_id, host_id, room_title, last_visit)
  VALUES (auth.uid(), r.host_id, r.title, now())
  ON CONFLICT (user_id, host_id) DO UPDATE SET room_title = EXCLUDED.room_title, last_visit = now();
  DELETE FROM room_history WHERE user_id = auth.uid() AND last_visit < now() - interval '60 days';
END $$;

DROP FUNCTION IF EXISTS public.my_recent_rooms();
CREATE FUNCTION public.my_recent_rooms()
RETURNS TABLE(host_id uuid, host_name text, host_avatar text, room_title text, last_visit timestamptz,
              live_room_id uuid, live_title text, live_topic text, locked boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT h.host_id, p.name, p.avatar_url, h.room_title, h.last_visit,
         lr.id, lr.title, lr.topic, coalesce(lr.locked, false)
  FROM room_history h
  JOIN profiles p ON p.id = h.host_id
  LEFT JOIN LATERAL (SELECT r.id, r.title, r.topic, r.locked FROM rooms r
                     WHERE r.host_id = h.host_id AND r.is_live ORDER BY r.created_at DESC LIMIT 1) lr ON true
  WHERE h.user_id = auth.uid()
  ORDER BY (lr.id IS NOT NULL) DESC, h.last_visit DESC
  LIMIT 40;
$$;

-- ===== 3) أغاني المستخدمين =====
CREATE TABLE IF NOT EXISTS public.songs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  artist text NOT NULL DEFAULT '' CHECK (char_length(artist) <= 60),
  url text NOT NULL,
  path text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS songs_created_idx ON public.songs (created_at DESC);
ALTER TABLE public.songs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS songs_read ON public.songs;
CREATE POLICY songs_read ON public.songs FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS songs_insert ON public.songs;
CREATE POLICY songs_insert ON public.songs FOR INSERT TO authenticated
  WITH CHECK (owner = auth.uid()
              AND (SELECT count(*) FROM public.songs s WHERE s.owner = auth.uid()) < 30);
DROP POLICY IF EXISTS songs_delete ON public.songs;
CREATE POLICY songs_delete ON public.songs FOR DELETE TO authenticated
  USING (owner = auth.uid() OR public.is_admin());
GRANT SELECT, INSERT, DELETE ON public.songs TO authenticated;

DO $$ BEGIN
  INSERT INTO storage.buckets (id, name, public) VALUES ('songs', 'songs', true) ON CONFLICT (id) DO NOTHING;
  BEGIN
    UPDATE storage.buckets SET file_size_limit = 15728640 WHERE id = 'songs';   -- 15 ميغابايت
  EXCEPTION WHEN OTHERS THEN NULL; END;
  DROP POLICY IF EXISTS "songs_read" ON storage.objects;
  DROP POLICY IF EXISTS "songs_ins" ON storage.objects;
  DROP POLICY IF EXISTS "songs_del" ON storage.objects;
  CREATE POLICY "songs_read" ON storage.objects FOR SELECT USING (bucket_id = 'songs');
  CREATE POLICY "songs_ins" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'songs' AND split_part(name, '/', 1) = auth.uid()::text);
  CREATE POLICY "songs_del" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'songs' AND (split_part(name, '/', 1) = auth.uid()::text OR public.is_admin()));
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ===== 4) تشغيل أغنية داخل الروم (المالك والمشرفون) — كل المستمعين يشغّلونها محلياً بالتزامن =====
ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS song_title text,
  ADD COLUMN IF NOT EXISTS song_artist text,
  ADD COLUMN IF NOT EXISTS song_url text,
  ADD COLUMN IF NOT EXISTS song_started timestamptz,
  ADD COLUMN IF NOT EXISTS song_paused_ms int;

CREATE OR REPLACE FUNCTION public.server_time() RETURNS timestamptz
LANGUAGE sql STABLE AS $$ SELECT now(); $$;

-- p_action: play (مع p_song) | pause | resume | stop
CREATE OR REPLACE FUNCTION public.room_song(p_room uuid, p_action text, p_song uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s songs%ROWTYPE; r rooms%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF room_rank(p_room, auth.uid()) < 2 THEN RAISE EXCEPTION 'not allowed'; END IF;
  SELECT * INTO r FROM rooms WHERE id = p_room AND is_live;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not live'; END IF;
  IF p_action = 'play' THEN
    SELECT * INTO s FROM songs WHERE id = p_song;
    IF NOT FOUND THEN RAISE EXCEPTION 'song not found'; END IF;
    UPDATE rooms SET song_title = s.title, song_artist = s.artist, song_url = s.url,
                     song_started = now(), song_paused_ms = NULL WHERE id = p_room;
  ELSIF p_action = 'pause' THEN
    UPDATE rooms SET song_paused_ms = greatest(0, (extract(epoch FROM (now() - song_started)) * 1000)::int)
    WHERE id = p_room AND song_url IS NOT NULL AND song_paused_ms IS NULL;
  ELSIF p_action = 'resume' THEN
    UPDATE rooms SET song_started = now() - make_interval(secs => song_paused_ms / 1000.0), song_paused_ms = NULL
    WHERE id = p_room AND song_url IS NOT NULL AND song_paused_ms IS NOT NULL;
  ELSIF p_action = 'stop' THEN
    UPDATE rooms SET song_title = NULL, song_artist = NULL, song_url = NULL,
                     song_started = NULL, song_paused_ms = NULL WHERE id = p_room;
  ELSE RAISE EXCEPTION 'bad action'; END IF;
END $$;

REVOKE ALL ON FUNCTION public.set_room_locked(uuid, boolean), public.room_visited(uuid), public.my_recent_rooms(),
  public.room_song(uuid, text, uuid), public.room_heartbeat(uuid), public.list_rooms(), public.server_time() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_room_locked(uuid, boolean), public.room_visited(uuid), public.my_recent_rooms(),
  public.room_song(uuid, text, uuid), public.room_heartbeat(uuid), public.list_rooms(), public.server_time() TO authenticated;

-- نتونس — التحديث 11: مكافآت مجانية (هدية يومية بإعلان، مهام يومية متبدّلة، روليت) + سعر «بدون إعلانات» 10000.
-- شغّله بعد voice_v10.sql (أو شغّل الملف الشامل voice_all_v4_to_v11.sql وحده). آمن لو أعدت تشغيله.

-- يوم العراق (يتبدّل عند منتصف الليل بتوقيت بغداد)
CREATE OR REPLACE FUNCTION public.bag_day() RETURNS date
LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date; $$;
CREATE OR REPLACE FUNCTION public.bag_day_start() RETURNS timestamptz
LANGUAGE sql STABLE AS $$ SELECT (public.bag_day()::timestamp AT TIME ZONE 'Asia/Baghdad'); $$;

-- ===== الإعدادات =====
INSERT INTO public.app_settings(key, value) VALUES
  ('daily_gems', '5'), ('missions_per_day', '3'),
  ('roulette_free', '1'), ('roulette_ad_spins', '3'),
  ('roulette', '[{"g":5,"w":22.5},{"g":10,"w":10},{"g":0,"w":12.5},{"g":20,"w":9.7},{"g":5,"w":22.5},{"g":10,"w":10},{"g":0,"w":12.5},{"g":100,"w":0.3}]')
ON CONFLICT (key) DO NOTHING;
-- سعر التخلص من الإعلانات 10000 (إن كان المدير لم يغيّره عن القديم 3000)
INSERT INTO public.app_settings(key, value) VALUES ('ads_free_price', '10000')
ON CONFLICT (key) DO UPDATE SET value = '10000' WHERE public.app_settings.value = '3000';

-- ===== 1) الهدية اليومية =====
CREATE TABLE IF NOT EXISTS public.daily_claims (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_day date NOT NULL,
  streak int NOT NULL DEFAULT 1
);
ALTER TABLE public.daily_claims ENABLE ROW LEVEL SECURITY;   -- بدون سياسات: عبر الدوال فقط

CREATE OR REPLACE FUNCTION public.daily_status()
RETURNS TABLE(available boolean, gems int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT EXISTS (SELECT 1 FROM daily_claims WHERE user_id = auth.uid() AND last_day = bag_day()),
         setting_int('daily_gems', 5);
$$;

-- يستدعيها التطبيق بعد مشاهدة الإعلان (أو مباشرة لمن اشترى «بدون إعلانات»)
CREATE OR REPLACE FUNCTION public.claim_daily()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g int := setting_int('daily_gems', 5); d date;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT last_day INTO d FROM daily_claims WHERE user_id = auth.uid() FOR UPDATE;
  IF d = bag_day() THEN RAISE EXCEPTION 'already claimed'; END IF;
  INSERT INTO daily_claims(user_id, last_day, streak) VALUES (auth.uid(), bag_day(), 1)
  ON CONFLICT (user_id) DO UPDATE SET last_day = bag_day(),
    streak = CASE WHEN daily_claims.last_day = bag_day() - 1 THEN daily_claims.streak + 1 ELSE 1 END;
  INSERT INTO wallets(user_id, gems) VALUES (auth.uid(), g)
  ON CONFLICT (user_id) DO UPDATE SET gems = wallets.gems + g;
  RETURN g;
END $$;

-- ===== 2) المهام (يضيفها المدير وتتبدّل كل 24 ساعة) =====
CREATE TABLE IF NOT EXISTS public.mission_pool (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 80),
  kind text NOT NULL CHECK (kind IN ('room_visit','play_game','send_gift','send_msg','watch_ad')),
  target int NOT NULL CHECK (target BETWEEN 1 AND 1000),
  reward int NOT NULL CHECK (reward BETWEEN 1 AND 1000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.mission_pool ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mp_read ON public.mission_pool;
CREATE POLICY mp_read ON public.mission_pool FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS mp_admin ON public.mission_pool;
CREATE POLICY mp_admin ON public.mission_pool FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mission_pool TO authenticated;

CREATE TABLE IF NOT EXISTS public.mission_claims (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL,
  mission_id uuid NOT NULL REFERENCES public.mission_pool(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, day, mission_id)
);
ALTER TABLE public.mission_claims ENABLE ROW LEVEL SECURITY;

INSERT INTO public.mission_pool(title, kind, target, reward)
SELECT * FROM (VALUES
  ('اقضِ 30 دقيقة في الغرف الصوتية', 'room_visit', 3, 3),
  ('العب 3 تحديات في خمّن الشخصية', 'play_game', 3, 3),
  ('أرسل هدية لأي شخص في غرفة', 'send_gift', 1, 2),
  ('اكتب 10 رسائل في الغرف', 'send_msg', 10, 2),
  ('شاهد إعلاناً من المكافآت', 'watch_ad', 1, 2),
  ('اقضِ ساعة كاملة في الغرف', 'room_visit', 6, 5)
) AS v(title, kind, target, reward)
WHERE NOT EXISTS (SELECT 1 FROM public.mission_pool);

-- سجل مشاهدات الإعلانات المكافئة (يزيده التطبيق عند مشاهدة إعلان من المكافآت)
CREATE TABLE IF NOT EXISTS public.ad_views (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL DEFAULT public.bag_day(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ad_views_idx ON public.ad_views(user_id, day);
ALTER TABLE public.ad_views ENABLE ROW LEVEL SECURITY;

-- تقدّم المستخدم اليوم في نوع معيّن
CREATE OR REPLACE FUNCTION public.mission_progress(p_kind text) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE p_kind
    WHEN 'room_visit' THEN (SELECT count(*)::int FROM xp_log WHERE user_id = auth.uid() AND kind = 'room' AND created_at >= bag_day_start())
    WHEN 'play_game'  THEN (SELECT count(*)::int FROM xp_log WHERE user_id = auth.uid() AND kind = 'game' AND created_at >= bag_day_start())
    WHEN 'send_gift'  THEN (SELECT coalesce(sum(qty),0)::int FROM gift_log WHERE from_id = auth.uid() AND created_at >= bag_day_start())
    WHEN 'send_msg'   THEN (SELECT count(*)::int FROM room_messages WHERE user_id = auth.uid() AND coalesce(kind,'text') = 'text' AND created_at >= bag_day_start())
    WHEN 'watch_ad'   THEN (SELECT count(*)::int FROM ad_views WHERE user_id = auth.uid() AND day = bag_day())
    ELSE 0 END;
$$;

-- مهام اليوم: n مهمة من المجموعة الفعّالة، تختلف كل يوم بترتيب ثابت لجميع المستخدمين
CREATE OR REPLACE FUNCTION public.my_missions()
RETURNS TABLE(id uuid, title text, kind text, target int, reward int, progress int, claimed boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT m.id, m.title, m.kind, m.target, m.reward,
         least(mission_progress(m.kind), m.target),
         EXISTS (SELECT 1 FROM mission_claims c WHERE c.user_id = auth.uid() AND c.day = bag_day() AND c.mission_id = m.id)
  FROM (SELECT * FROM mission_pool WHERE active
        ORDER BY md5(bag_day()::text || id::text) LIMIT setting_int('missions_per_day', 3)) m
  ORDER BY m.created_at;
$$;

CREATE OR REPLACE FUNCTION public.claim_mission(p_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m mission_pool%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO m FROM mission_pool WHERE id = p_id AND active
    AND id IN (SELECT x.id FROM mission_pool x WHERE x.active
               ORDER BY md5(bag_day()::text || x.id::text) LIMIT setting_int('missions_per_day', 3));
  IF NOT FOUND THEN RAISE EXCEPTION 'mission not available'; END IF;
  IF mission_progress(m.kind) < m.target THEN RAISE EXCEPTION 'not finished'; END IF;
  INSERT INTO mission_claims(user_id, day, mission_id) VALUES (auth.uid(), bag_day(), m.id);   -- مكرر = خطأ
  INSERT INTO wallets(user_id, gems) VALUES (auth.uid(), m.reward)
  ON CONFLICT (user_id) DO UPDATE SET gems = wallets.gems + m.reward;
  RETURN m.reward;
END $$;

-- ===== 3) الروليت =====
CREATE TABLE IF NOT EXISTS public.spin_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL DEFAULT public.bag_day(),
  via_ad boolean NOT NULL,
  seg int NOT NULL,
  gems int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS spin_log_idx ON public.spin_log(user_id, day);
ALTER TABLE public.spin_log ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.roulette_info()
RETURNS TABLE(segments jsonb, free_left int, ad_left int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (SELECT jsonb_agg(jsonb_build_object('g', e->'g')) FROM jsonb_array_elements(
            (SELECT value::jsonb FROM app_settings WHERE key = 'roulette')) e),
         greatest(0, setting_int('roulette_free', 1) - (SELECT count(*)::int FROM spin_log WHERE user_id = auth.uid() AND day = bag_day() AND NOT via_ad)),
         greatest(0, setting_int('roulette_ad_spins', 3) - (SELECT count(*)::int FROM spin_log WHERE user_id = auth.uid() AND day = bag_day() AND via_ad));
$$;

-- p_via_ad = true: محاولة إضافية بعد مشاهدة إعلان (أو مجانية لمن اشترى «بدون إعلانات»). تُرجع (رقم القطاع, الجواهر)
CREATE OR REPLACE FUNCTION public.roulette_spin(p_via_ad boolean)
RETURNS TABLE(seg int, gems int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE segs jsonb; n int; total numeric := 0; r numeric; acc numeric := 0; i int; pick int := 0; g int;
        free_used int; ad_used int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  PERFORM 1 FROM profiles WHERE id = auth.uid() FOR UPDATE;      -- يمنع الطلبات المتزامنة
  SELECT count(*) FILTER (WHERE NOT via_ad), count(*) FILTER (WHERE via_ad) INTO free_used, ad_used
    FROM spin_log WHERE user_id = auth.uid() AND day = bag_day();
  IF NOT p_via_ad THEN
    IF free_used >= setting_int('roulette_free', 1) THEN RAISE EXCEPTION 'no free spin'; END IF;
  ELSE
    IF ad_used >= setting_int('roulette_ad_spins', 3) THEN RAISE EXCEPTION 'no more spins today'; END IF;
  END IF;
  SELECT value::jsonb INTO segs FROM app_settings WHERE key = 'roulette';
  n := jsonb_array_length(segs);
  FOR i IN 0 .. n - 1 LOOP total := total + (segs->i->>'w')::numeric; END LOOP;
  r := random() * total;
  FOR i IN 0 .. n - 1 LOOP
    acc := acc + (segs->i->>'w')::numeric;
    IF r < acc THEN pick := i; EXIT; END IF;
  END LOOP;
  g := (segs->pick->>'g')::int;
  INSERT INTO spin_log(user_id, via_ad, seg, gems) VALUES (auth.uid(), p_via_ad, pick, g);
  IF g > 0 THEN
    INSERT INTO wallets(user_id, gems) VALUES (auth.uid(), g)
    ON CONFLICT (user_id) DO UPDATE SET gems = wallets.gems + g;
  END IF;
  RETURN QUERY SELECT pick, g;
END $$;

-- تسجيل مشاهدة إعلان مكافئ (لمهام «شاهد إعلاناً»)، بحد أقصى 20 يومياً
CREATE OR REPLACE FUNCTION public.log_ad_view() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF (SELECT count(*) FROM ad_views WHERE user_id = auth.uid() AND day = bag_day()) < 20 THEN
    INSERT INTO ad_views(user_id) VALUES (auth.uid());
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.daily_status(), public.claim_daily(), public.mission_progress(text), public.my_missions(),
  public.claim_mission(uuid), public.roulette_info(), public.roulette_spin(boolean), public.log_ad_view() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.daily_status(), public.claim_daily(), public.my_missions(),
  public.claim_mission(uuid), public.roulette_info(), public.roulette_spin(boolean), public.log_ad_view() TO authenticated;

-- ===== v12 =====
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS photos   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS tags     text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS birthday date;

GRANT UPDATE (photos, tags, birthday) ON public.profiles TO authenticated;
-- =====================================================================
-- v13: قفل الروم بكلمة مرور (يُفرض من الخادم)
--  • صاحب الروم يضع كلمة مرور (4-16 حرفاً)؛ من لا يعرفها لا يدخل
--  • من كان داخل الروم لحظة وضع الكلمة يبقى فيها
--  • بعد 5 محاولات خاطئة يُمنع المحاول 10 دقائق
--  • تغيير الكلمة أو إزالتها يلغي صلاحيات الدخول السابقة
-- آمن لو أعدت تشغيله
-- =====================================================================

-- أسرار الروم في جدول منفصل لا يقرؤه العملاء إطلاقاً
CREATE TABLE IF NOT EXISTS public.room_secrets (
  room_id uuid PRIMARY KEY REFERENCES public.rooms(id) ON DELETE CASCADE,
  salt text NOT NULL,
  hash text NOT NULL,
  ver  int  NOT NULL DEFAULT 1
);
ALTER TABLE public.room_secrets ENABLE ROW LEVEL SECURITY;   -- بدون سياسات

CREATE TABLE IF NOT EXISTS public.room_access (
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ver int NOT NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);
ALTER TABLE public.room_access ENABLE ROW LEVEL SECURITY;    -- بدون سياسات

CREATE TABLE IF NOT EXISTS public.room_pass_attempts (
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  fails int NOT NULL DEFAULT 0,
  blocked_until timestamptz,
  PRIMARY KEY (room_id, user_id)
);
ALTER TABLE public.room_pass_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._room_hash(p_salt text, p_pass text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT encode(sha256(convert_to(p_salt || ':' || p_pass, 'UTF8')), 'hex') $$;

-- هل يستطيع المستخدم الحالي دخول الروم؟
CREATE OR REPLACE FUNCTION public.can_enter_room(p_room uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE lk boolean; hid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  SELECT locked, host_id INTO lk, hid FROM rooms WHERE id = p_room;
  IF NOT FOUND THEN RETURN false; END IF;
  IF NOT lk OR hid = auth.uid() THEN RETURN true; END IF;
  RETURN EXISTS (
    SELECT 1 FROM room_access a JOIN room_secrets s ON s.room_id = a.room_id AND s.ver = a.ver
    WHERE a.room_id = p_room AND a.user_id = auth.uid());
END $$;

-- وضع / تغيير / إزالة كلمة المرور (للمالك فقط). كلمة فارغة = إزالة القفل
CREATE OR REPLACE FUNCTION public.set_room_password(p_room uuid, p_pass text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE hid uuid; pw text := coalesce(btrim(p_pass), ''); s text; v int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT host_id INTO hid FROM rooms WHERE id = p_room;
  IF NOT FOUND OR hid <> auth.uid() THEN RAISE EXCEPTION 'owner only'; END IF;
  IF pw = '' THEN
    UPDATE rooms SET locked = false WHERE id = p_room;
    DELETE FROM room_secrets WHERE room_id = p_room;
    DELETE FROM room_access WHERE room_id = p_room;
    DELETE FROM room_pass_attempts WHERE room_id = p_room;
    RETURN;
  END IF;
  IF char_length(pw) < 4 OR char_length(pw) > 16 THEN RAISE EXCEPTION 'bad password'; END IF;
  s := gen_random_uuid()::text;
  SELECT coalesce(max(ver), 0) + 1 INTO v FROM room_secrets WHERE room_id = p_room;
  INSERT INTO room_secrets(room_id, salt, hash, ver) VALUES (p_room, s, _room_hash(s, pw), v)
  ON CONFLICT (room_id) DO UPDATE SET salt = excluded.salt, hash = excluded.hash, ver = excluded.ver;
  UPDATE rooms SET locked = true WHERE id = p_room;
  DELETE FROM room_access WHERE room_id = p_room;
  DELETE FROM room_pass_attempts WHERE room_id = p_room;
  -- الموجودون الآن داخل الروم يبقون فيها
  INSERT INTO room_access(room_id, user_id, ver)
  SELECT p_room, m.user_id, v FROM room_members m
  WHERE m.room_id = p_room AND m.user_id <> hid AND m.last_seen > now() - interval '60 seconds'
  ON CONFLICT DO NOTHING;
END $$;

-- محاولة الدخول بكلمة مرور. ترجع: ok | wrong:<المتبقي> | blocked
CREATE OR REPLACE FUNCTION public.join_room_with_password(p_room uuid, p_pass text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE hid uuid; sec room_secrets%ROWTYPE; att room_pass_attempts%ROWTYPE; f int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT host_id INTO hid FROM rooms WHERE id = p_room AND is_live;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not live'; END IF;
  IF hid = auth.uid() THEN RETURN 'ok'; END IF;
  IF EXISTS (SELECT 1 FROM room_flags WHERE room_id = p_room AND user_id = auth.uid() AND kicked_until > now()) THEN
    RAISE EXCEPTION 'kicked';
  END IF;
  SELECT * INTO sec FROM room_secrets WHERE room_id = p_room;
  IF NOT FOUND THEN RETURN 'ok'; END IF;
  SELECT * INTO att FROM room_pass_attempts WHERE room_id = p_room AND user_id = auth.uid();
  IF FOUND AND att.blocked_until IS NOT NULL AND att.blocked_until > now() THEN RETURN 'blocked'; END IF;
  IF _room_hash(sec.salt, coalesce(p_pass, '')) = sec.hash THEN
    INSERT INTO room_access(room_id, user_id, ver) VALUES (p_room, auth.uid(), sec.ver)
    ON CONFLICT (room_id, user_id) DO UPDATE SET ver = excluded.ver, granted_at = now();
    DELETE FROM room_pass_attempts WHERE room_id = p_room AND user_id = auth.uid();
    RETURN 'ok';
  END IF;
  f := coalesce(att.fails, 0) + 1;
  IF f >= 5 THEN
    INSERT INTO room_pass_attempts(room_id, user_id, fails, blocked_until)
    VALUES (p_room, auth.uid(), 0, now() + interval '10 minutes')
    ON CONFLICT (room_id, user_id) DO UPDATE SET fails = 0, blocked_until = now() + interval '10 minutes';
    RETURN 'blocked';
  END IF;
  INSERT INTO room_pass_attempts(room_id, user_id, fails) VALUES (p_room, auth.uid(), f)
  ON CONFLICT (room_id, user_id) DO UPDATE SET fails = f, blocked_until = NULL;
  RETURN 'wrong:' || (5 - f);
END $$;

-- القفل القديم (بدون كلمة) لم يعد موجوداً: النسخ القديمة من التطبيق لا تستطيع إغلاق الروم بلا كلمة
CREATE OR REPLACE FUNCTION public.set_room_locked(p_room uuid, p_locked boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_locked THEN RAISE EXCEPTION 'update the app'; END IF;
  PERFORM set_room_password(p_room, NULL);
END $$;

-- التحقق عند كل نبضة: صلاحية الدخول بدل «كان عضواً من قبل»
CREATE OR REPLACE FUNCTION public.room_heartbeat(p_room uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE live boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF EXISTS (SELECT 1 FROM room_flags WHERE room_id = p_room AND user_id = auth.uid() AND kicked_until > now()) THEN
    RAISE EXCEPTION 'kicked';
  END IF;
  SELECT is_live INTO live FROM rooms WHERE id = p_room;
  IF live IS NOT TRUE THEN RETURN false; END IF;
  IF NOT can_enter_room(p_room) THEN RAISE EXCEPTION 'room locked'; END IF;
  INSERT INTO room_members(room_id, user_id, last_seen) VALUES (p_room, auth.uid(), now())
  ON CONFLICT (room_id, user_id) DO UPDATE SET last_seen = now();
  DELETE FROM room_seats s WHERE s.room_id = p_room AND NOT EXISTS (
    SELECT 1 FROM room_members m WHERE m.room_id = s.room_id AND m.user_id = s.user_id
      AND m.last_seen > now() - interval '45 seconds');
  RETURN true;
END $$;

-- الأقفال القديمة (بلا كلمة مرور) تُفتح لأن القفل صار بكلمة فقط
UPDATE public.rooms r SET locked = false
WHERE r.locked AND NOT EXISTS (SELECT 1 FROM public.room_secrets s WHERE s.room_id = r.id);

REVOKE ALL ON FUNCTION public.can_enter_room(uuid), public.set_room_password(uuid, text),
  public.join_room_with_password(uuid, text), public.set_room_locked(uuid, boolean),
  public.room_heartbeat(uuid), public._room_hash(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_enter_room(uuid), public.set_room_password(uuid, text),
  public.join_room_with_password(uuid, text), public.set_room_locked(uuid, boolean),
  public.room_heartbeat(uuid) TO authenticated;
-- =====================================================================
-- v14: خلفيات الروم من لوحة المدير (مجانية أو بسعر بالجواهر)
--  • المدير يضيف/يحذف/يعدّل الخلفيات وأسعارها
--  • صاحب الروم يشتري الخلفية مرة واحدة فتبقى له، ثم يطبّقها على رومه
--  • آمن لو أعدت تشغيله
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.room_backgrounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
  image_url text NOT NULL,
  price int NOT NULL DEFAULT 0 CHECK (price >= 0),
  sort int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.room_backgrounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rbg_read ON public.room_backgrounds;
DROP POLICY IF EXISTS rbg_admin ON public.room_backgrounds;
CREATE POLICY rbg_read ON public.room_backgrounds FOR SELECT TO authenticated USING (active OR public.is_admin());
CREATE POLICY rbg_admin ON public.room_backgrounds FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.room_backgrounds TO authenticated;

CREATE TABLE IF NOT EXISTS public.user_backgrounds (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  bg_id uuid NOT NULL REFERENCES public.room_backgrounds(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, bg_id)
);
ALTER TABLE public.user_backgrounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ubg_read ON public.user_backgrounds;
CREATE POLICY ubg_read ON public.user_backgrounds FOR SELECT TO authenticated USING (user_id = auth.uid());
GRANT SELECT ON public.user_backgrounds TO authenticated;

-- شراء خلفية (مرة واحدة). المجانية لا تحتاج شراء.
CREATE OR REPLACE FUNCTION public.buy_room_background(p_bg uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b room_backgrounds%ROWTYPE; w int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO b FROM room_backgrounds WHERE id = p_bg AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'bad background'; END IF;
  IF b.price = 0 OR EXISTS (SELECT 1 FROM user_backgrounds WHERE user_id = auth.uid() AND bg_id = p_bg) THEN RETURN; END IF;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < b.price THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - b.price WHERE user_id = auth.uid();
  INSERT INTO user_backgrounds(user_id, bg_id) VALUES (auth.uid(), p_bg) ON CONFLICT DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.buy_room_background(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buy_room_background(uuid) TO authenticated;

-- تطبيق الخلفية: إن كانت صورة من الكتالوج وبسعر فلا تُطبَّق إلا لمن اشتراها
CREATE OR REPLACE FUNCTION public.room_set_look(p_room uuid, p_bg_preset text, p_bg_url text,
                                                p_mic_skin text, p_mic_skin_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF nullif(p_bg_url, '') IS NOT NULL AND EXISTS (
       SELECT 1 FROM room_backgrounds b
       WHERE b.image_url = p_bg_url AND b.price > 0
         AND NOT EXISTS (SELECT 1 FROM user_backgrounds u WHERE u.bg_id = b.id AND u.user_id = auth.uid())
     ) THEN
    RAISE EXCEPTION 'background locked';
  END IF;
  UPDATE rooms SET bg_preset = coalesce(nullif(p_bg_preset, ''), 'violet'),
                   bg_url = nullif(p_bg_url, ''),
                   mic_skin = coalesce(nullif(p_mic_skin, ''), 'none'),
                   mic_skin_url = nullif(p_mic_skin_url, '')
  WHERE id = p_room AND host_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'owner only'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.room_set_look(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.room_set_look(uuid, text, text, text, text) TO authenticated;
