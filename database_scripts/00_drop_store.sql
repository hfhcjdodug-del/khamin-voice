-- 00_drop_store.sql
-- ⚠️ يحذف متجر "هوبي" بالكامل (كل الجداول والدوال والبيانات في schema public).
-- لا رجعة فيه. شغّله مرة واحدة فقط، قبل 01_game_core.sql.
-- حسابات الدخول (Google / Facebook) لا تُحذف لأنها في schema آخر (auth).

-- إلغاء المهام المجدولة القديمة (إن وُجدت)
DO $$
DECLARE r record;
BEGIN
  BEGIN
    FOR r IN SELECT jobid FROM cron.job LOOP
      PERFORM cron.unschedule(r.jobid);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- امتداد cron غير مفعّل: لا مشكلة
  END;
END $$;

DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, service_role;

-- حذف سياسات التخزين القديمة (صور المتجر)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
  END LOOP;
END $$;
