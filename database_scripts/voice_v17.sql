-- =====================================================================
-- v17: لعبة المزرعة (عجلة الأكل) — النتيجة والدفع من الخادم فقط
--  • مطفأة افتراضياً: المدير يشغّلها من لوحة المدير > المزرعة
--  • إعدادات (app_settings): farm_enabled(0/1) farm_min_bet farm_max_bet farm_daily_limit
--    farm_payout_pct (نسبة الدفع من المضاعف، 90 يعني الربح يُدفع بـ 90%) farm_round_secs
--  آمن لو أعدت تشغيله
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.farm_items (
  idx smallint PRIMARY KEY,
  name text NOT NULL,
  emoji text NOT NULL,
  mult int NOT NULL CHECK (mult >= 2)
);
INSERT INTO public.farm_items(idx, name, emoji, mult) VALUES
  (0, 'جزر', '🥕', 5), (1, 'ذرة', '🌽', 5), (2, 'طماطم', '🍅', 5), (3, 'باذنجان', '🍆', 5),
  (4, 'دجاج', '🍗', 10), (5, 'لحم', '🥩', 15), (6, 'سمك', '🐟', 25), (7, 'ذهب', '🏆', 45)
ON CONFLICT (idx) DO NOTHING;
ALTER TABLE public.farm_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS farm_items_read ON public.farm_items;
CREATE POLICY farm_items_read ON public.farm_items FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.farm_items TO authenticated;

CREATE TABLE IF NOT EXISTS public.farm_rounds (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  started_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL,
  result smallint,
  settled boolean NOT NULL DEFAULT false
);
ALTER TABLE public.farm_rounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS farm_rounds_read ON public.farm_rounds;
CREATE POLICY farm_rounds_read ON public.farm_rounds FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.farm_rounds TO authenticated;

CREATE TABLE IF NOT EXISTS public.farm_bets (
  round_id bigint NOT NULL REFERENCES public.farm_rounds(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item smallint NOT NULL REFERENCES public.farm_items(idx),
  amount int NOT NULL CHECK (amount > 0),
  payout int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (round_id, user_id, item)
);
ALTER TABLE public.farm_bets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS farm_bets_own ON public.farm_bets;
CREATE POLICY farm_bets_own ON public.farm_bets FOR SELECT TO authenticated USING (user_id = auth.uid());
GRANT SELECT ON public.farm_bets TO authenticated;

CREATE OR REPLACE FUNCTION public._farm_setting(p_key text, p_def int) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT nullif(value, '')::int FROM app_settings WHERE key = p_key), p_def);
$$;

-- يُنهي الجولة المنتهية (يختار النتيجة ويدفع) ويفتح جولة جديدة. مقفل برقم استشاري.
CREATE OR REPLACE FUNCTION public._farm_advance() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rd farm_rounds%ROWTYPE; tot numeric; pick numeric; acc numeric := 0; res smallint; it record;
        pct int := _farm_setting('farm_payout_pct', 90);
        secs int := greatest(10, least(120, _farm_setting('farm_round_secs', 25)));
