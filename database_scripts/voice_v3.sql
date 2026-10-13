-- =====================================================================
-- voice_v3.sql : أغلفة وأغاني الألعاب + شارة التوثيق + صور الحسابات + الأفلام المشتركة
-- شغّله مرة واحدة في Supabase → SQL Editor (آمن لو أعدته)
-- =====================================================================

-- ===== 1) الألعاب (غلاف + أغنية يتحكم بها المدير) =====
CREATE TABLE IF NOT EXISTS public.games (
  id text PRIMARY KEY,
  title text NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  cover_url text,
  music_url text,
  ready boolean NOT NULL DEFAULT false,
  sort int NOT NULL DEFAULT 0
);
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS games_read ON public.games;
DROP POLICY IF EXISTS games_admin ON public.games;
CREATE POLICY games_read ON public.games FOR SELECT TO authenticated USING (true);
CREATE POLICY games_admin ON public.games FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.games TO authenticated;

INSERT INTO public.games(id, title, subtitle, ready, sort) VALUES
  ('guess', 'خمّن الشخصية', 'اعرف شخصيتك بأسئلة نعم/لا', true, 1),
  ('xo', 'إكس أو', 'تحدَّ صديقك', false, 2),
  ('rps', 'حجرة ورقة مقص', 'من الأسرع بديهة؟', false, 3)
ON CONFLICT (id) DO NOTHING;

-- ===== 2) شارة التوثيق =====
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS verified boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.admin_set_verified(p_id uuid, p_v boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE profiles SET verified = p_v WHERE id = p_id;
END $$;

DROP FUNCTION IF EXISTS public.get_profile(uuid);
CREATE FUNCTION public.get_profile(p_id uuid)
RETURNS TABLE(id uuid, name text, username text, num bigint, avatar_url text, bio text,
              followers int, following int, is_following boolean, verified boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.name, p.username, p.num, p.avatar_url, p.bio,
         (SELECT count(*)::int FROM follows f WHERE f.followee = p.id),
         (SELECT count(*)::int FROM follows f WHERE f.follower = p.id),
         EXISTS (SELECT 1 FROM follows f WHERE f.follower = auth.uid() AND f.followee = p.id),
         p.verified
  FROM profiles p WHERE p.id = p_id;
$$;

-- ===== 3) الأفلام والمشاهدة المشتركة =====
CREATE TABLE IF NOT EXISTS public.movies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  poster_url text,
  video_url text NOT NULL,
  subtitle_url text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.movies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS movies_read ON public.movies;
DROP POLICY IF EXISTS movies_admin ON public.movies;
CREATE POLICY movies_read ON public.movies FOR SELECT TO authenticated USING (active OR public.is_admin());
CREATE POLICY movies_admin ON public.movies FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.movies TO authenticated;

CREATE TABLE IF NOT EXISTS public.watch_parties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  guest_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  movie_id uuid NOT NULL REFERENCES public.movies(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','active','ended','declined')),
  playing boolean NOT NULL DEFAULT false,
  pos_ms bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.watch_parties ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS wp_read ON public.watch_parties;
CREATE POLICY wp_read ON public.watch_parties FOR SELECT TO authenticated
  USING (host_id = auth.uid() OR guest_id = auth.uid());
GRANT SELECT ON public.watch_parties TO authenticated;
-- الكتابة عبر الدوال فقط

CREATE OR REPLACE FUNCTION public.party_invite(p_movie uuid, p_guest uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pid uuid;
BEGIN
  IF auth.uid() = p_guest THEN RAISE EXCEPTION 'self'; END IF;
  IF NOT EXISTS (SELECT 1 FROM movies WHERE id = p_movie AND active) THEN RAISE EXCEPTION 'no movie'; END IF;
  UPDATE watch_parties SET status = 'ended' WHERE host_id = auth.uid() AND status IN ('invited','active');
  INSERT INTO watch_parties(host_id, guest_id, movie_id) VALUES (auth.uid(), p_guest, p_movie) RETURNING id INTO pid;
  RETURN pid;
END $$;

CREATE OR REPLACE FUNCTION public.party_invites()
RETURNS TABLE(id uuid, host_id uuid, host_name text, host_avatar text, movie_title text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT w.id, p.id, p.name, p.avatar_url, m.title, w.created_at
  FROM watch_parties w JOIN profiles p ON p.id = w.host_id JOIN movies m ON m.id = w.movie_id
  WHERE w.guest_id = auth.uid() AND w.status = 'invited' AND w.created_at > now() - interval '5 minutes'
  ORDER BY w.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.party_accept(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE watch_parties SET status = 'active', updated_at = now()
   WHERE id = p_id AND guest_id = auth.uid() AND status = 'invited' AND created_at > now() - interval '5 minutes';
  IF NOT FOUND THEN RAISE EXCEPTION 'invite expired'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.party_decline(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE watch_parties SET status = 'declined' WHERE id = p_id AND guest_id = auth.uid() AND status = 'invited';
$$;

-- صاحب الدعوة فقط يتحكم بالتشغيل/الإيقاف/التقديم
CREATE OR REPLACE FUNCTION public.party_sync(p_id uuid, p_playing boolean, p_pos bigint) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE watch_parties SET playing = p_playing, pos_ms = greatest(p_pos, 0), updated_at = now()
   WHERE id = p_id AND host_id = auth.uid() AND status IN ('invited','active');
$$;

CREATE OR REPLACE FUNCTION public.party_end(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE watch_parties SET status = 'ended', playing = false, updated_at = now()
   WHERE id = p_id AND (host_id = auth.uid() OR guest_id = auth.uid()) AND status IN ('invited','active');
$$;

REVOKE ALL ON FUNCTION public.admin_set_verified(uuid, boolean), public.party_invite(uuid, uuid), public.party_invites(),
  public.party_accept(uuid), public.party_decline(uuid), public.party_sync(uuid, boolean, bigint), public.party_end(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_verified(uuid, boolean), public.party_invite(uuid, uuid), public.party_invites(),
  public.party_accept(uuid), public.party_decline(uuid), public.party_sync(uuid, boolean, bigint), public.party_end(uuid),
  public.get_profile(uuid) TO authenticated;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.watch_parties; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ===== 4) صور الحسابات (كل مستخدم في مجلده) =====
DO $$ BEGIN
  INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT (id) DO NOTHING;
  DROP POLICY IF EXISTS "avatars_read" ON storage.objects;
  DROP POLICY IF EXISTS "avatars_ins" ON storage.objects;
  DROP POLICY IF EXISTS "avatars_upd" ON storage.objects;
  DROP POLICY IF EXISTS "avatars_del" ON storage.objects;
  CREATE POLICY "avatars_read" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
  CREATE POLICY "avatars_ins" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
  CREATE POLICY "avatars_upd" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
  CREATE POLICY "avatars_del" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'storage setup skipped: %', SQLERRM;
END $$;

-- ===== 5) الموسيقى والأفلام تُرفع إلى game-media (المدير فقط) — موجود مسبقاً =====
