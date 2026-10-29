-- نستأنس — التحديث 21: فيديو شاشة الدخول (يُقرأ قبل تسجيل الدخول)
CREATE OR REPLACE FUNCTION public.login_media() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT nullif(value, '') FROM app_settings WHERE key = 'login_video'), '');
$$;
REVOKE ALL ON FUNCTION public.login_media() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.login_media() TO anon, authenticated;
