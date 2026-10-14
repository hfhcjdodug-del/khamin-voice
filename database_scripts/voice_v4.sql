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
