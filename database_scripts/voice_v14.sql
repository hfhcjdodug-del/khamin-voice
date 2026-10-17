-- =====================================================================
-- v14: خلفيات الروم من لوحة المدير (مجانية أو بسعر بالجواهر)
--  • المدير يضيف/يحذف/يعدّل الخلفيات وأسعارها
--  • صاحب الروم يشتري الخلفية مرة واحدة فتبقى له، ثم يطبّقها على رومه
--  • آمن لو أعدت تشغيله
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.room_backgrounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
  image_url text NOT NULL,
  price int NOT NULL DEFAULT 0 CHECK (price >= 0),
  sort int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.room_backgrounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rbg_read ON public.room_backgrounds;
DROP POLICY IF EXISTS rbg_admin ON public.room_backgrounds;
CREATE POLICY rbg_read ON public.room_backgrounds FOR SELECT TO authenticated USING (active OR public.is_admin());
CREATE POLICY rbg_admin ON public.room_backgrounds FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.room_backgrounds TO authenticated;

CREATE TABLE IF NOT EXISTS public.user_backgrounds (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  bg_id uuid NOT NULL REFERENCES public.room_backgrounds(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, bg_id)
);
ALTER TABLE public.user_backgrounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ubg_read ON public.user_backgrounds;
CREATE POLICY ubg_read ON public.user_backgrounds FOR SELECT TO authenticated USING (user_id = auth.uid());
GRANT SELECT ON public.user_backgrounds TO authenticated;

-- شراء خلفية (مرة واحدة). المجانية لا تحتاج شراء.
CREATE OR REPLACE FUNCTION public.buy_room_background(p_bg uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b room_backgrounds%ROWTYPE; w int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO b FROM room_backgrounds WHERE id = p_bg AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'bad background'; END IF;
  IF b.price = 0 OR EXISTS (SELECT 1 FROM user_backgrounds WHERE user_id = auth.uid() AND bg_id = p_bg) THEN RETURN; END IF;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < b.price THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - b.price WHERE user_id = auth.uid();
  INSERT INTO user_backgrounds(user_id, bg_id) VALUES (auth.uid(), p_bg) ON CONFLICT DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.buy_room_background(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buy_room_background(uuid) TO authenticated;

-- تطبيق الخلفية: إن كانت صورة من الكتالوج وبسعر فلا تُطبَّق إلا لمن اشتراها
CREATE OR REPLACE FUNCTION public.room_set_look(p_room uuid, p_bg_preset text, p_bg_url text,
                                                p_mic_skin text, p_mic_skin_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF nullif(p_bg_url, '') IS NOT NULL AND EXISTS (
       SELECT 1 FROM room_backgrounds b
       WHERE b.image_url = p_bg_url AND b.price > 0
         AND NOT EXISTS (SELECT 1 FROM user_backgrounds u WHERE u.bg_id = b.id AND u.user_id = auth.uid())
     ) THEN
    RAISE EXCEPTION 'background locked';
  END IF;
  UPDATE rooms SET bg_preset = coalesce(nullif(p_bg_preset, ''), 'violet'),
                   bg_url = nullif(p_bg_url, ''),
                   mic_skin = coalesce(nullif(p_mic_skin, ''), 'none'),
                   mic_skin_url = nullif(p_mic_skin_url, '')
  WHERE id = p_room AND host_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'owner only'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.room_set_look(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.room_set_look(uuid, text, text, text, text) TO authenticated;
