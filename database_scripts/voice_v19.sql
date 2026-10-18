-- =====================================================================
-- v19: ألقاب ومستويات قابلة للتعديل من لوحة المدير
--  • level_badges: صورة مخصصة لمستوى معيّن (تغيّر الأصلية أو تضيف مستوى جديداً بعد 50)
--  • title_defs: لقب (اسم + صورة + يبدأ من أي مستوى). idx 0..24 يعدّل الألقاب الحالية، و25 فأكثر ألقاب جديدة
--  آمن لو أعدت تشغيله
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.level_badges (
  level int PRIMARY KEY CHECK (level BETWEEN 1 AND 500),
  image_url text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.title_defs (
  idx int PRIMARY KEY CHECK (idx BETWEEN 0 AND 300),
  from_level int NOT NULL CHECK (from_level BETWEEN 1 AND 500),
  name text NOT NULL,
  image_url text
);
ALTER TABLE public.level_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.title_defs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS level_badges_read ON public.level_badges;
DROP POLICY IF EXISTS level_badges_admin ON public.level_badges;
DROP POLICY IF EXISTS title_defs_read ON public.title_defs;
DROP POLICY IF EXISTS title_defs_admin ON public.title_defs;
CREATE POLICY level_badges_read ON public.level_badges FOR SELECT TO authenticated USING (true);
CREATE POLICY level_badges_admin ON public.level_badges FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY title_defs_read ON public.title_defs FOR SELECT TO authenticated USING (true);
CREATE POLICY title_defs_admin ON public.title_defs FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.level_badges, public.title_defs TO authenticated;
