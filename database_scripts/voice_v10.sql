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
