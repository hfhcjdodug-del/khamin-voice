-- نستأنس — التحديث 20: الجولات المجانية والماسات والإعلانات + شرح طريقة اللعب
-- آمن لو أعدت تشغيله. شغّله مرة واحدة في SQL Editor.

-- ===== الإعدادات (يعدّلها المدير من لوحة التحكم) =====
INSERT INTO public.app_settings(key, value) VALUES
  ('free_rounds_daily', '5'),       -- جولات مجانية يومياً
  ('ad_round_max', '10'),           -- أقصى جولات إضافية بمشاهدة إعلان يومياً
  ('ad_gems_amount', '10'),         -- ماسات مقابل إعلان واحد
  ('ad_gems_max', '20'),            -- أقصى عدد إعلانات للماسات يومياً
  ('pass_day_price', '100'),        -- سعر اللعب المفتوح ليوم
  ('pass_week_price', '500'),
  ('pass_month_price', '1500')
ON CONFLICT (key) DO NOTHING;

-- ===== جداول =====
CREATE TABLE IF NOT EXISTS public.play_rounds (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL,
  used int NOT NULL DEFAULT 0,
  bonus int NOT NULL DEFAULT 0,        -- جولات إضافية من إعلانات
  ad_gems int NOT NULL DEFAULT 0,      -- عدد إعلانات الماسات اليوم
  PRIMARY KEY (user_id, day)
);
ALTER TABLE public.play_rounds ENABLE ROW LEVEL SECURITY;   -- عبر الدوال فقط

CREATE TABLE IF NOT EXISTS public.play_pass (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  until timestamptz NOT NULL
);
ALTER TABLE public.play_pass ENABLE ROW LEVEL SECURITY;

-- ===== حالة اللعب =====
CREATE OR REPLACE FUNCTION public._can_play(p_uid uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM app_admins WHERE user_id = p_uid)
      OR coalesce((SELECT ads_free FROM wallets WHERE user_id = p_uid), false)
      OR coalesce((SELECT until > now() FROM play_pass WHERE user_id = p_uid), false)
      OR coalesce((SELECT used < setting_int('free_rounds_daily', 5) + bonus
                   FROM play_rounds WHERE user_id = p_uid AND day = bag_day()), true);
$$;

-- تستهلك جولة (بصمت إن لم يكن هناك حدّ)
CREATE OR REPLACE FUNCTION public._use_round(p_uid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM app_admins WHERE user_id = p_uid)
     OR coalesce((SELECT ads_free FROM wallets WHERE user_id = p_uid), false)
     OR coalesce((SELECT until > now() FROM play_pass WHERE user_id = p_uid), false) THEN
    RETURN;
  END IF;
  INSERT INTO play_rounds(user_id, day, used) VALUES (p_uid, bag_day(), 1)
  ON CONFLICT (user_id, day) DO UPDATE SET used = play_rounds.used + 1;
END $$;

CREATE OR REPLACE FUNCTION public.play_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r play_rounds%ROWTYPE; pu timestamptz; unl boolean; free int := setting_int('free_rounds_daily', 5);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO r FROM play_rounds WHERE user_id = auth.uid() AND day = bag_day();
  SELECT until INTO pu FROM play_pass WHERE user_id = auth.uid();
  unl := EXISTS (SELECT 1 FROM app_admins WHERE user_id = auth.uid())
         OR coalesce((SELECT ads_free FROM wallets WHERE user_id = auth.uid()), false);
  RETURN jsonb_build_object(
    'unlimited', unl,
    'pass_until', CASE WHEN pu > now() THEN pu END,
    'free_total', free,
    'used', coalesce(r.used, 0),
    'bonus', coalesce(r.bonus, 0),
    'left', greatest(0, free + coalesce(r.bonus, 0) - coalesce(r.used, 0)),
    'can_play', public._can_play(auth.uid()),
    'ad_rounds_left', greatest(0, setting_int('ad_round_max', 10) - coalesce(r.bonus, 0)),
    'ad_gems_left', greatest(0, setting_int('ad_gems_max', 20) - coalesce(r.ad_gems, 0)),
    'ad_gems_amount', setting_int('ad_gems_amount', 10),
    'price_day', setting_int('pass_day_price', 100),
    'price_week', setting_int('pass_week_price', 500),
    'price_month', setting_int('pass_month_price', 1500));
END $$;

-- إعلان مكتمل = جولة إضافية
CREATE OR REPLACE FUNCTION public.claim_ad_round() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  INSERT INTO play_rounds(user_id, day) VALUES (auth.uid(), bag_day()) ON CONFLICT DO NOTHING;
  SELECT bonus INTO b FROM play_rounds WHERE user_id = auth.uid() AND day = bag_day() FOR UPDATE;
  IF b >= setting_int('ad_round_max', 10) THEN RAISE EXCEPTION 'ad rounds limit'; END IF;
  UPDATE play_rounds SET bonus = bonus + 1 WHERE user_id = auth.uid() AND day = bag_day();
