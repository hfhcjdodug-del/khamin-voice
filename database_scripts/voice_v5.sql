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
