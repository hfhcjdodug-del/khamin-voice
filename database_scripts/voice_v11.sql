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