END $$;

-- إعلان مكتمل = ماسات (بحدّ يومي)
CREATE OR REPLACE FUNCTION public.claim_ad_gems() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n int; g int := setting_int('ad_gems_amount', 10);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  INSERT INTO play_rounds(user_id, day) VALUES (auth.uid(), bag_day()) ON CONFLICT DO NOTHING;
  SELECT ad_gems INTO n FROM play_rounds WHERE user_id = auth.uid() AND day = bag_day() FOR UPDATE;
  IF n >= setting_int('ad_gems_max', 20) THEN RAISE EXCEPTION 'ad gems limit'; END IF;
  UPDATE play_rounds SET ad_gems = ad_gems + 1 WHERE user_id = auth.uid() AND day = bag_day();
  INSERT INTO wallets(user_id, gems) VALUES (auth.uid(), g)
  ON CONFLICT (user_id) DO UPDATE SET gems = wallets.gems + g;
  RETURN g;
END $$;

-- شراء لعب مفتوح بالماسات: day | week | month
CREATE OR REPLACE FUNCTION public.buy_pass(p_kind text) RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE price int; span interval; have int; base timestamptz; res timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_kind = 'day' THEN price := setting_int('pass_day_price', 100); span := interval '1 day';
  ELSIF p_kind = 'week' THEN price := setting_int('pass_week_price', 500); span := interval '7 days';
  ELSIF p_kind = 'month' THEN price := setting_int('pass_month_price', 1500); span := interval '30 days';
  ELSE RAISE EXCEPTION 'bad kind'; END IF;
  SELECT gems INTO have FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF coalesce(have, 0) < price THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - price WHERE user_id = auth.uid();
  SELECT greatest(now(), coalesce((SELECT until FROM play_pass WHERE user_id = auth.uid()), now())) INTO base;
  res := base + span;
  INSERT INTO play_pass(user_id, until) VALUES (auth.uid(), res)
  ON CONFLICT (user_id) DO UPDATE SET until = EXCLUDED.until;
  RETURN res;
END $$;

-- ===== ربط الحدّ بإنشاء المباراة =====
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
  PERFORM public._use_round(p1);
  PERFORM public._use_round(p2);
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
  IF NOT public._can_play(me) THEN RAISE EXCEPTION 'no rounds'; END IF;

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

CREATE OR REPLACE FUNCTION public.accept_invite(p_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inv game_invites%ROWTYPE; mid uuid;
BEGIN
  IF NOT public._can_play(auth.uid()) THEN RAISE EXCEPTION 'no rounds'; END IF;
  SELECT * INTO inv FROM game_invites
   WHERE id = p_id AND to_user = auth.uid() AND status = 'pending' AND created_at > now() - interval '2 minutes'
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invite expired'; END IF;
  mid := public._create_match(inv.from_user, auth.uid(), inv.category_id);
  UPDATE game_invites SET status = 'accepted', match_id = mid WHERE id = p_id;
  RETURN mid;
END $$;

REVOKE ALL ON FUNCTION public.play_status(), public.claim_ad_round(), public.claim_ad_gems(), public.buy_pass(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._can_play(uuid), public._use_round(uuid) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.play_status(), public.claim_ad_round(), public.claim_ad_gems(), public.buy_pass(text) TO authenticated;

-- ===== شرح طريقة اللعب (صور ونصوص يعدّلها المدير) =====
CREATE TABLE IF NOT EXISTS public.tutorial_slides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sort int NOT NULL DEFAULT 0,
  title text NOT NULL DEFAULT '',
  body text NOT NULL DEFAULT '',
  image_url text
);
ALTER TABLE public.tutorial_slides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ts_read ON public.tutorial_slides;
CREATE POLICY ts_read ON public.tutorial_slides FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS ts_admin ON public.tutorial_slides;
CREATE POLICY ts_admin ON public.tutorial_slides FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tutorial_slides TO authenticated;

INSERT INTO public.tutorial_slides(sort, title, body)
SELECT * FROM (VALUES
  (1, 'مرحباً بك في نستأنس', 'لعبة خمّن الشخصية: كل لاعب لا يرى صورة شخصيته، لكنه يرى شخصية خصمه.'),
  (2, 'اسأل بنعم أو لا', 'اسأل خصمك أسئلة إجابتها نعم أو لا لتعرف من أنت.'),
  (3, 'خمّن واربح', 'من يعرف شخصيته أولاً يفوز بالجولة.')
) v(sort, title, body)
WHERE NOT EXISTS (SELECT 1 FROM public.tutorial_slides);
