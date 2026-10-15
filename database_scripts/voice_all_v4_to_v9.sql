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
