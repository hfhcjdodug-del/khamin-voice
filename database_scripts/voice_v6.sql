-- نتونس — التحديث 6: إشعارات التطبيق، إعدادات عامة (غلاف/اسم «منوّع»)، رفع مستوى أي حساب.
-- شغّله في Supabase > SQL Editor (آمن لو أعدت تشغيله).

-- ===== 1) إشعارات التطبيق =====
CREATE TABLE IF NOT EXISTS public.app_notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  body text NOT NULL DEFAULT '' CHECK (char_length(body) <= 400),
  kind text NOT NULL DEFAULT 'info' CHECK (kind IN ('info', 'update', 'alert')),
  url text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notif_read ON public.app_notifications;
DROP POLICY IF EXISTS notif_admin ON public.app_notifications;
CREATE POLICY notif_read ON public.app_notifications FOR SELECT TO authenticated USING (true);
CREATE POLICY notif_admin ON public.app_notifications FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, DELETE ON public.app_notifications TO authenticated;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.app_notifications; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ===== 2) إعدادات عامة (مثلاً غلاف واسم «منوّع») =====
CREATE TABLE IF NOT EXISTS public.app_settings (
  key text PRIMARY KEY,
  value text NOT NULL DEFAULT ''
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS settings_read ON public.app_settings;
DROP POLICY IF EXISTS settings_admin ON public.app_settings;
CREATE POLICY settings_read ON public.app_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY settings_admin ON public.app_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_settings TO authenticated;

-- ===== 3) رفع/تغيير مستوى أي حساب (للمدير) =====
-- المستوى L يبدأ عند 50*(L-1)^2 نقطة، فنضبط النقاط على بداية المستوى المطلوب.
CREATE OR REPLACE FUNCTION public.admin_set_level(p_id uuid, p_level int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_level < 1 OR p_level > 100 THEN RAISE EXCEPTION 'bad level'; END IF;
  UPDATE profiles SET xp = 50 * (p_level - 1) * (p_level - 1) WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.admin_set_level(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_level(uuid, int) TO authenticated;

-- ===== كود جاهز تنفّذه يدوياً في SQL Editor (غيّر اليوزر والمستوى) =====
-- رفع حساب إلى المستوى 30 باليوزر:
--   UPDATE public.profiles SET xp = 50 * (30 - 1) * (30 - 1) WHERE username = 'mustafa';
-- أو بالرقم (ID الظاهر في الملف الشخصي):
--   UPDATE public.profiles SET xp = 50 * (50 - 1) * (50 - 1) WHERE num = 100004;
