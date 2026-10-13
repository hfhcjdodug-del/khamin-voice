-- voice_games.sql — قسم الألعاب (خمّن الشخصية) + لوحة المدير.
-- يُشغَّل بعد voice_update.sql. لا يحذف بيانات.

-- ===== المديرون =====
CREATE TABLE IF NOT EXISTS public.app_admins (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE
);
ALTER TABLE public.app_admins ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM app_admins WHERE user_id = auth.uid());
$$;

-- ===== الفئات والصور =====
CREATE TABLE IF NOT EXISTS public.game_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 40),
  cover_url text,
  sort int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.game_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid REFERENCES public.game_categories(id) ON DELETE CASCADE,
  url text NOT NULL,
  label text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS game_images_cat_idx ON public.game_images (category_id);

ALTER TABLE public.game_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gc_read ON public.game_categories;
DROP POLICY IF EXISTS gc_admin ON public.game_categories;
DROP POLICY IF EXISTS gi_read ON public.game_images;
DROP POLICY IF EXISTS gi_admin ON public.game_images;
CREATE POLICY gc_read ON public.game_categories FOR SELECT TO authenticated USING (active OR public.is_admin());
CREATE POLICY gc_admin ON public.game_categories FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY gi_read ON public.game_images FOR SELECT TO authenticated USING (true);
CREATE POLICY gi_admin ON public.game_images FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.game_categories, public.game_images TO authenticated;

INSERT INTO public.game_categories(name, sort)
SELECT v.n, v.s FROM (VALUES ('لاعبو كرة القدم',1), ('مشاهير وممثلون',2), ('مغنّون وفنانون',3), ('كرتون وأنمي',4)) AS v(n, s)
WHERE NOT EXISTS (SELECT 1 FROM public.game_categories);

-- ===== المباريات (الوصول عبر دوال فقط حتى لا تُكشف الصور السرية) =====
CREATE TABLE IF NOT EXISTS public.game_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid REFERENCES public.game_categories(id) ON DELETE SET NULL,
  player1 uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  player2 uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  image1 uuid REFERENCES public.game_images(id) ON DELETE SET NULL,
  image2 uuid REFERENCES public.game_images(id) ON DELETE SET NULL,
  reveal1 boolean NOT NULL DEFAULT false,
  reveal2 boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','finished')),
  created_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  CHECK (player1 <> player2)
);
CREATE INDEX IF NOT EXISTS game_matches_p1 ON public.game_matches (player1, status);
CREATE INDEX IF NOT EXISTS game_matches_p2 ON public.game_matches (player2, status);
ALTER TABLE public.game_matches ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.game_queue (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  category_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.game_queue ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.game_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_user uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category_id uuid,
  match_id uuid,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined','expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (from_user <> to_user)
);
CREATE INDEX IF NOT EXISTS game_invites_to ON public.game_invites (to_user, status);
ALTER TABLE public.game_invites ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.game_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id uuid NOT NULL REFERENCES public.game_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 300),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS game_messages_idx ON public.game_messages (match_id, id DESC);
ALTER TABLE public.game_messages ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.in_match(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM game_matches m WHERE m.id = p_id AND auth.uid() IN (m.player1, m.player2));
$$;

CREATE OR REPLACE FUNCTION public.match_is_active(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM game_matches m WHERE m.id = p_id AND m.status = 'active' AND auth.uid() IN (m.player1, m.player2));
$$;

DROP POLICY IF EXISTS gm_read ON public.game_messages;
DROP POLICY IF EXISTS gm_insert ON public.game_messages;
CREATE POLICY gm_read ON public.game_messages FOR SELECT TO authenticated USING (public.in_match(match_id));
CREATE POLICY gm_insert ON public.game_messages FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.match_is_active(match_id));
GRANT SELECT, INSERT ON public.game_messages TO authenticated;

