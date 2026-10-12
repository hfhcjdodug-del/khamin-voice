-- 03_game_presence.sql — الحضور والغرف المؤقتة (بديل onDisconnect في Firebase)
-- التطبيق يرسل نبضة كل 20 ثانية للمسارات المؤقتة (حضور، انتظار مباراة، غرفة VIP)،
-- ومهمة مجدولة كل دقيقة تحذف ما انقطعت نبضته أكثر من 75 ثانية.
-- شغّله بعد 02_game_economy.sql.

CREATE TABLE public.rtdb_ephemeral (
  path      text PRIMARY KEY,
  owner     uuid NOT NULL,
  last_seen timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rtdb_ephemeral ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rtdb_ephemeral FROM anon, authenticated;

CREATE FUNCTION public.rtdb_heartbeat(p_paths text[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); p text;
BEGIN
  IF uid IS NULL THEN RETURN; END IF;
  IF coalesce(array_length(p_paths,1),0) > 20 THEN RAISE EXCEPTION 'too many paths'; END IF;
  FOREACH p IN ARRAY p_paths LOOP
    IF NOT public.rtdb_valid_path(p) THEN CONTINUE; END IF;
    IF NOT public.rtdb_can_write(p, NULL, uid) THEN CONTINUE; END IF;
    INSERT INTO public.rtdb_ephemeral(path, owner, last_seen) VALUES (p, uid, now())
    ON CONFLICT (path) DO UPDATE SET last_seen = now(), owner = EXCLUDED.owner;
  END LOOP;
END $$;

CREATE FUNCTION public.rtdb_ephemeral_clear(p_path text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.rtdb_ephemeral WHERE path = p_path AND owner = auth.uid();
$$;

CREATE FUNCTION public.rtdb_cleanup_ephemeral() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT path FROM public.rtdb_ephemeral WHERE last_seen < now() - interval '75 seconds' LOOP
    DELETE FROM public.rtdb_nodes WHERE path = r.path OR (path >= r.path || '/' AND path < r.path || '0');
    DELETE FROM public.rtdb_ephemeral WHERE path = r.path;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

REVOKE ALL ON FUNCTION public.rtdb_heartbeat(text[]), public.rtdb_ephemeral_clear(text), public.rtdb_cleanup_ephemeral() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rtdb_heartbeat(text[]), public.rtdb_ephemeral_clear(text) TO authenticated;

-- الجدولة: pg_cron (فعّله من Database → Extensions إن لم يكن مفعّلاً)
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'rtdb_cleanup_ephemeral';
  PERFORM cron.schedule('rtdb_cleanup_ephemeral', '* * * * *', 'select public.rtdb_cleanup_ephemeral()');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '⚠️ لم تُجدوَل مهمة التنظيف (pg_cron): %. فعّل pg_cron من Database > Extensions ثم أعد تشغيل هذا الملف.', SQLERRM;
END $$;
