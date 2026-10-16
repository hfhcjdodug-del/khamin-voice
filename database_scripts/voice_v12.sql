-- v12: الملف الشخصي الجديد — جدار الصور، العلامات، تاريخ الميلاد
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS photos   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS tags     text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS birthday date;

GRANT UPDATE (photos, tags, birthday) ON public.profiles TO authenticated;