-- ===== دوال اللعبة =====
CREATE OR REPLACE FUNCTION public._create_match(p1 uuid, p2 uuid, p_cat uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i1 uuid; i2 uuid; mid uuid;
BEGIN
  UPDATE game_matches SET status = 'finished', ended_at = now()
   WHERE status = 'active' AND (player1 IN (p1, p2) OR player2 IN (p1, p2));
  SELECT id INTO i1 FROM game_images WHERE (p_cat IS NULL OR category_id = p_cat) ORDER BY random() LIMIT 1;
  SELECT id INTO i2 FROM game_images WHERE (p_cat IS NULL OR category_id = p_cat) AND id <> i1 ORDER BY random() LIMIT 1;
  IF i1 IS NULL OR i2 IS NULL THEN RAISE EXCEPTION 'not enough images'; END IF;
  INSERT INTO game_matches(category_id, player1, player2, image1, image2)
  VALUES (p_cat, p1, p2, i1, i2) RETURNING id INTO mid;
  RETURN mid;
END $$;

CREATE OR REPLACE FUNCTION public.quick_match(p_cat uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE me uuid := auth.uid(); mid uuid; other uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT id INTO mid FROM game_matches
   WHERE status = 'active' AND me IN (player1, player2) AND created_at > now() - interval '3 hours'
   ORDER BY created_at DESC LIMIT 1;
  IF mid IS NOT NULL THEN RETURN mid; END IF;

  SELECT user_id INTO other FROM game_queue
   WHERE user_id <> me AND category_id IS NOT DISTINCT FROM p_cat AND created_at > now() - interval '10 seconds'
   ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF other IS NOT NULL THEN
    DELETE FROM game_queue WHERE user_id IN (me, other);
    RETURN public._create_match(other, me, p_cat);
  END IF;

  INSERT INTO game_queue(user_id, category_id, created_at) VALUES (me, p_cat, now())
  ON CONFLICT (user_id) DO UPDATE SET category_id = EXCLUDED.category_id, created_at = now();
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_queue() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM game_queue WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.match_view(p_id uuid)
RETURNS TABLE(id uuid, status text, category_name text, opponent_id uuid, opponent_name text,
              opponent_avatar text, opponent_image text, my_image text, reveal_me boolean, reveal_opp boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT m.id, m.status, c.name, o.id, o.name, o.avatar_url,
         oi.url,
         CASE WHEN (CASE WHEN m.player1 = auth.uid() THEN m.reveal1 ELSE m.reveal2 END) THEN mi.url END,
         (CASE WHEN m.player1 = auth.uid() THEN m.reveal1 ELSE m.reveal2 END),
         (CASE WHEN m.player1 = auth.uid() THEN m.reveal2 ELSE m.reveal1 END)
  FROM game_matches m
  JOIN profiles o ON o.id = CASE WHEN m.player1 = auth.uid() THEN m.player2 ELSE m.player1 END
  LEFT JOIN game_images oi ON oi.id = CASE WHEN m.player1 = auth.uid() THEN m.image2 ELSE m.image1 END
  LEFT JOIN game_images mi ON mi.id = CASE WHEN m.player1 = auth.uid() THEN m.image1 ELSE m.image2 END
  LEFT JOIN game_categories c ON c.id = m.category_id
  WHERE m.id = p_id AND auth.uid() IN (m.player1, m.player2);
$$;

CREATE OR REPLACE FUNCTION public.reveal_mine(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE game_matches SET
    reveal1 = reveal1 OR (player1 = auth.uid()),
    reveal2 = reveal2 OR (player2 = auth.uid())
  WHERE id = p_id AND status = 'active' AND auth.uid() IN (player1, player2);
$$;

CREATE OR REPLACE FUNCTION public.leave_match(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE game_matches SET status = 'finished', ended_at = now()
  WHERE id = p_id AND status = 'active' AND auth.uid() IN (player1, player2);
$$;

CREATE OR REPLACE FUNCTION public.my_following()
RETURNS TABLE(id uuid, name text, username text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.name, p.username, p.avatar_url
  FROM follows f JOIN profiles p ON p.id = f.followee
  WHERE f.follower = auth.uid() ORDER BY f.created_at DESC LIMIT 200;
$$;

CREATE OR REPLACE FUNCTION public.send_invite(p_to uuid, p_cat uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE iid uuid;
BEGIN
  IF auth.uid() = p_to THEN RAISE EXCEPTION 'self'; END IF;
  UPDATE game_invites SET status = 'expired' WHERE from_user = auth.uid() AND status = 'pending';
  INSERT INTO game_invites(from_user, to_user, category_id) VALUES (auth.uid(), p_to, p_cat) RETURNING id INTO iid;
  RETURN iid;
END $$;

CREATE OR REPLACE FUNCTION public.my_invites()
RETURNS TABLE(id uuid, from_id uuid, from_name text, from_avatar text, category_name text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT i.id, p.id, p.name, p.avatar_url, COALESCE(c.name, 'منوّع'), i.created_at
  FROM game_invites i JOIN profiles p ON p.id = i.from_user
  LEFT JOIN game_categories c ON c.id = i.category_id
  WHERE i.to_user = auth.uid() AND i.status = 'pending' AND i.created_at > now() - interval '2 minutes'
  ORDER BY i.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.accept_invite(p_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inv game_invites%ROWTYPE; mid uuid;
BEGIN
  SELECT * INTO inv FROM game_invites
   WHERE id = p_id AND to_user = auth.uid() AND status = 'pending' AND created_at > now() - interval '2 minutes'
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invite expired'; END IF;
  mid := public._create_match(inv.from_user, auth.uid(), inv.category_id);
  UPDATE game_invites SET status = 'accepted', match_id = mid WHERE id = p_id;
  RETURN mid;
END $$;

CREATE OR REPLACE FUNCTION public.decline_invite(p_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE game_invites SET status = 'declined' WHERE id = p_id AND to_user = auth.uid() AND status = 'pending';
$$;

CREATE OR REPLACE FUNCTION public.invite_status(p_id uuid)
RETURNS TABLE(status text, match_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN i.status = 'pending' AND i.created_at < now() - interval '2 minutes' THEN 'expired' ELSE i.status END, i.match_id
  FROM game_invites i WHERE i.id = p_id AND i.from_user = auth.uid();
$$;

-- ===== لوحة المدير =====
CREATE OR REPLACE FUNCTION public.am_i_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT public.is_admin(); $$;

CREATE OR REPLACE FUNCTION public.admin_stats() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN jsonb_build_object(
    'users', (SELECT count(*) FROM profiles),
    'users_today', (SELECT count(*) FROM profiles WHERE created_at > now() - interval '1 day'),
    'live_rooms', (SELECT count(*) FROM list_rooms()),
    'matches_today', (SELECT count(*) FROM game_matches WHERE created_at > now() - interval '1 day'),
    'active_matches', (SELECT count(*) FROM game_matches WHERE status = 'active' AND created_at > now() - interval '3 hours'),
    'categories', (SELECT count(*) FROM game_categories),
    'images', (SELECT count(*) FROM game_images)
  );
END $$;

CREATE OR REPLACE FUNCTION public.admin_end_room(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  UPDATE rooms SET is_live = false WHERE id = p_id;
END $$;

-- ===== التخزين: صور الألعاب (قراءة للجميع، كتابة للمدير) =====
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public) VALUES ('game-media', 'game-media', true) ON CONFLICT (id) DO NOTHING;
  DROP POLICY IF EXISTS "game_media_read" ON storage.objects;
  DROP POLICY IF EXISTS "game_media_admin_ins" ON storage.objects;
  DROP POLICY IF EXISTS "game_media_admin_upd" ON storage.objects;
  DROP POLICY IF EXISTS "game_media_admin_del" ON storage.objects;
  CREATE POLICY "game_media_read" ON storage.objects FOR SELECT USING (bucket_id = 'game-media');
  CREATE POLICY "game_media_admin_ins" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'game-media' AND public.is_admin());
  CREATE POLICY "game_media_admin_upd" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'game-media' AND public.is_admin());
  CREATE POLICY "game_media_admin_del" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'game-media' AND public.is_admin());
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'storage setup skipped: %', SQLERRM;
END $$;

-- ===== الصلاحيات =====
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon, public;
REVOKE EXECUTE ON FUNCTION public._create_match(uuid, uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION
  public.is_admin(), public.in_match(uuid), public.match_is_active(uuid), public.quick_match(uuid), public.cancel_queue(),
  public.match_view(uuid), public.reveal_mine(uuid), public.leave_match(uuid), public.my_following(),
  public.send_invite(uuid, uuid), public.my_invites(), public.accept_invite(uuid), public.decline_invite(uuid),
  public.invite_status(uuid), public.am_i_admin(), public.admin_stats(), public.admin_end_room(uuid)
TO authenticated;
