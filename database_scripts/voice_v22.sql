-- ===== v22: هدايا SVGA داخل المنافسة =====
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS svga_url text;  -- رابط https أو asset:اسم.svga

CREATE TABLE IF NOT EXISTS public.match_gifts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id uuid NOT NULL REFERENCES public.game_matches(id) ON DELETE CASCADE,
  from_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  gift_name text NOT NULL,
  svga_url text, image_url text, emoji text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS match_gifts_m ON public.match_gifts (match_id, id);
ALTER TABLE public.match_gifts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS match_gifts_read ON public.match_gifts;
CREATE POLICY match_gifts_read ON public.match_gifts FOR SELECT TO authenticated
  USING (auth.uid() IN (from_id, to_id));
GRANT SELECT ON public.match_gifts TO authenticated;

CREATE OR REPLACE FUNCTION public.send_match_gift(p_match uuid, p_gift uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g gifts%ROWTYPE; m game_matches%ROWTYPE; opp uuid; w int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO m FROM game_matches WHERE id = p_match AND status = 'active' AND auth.uid() IN (player1, player2);
  IF NOT FOUND THEN RAISE EXCEPTION 'match not active'; END IF;
  opp := CASE WHEN m.player1 = auth.uid() THEN m.player2 ELSE m.player1 END;
  SELECT * INTO g FROM gifts WHERE id = p_gift AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'bad gift'; END IF;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < g.price THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - g.price WHERE user_id = auth.uid();
  INSERT INTO wallets(user_id) VALUES (opp) ON CONFLICT DO NOTHING;
  UPDATE wallets SET ruby_pts = ruby_pts + g.price WHERE user_id = opp;   -- 20 مستلمة = ياقوتة
  INSERT INTO gift_log(from_id, to_id, gift_id, qty, gems) VALUES (auth.uid(), opp, g.id, 1, g.price);
  INSERT INTO match_gifts(match_id, from_id, to_id, gift_name, svga_url, image_url, emoji)
  VALUES (p_match, auth.uid(), opp, g.name, g.svga_url, g.image_url, g.emoji);
  UPDATE profiles SET xp = xp + g.price * setting_int('gift_xp_sender', 2) WHERE id = auth.uid();
  UPDATE profiles SET xp = xp + g.price * setting_int('gift_xp_receiver', 1) WHERE id = opp;
END $$;
REVOKE ALL ON FUNCTION public.send_match_gift(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_match_gift(uuid, uuid) TO authenticated;

-- هدايا افتراضية (ملفاتها داخل التطبيق) — احذف أي هدية لا تناسبك من لوحة التحكم > الهدايا
INSERT INTO public.gifts(name, price, emoji, svga_url, sort)
SELECT v.n, v.p, v.e, v.u, v.s FROM (VALUES
  ('نبض', 50, '💓', 'asset:heartbeat.svga', 1),
  ('وردة', 100, '🌹', 'asset:rose.svga', 2),
  ('يقطينة', 150, '🎃', 'asset:halloween.svga', 3),
  ('ملاك', 300, '😇', 'asset:angel.svga', 4),
  ('سيارة', 500, '🏎️', 'asset:posche.svga', 5),
  ('ملك', 1000, '👑', 'asset:kingset.svga', 6)
) AS v(n, p, e, u, s)
WHERE NOT EXISTS (SELECT 1 FROM public.gifts WHERE svga_url LIKE 'asset:%');