BEGIN
  PERFORM pg_advisory_xact_lock(7770017);
  SELECT * INTO rd FROM farm_rounds WHERE NOT settled ORDER BY id DESC LIMIT 1;
  IF FOUND AND rd.ends_at <= now() THEN
    SELECT sum(1.0 / mult) INTO tot FROM farm_items;
    pick := random() * tot;
    FOR it IN SELECT idx, mult FROM farm_items ORDER BY idx LOOP
      acc := acc + 1.0 / it.mult;
      res := it.idx;
      EXIT WHEN pick <= acc;
    END LOOP;
    UPDATE farm_bets b SET payout = floor(b.amount * (SELECT mult FROM farm_items WHERE idx = b.item) * pct / 100.0)::int
      WHERE b.round_id = rd.id AND b.item = res;
    UPDATE wallets w SET gems = w.gems + s.p
      FROM (SELECT user_id, sum(payout)::int AS p FROM farm_bets WHERE round_id = rd.id AND payout > 0 GROUP BY user_id) s
      WHERE w.user_id = s.user_id;
    UPDATE farm_rounds SET result = res, settled = true WHERE id = rd.id;
    rd := NULL;
  ELSIF FOUND THEN
    RETURN;
  END IF;
  IF _farm_setting('farm_enabled', 0) = 1 THEN
    INSERT INTO farm_rounds(ends_at) VALUES (now() + make_interval(secs => secs));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.farm_state() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE en boolean := _farm_setting('farm_enabled', 0) = 1; rd farm_rounds%ROWTYPE; lastr farm_rounds%ROWTYPE; out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  PERFORM _farm_advance();
  SELECT * INTO rd FROM farm_rounds WHERE NOT settled ORDER BY id DESC LIMIT 1;
  SELECT * INTO lastr FROM farm_rounds WHERE settled ORDER BY id DESC LIMIT 1;
  out := jsonb_build_object(
    'enabled', en,
    'min_bet', _farm_setting('farm_min_bet', 10),
    'max_bet', _farm_setting('farm_max_bet', 1000),
    'daily_limit', _farm_setting('farm_daily_limit', 20000),
    'today_staked', coalesce((SELECT sum(amount) FROM farm_bets WHERE user_id = auth.uid() AND created_at >= date_trunc('day', now())), 0),
    'round_id', rd.id,
    'ends_in', CASE WHEN rd.id IS NULL THEN NULL ELSE greatest(0, extract(epoch FROM rd.ends_at - now()))::numeric(6,1) END,
    'my_bets', coalesce((SELECT jsonb_object_agg(item::text, amount) FROM farm_bets WHERE round_id = rd.id AND user_id = auth.uid()), '{}'::jsonb),
    'history', coalesce((SELECT jsonb_agg(result ORDER BY id DESC) FROM (SELECT id, result FROM farm_rounds WHERE settled ORDER BY id DESC LIMIT 12) h), '[]'::jsonb),
    'last_result', lastr.result,
    'last_round', lastr.id,
    'last_staked', coalesce((SELECT sum(amount) FROM farm_bets WHERE round_id = lastr.id AND user_id = auth.uid()), 0),
    'last_payout', coalesce((SELECT sum(payout) FROM farm_bets WHERE round_id = lastr.id AND user_id = auth.uid()), 0),
    'items', (SELECT jsonb_agg(jsonb_build_object('idx', idx, 'name', name, 'emoji', emoji, 'mult', mult) ORDER BY idx) FROM farm_items)
  );
  RETURN out;
END $$;

CREATE OR REPLACE FUNCTION public.farm_bet(p_item int, p_amount int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rd farm_rounds%ROWTYPE; w int; mine int; today int;
        mn int := _farm_setting('farm_min_bet', 10); mx int := _farm_setting('farm_max_bet', 1000);
        dl int := _farm_setting('farm_daily_limit', 20000);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF _farm_setting('farm_enabled', 0) <> 1 THEN RAISE EXCEPTION 'farm off'; END IF;
  PERFORM _farm_advance();
  SELECT * INTO rd FROM farm_rounds WHERE NOT settled ORDER BY id DESC LIMIT 1;
  IF NOT FOUND OR rd.ends_at <= now() + interval '2 seconds' THEN RAISE EXCEPTION 'round closed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM farm_items WHERE idx = p_item) THEN RAISE EXCEPTION 'bad item'; END IF;
  IF p_amount < mn OR p_amount > mx THEN RAISE EXCEPTION 'bad amount'; END IF;
  SELECT coalesce(sum(amount), 0) INTO mine FROM farm_bets WHERE round_id = rd.id AND user_id = auth.uid();
  IF mine + p_amount > mx THEN RAISE EXCEPTION 'round limit'; END IF;
  SELECT coalesce(sum(amount), 0) INTO today FROM farm_bets WHERE user_id = auth.uid() AND created_at >= date_trunc('day', now());
  IF today + p_amount > dl THEN RAISE EXCEPTION 'daily limit'; END IF;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < p_amount THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - p_amount WHERE user_id = auth.uid();
  INSERT INTO farm_bets(round_id, user_id, item, amount) VALUES (rd.id, auth.uid(), p_item, p_amount)
  ON CONFLICT (round_id, user_id, item) DO UPDATE SET amount = farm_bets.amount + EXCLUDED.amount;
END $$;

REVOKE ALL ON FUNCTION public._farm_advance(), public._farm_setting(text, int), public.farm_state(), public.farm_bet(int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.farm_state(), public.farm_bet(int, int) TO authenticated;
