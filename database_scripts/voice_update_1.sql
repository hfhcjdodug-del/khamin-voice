-- voice_update_1.sql — إضافة اسم المستخدم (username) للملف الشخصي
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username text;
UPDATE public.profiles SET username = 'user' || substr(replace(id::text,'-',''),1,8) WHERE username IS NULL;
ALTER TABLE public.profiles ALTER COLUMN username SET NOT NULL;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS username_format;
ALTER TABLE public.profiles ADD CONSTRAINT username_format CHECK (username ~ '^[a-z0-9_]{3,20}$');
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_key ON public.profiles (lower(username));

CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n text;
BEGIN
  n := NULLIF(trim(COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', '')), '');
  IF n IS NULL THEN n := 'ضيف ' || (floor(random()*9000)+1000)::int; END IF;
  INSERT INTO public.profiles(id, name, username, avatar_url)
  VALUES (NEW.id, left(n, 40), 'user' || substr(replace(NEW.id::text,'-',''),1,8),
          COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture'))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;
