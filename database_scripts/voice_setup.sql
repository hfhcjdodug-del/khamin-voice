-- voice_setup.sql — قاعدة بيانات تطبيق الدردشة الصوتية
-- ⚠️ يحذف كل ما في schema public (جداول اللعبة القديمة) ثم ينشئ الجداول الجديدة.
-- حسابات الدخول (auth) لا تُحذف.

DO $$
DECLARE r record;
BEGIN
  BEGIN
    FOR r IN SELECT jobid FROM cron.job LOOP PERFORM cron.unschedule(r.jobid); END LOOP;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;

DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, service_role;

-- ===== الجداول =====
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL DEFAULT 'ضيف',
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 60),
  topic text NOT NULL DEFAULT '' CHECK (char_length(topic) <= 120),
  host_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_live boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.room_members (
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_seen timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);

CREATE TABLE public.room_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON public.room_messages (room_id, id DESC);
CREATE INDEX ON public.room_members (room_id, last_seen);

-- ===== إنشاء الملف الشخصي تلقائياً عند التسجيل =====
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n text;
BEGIN
  n := NULLIF(trim(COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', '')), '');
  IF n IS NULL THEN n := 'ضيف ' || (floor(random()*9000)+1000)::int; END IF;
  INSERT INTO public.profiles(id, name, avatar_url)
  VALUES (NEW.id, left(n, 40), COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture'))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- حسابات موجودة مسبقاً (من اللعبة/المتجر) تحصل على ملف شخصي
INSERT INTO public.profiles(id, name, avatar_url)
SELECT u.id,
       left(COALESCE(NULLIF(trim(COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name','')),''), 'ضيف ' || (floor(random()*9000)+1000)::int), 40),
       COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture')
FROM auth.users u ON CONFLICT (id) DO NOTHING;

-- ===== دوال =====
-- قائمة الغرف المباشرة مع عدد المستمعين (من شوهدوا خلال 45 ثانية)
CREATE OR REPLACE FUNCTION public.list_rooms()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text, listeners int, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') AS listeners,
         r.created_at
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 7 DESC, r.created_at DESC
  LIMIT 100;
$$;

-- دخول الغرفة + نبضة الحضور (تُستدعى كل 15 ثانية)
CREATE OR REPLACE FUNCTION public.room_heartbeat(p_room uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE live boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT is_live INTO live FROM rooms WHERE id = p_room;
  IF live IS NOT TRUE THEN RETURN false; END IF;
  INSERT INTO room_members(room_id, user_id, last_seen) VALUES (p_room, auth.uid(), now())
  ON CONFLICT (room_id, user_id) DO UPDATE SET last_seen = now();
  RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.leave_room(p_room uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM room_members WHERE room_id = p_room AND user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.end_room(p_room uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE rooms SET is_live = false WHERE id = p_room AND host_id = auth.uid();
$$;

-- ===== الأمان (RLS) =====
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_read ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY profiles_update ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY rooms_read ON public.rooms FOR SELECT TO authenticated USING (true);
CREATE POLICY rooms_insert ON public.rooms FOR INSERT TO authenticated WITH CHECK (host_id = auth.uid());
CREATE POLICY rooms_update ON public.rooms FOR UPDATE TO authenticated USING (host_id = auth.uid()) WITH CHECK (host_id = auth.uid());

CREATE POLICY members_read ON public.room_members FOR SELECT TO authenticated USING (true);

CREATE POLICY messages_read ON public.room_messages FOR SELECT TO authenticated USING (true);
CREATE POLICY messages_insert ON public.room_messages FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM public.rooms r WHERE r.id = room_id AND r.is_live));

-- منع الاستدعاء من المستخدمين غير المسجلين
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon, public;
GRANT EXECUTE ON FUNCTION public.list_rooms(), public.room_heartbeat(uuid), public.leave_room(uuid), public.end_room(uuid) TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles, public.rooms TO authenticated;
GRANT SELECT ON public.room_members TO authenticated;
GRANT SELECT, INSERT ON public.room_messages TO authenticated;

-- ===== الوقت الحقيقي (Realtime) للرسائل =====
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.room_messages;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
