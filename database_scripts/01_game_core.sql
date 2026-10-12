-- 01_game_core.sql  —  قاعدة بيانات لعبة "خمّن الشخصية" على Supabase
-- تعمل كبديل لـ Firebase Realtime Database: شجرة بيانات على شكل مسارات (users/..., games/...)
-- الكتابة والقراءة تمر فقط عبر دوال تفرض قواعد الأمان (لا وصول مباشر للجدول).
-- شغّله بعد 00_drop_store.sql (أو على مشروع فارغ).

------------------------------------------------------------------------------
-- 1) الجداول
------------------------------------------------------------------------------
CREATE TABLE public.rtdb_nodes (
  path       text COLLATE "C" PRIMARY KEY,      -- مثال: users/<uid>/coins
  top        text NOT NULL,                      -- أول جزء من المسار
  scope      text NOT NULL,                      -- أول جزءين من المسار
  value      jsonb NOT NULL,                     -- قيمة بسيطة (نص/رقم/صح-خطأ)
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rtdb_nodes_scope_idx ON public.rtdb_nodes (scope);
ALTER TABLE public.rtdb_nodes ENABLE ROW LEVEL SECURITY;      -- بدون أي سياسة = ممنوع مباشرة
REVOKE ALL ON public.rtdb_nodes FROM anon, authenticated;

CREATE TABLE public.app_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note    text
);
ALTER TABLE public.app_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_admins FROM anon, authenticated;

------------------------------------------------------------------------------
-- 2) دوال مساعدة
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_is_admin(u uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u IS NOT NULL AND EXISTS (SELECT 1 FROM public.app_admins WHERE user_id = u);
$$;

CREATE FUNCTION public.rtdb_seg(p text, i int) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT nullif(split_part(p, '/', i), '') $$;

CREATE FUNCTION public.rtdb_scope(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN split_part(p,'/',2) = '' THEN split_part(p,'/',1)
              ELSE split_part(p,'/',1) || '/' || split_part(p,'/',2) END
$$;

CREATE FUNCTION public.rtdb_valid_path(p text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT p IS NOT NULL AND length(p) BETWEEN 1 AND 400 AND p ~ '^[^/]+(/[^/]+)*$' AND p !~ '[[:cntrl:]]'
$$;

-- قيمة ورقة واحدة (أو NULL)
CREATE FUNCTION public.rtdb_val(p text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT value FROM public.rtdb_nodes WHERE path = p;
$$;

-- هل يوجد أي شيء تحت المسار (أو المسار نفسه)
CREATE FUNCTION public.rtdb_exists(p text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.rtdb_nodes
                 WHERE path = p OR (path >= p || '/' AND path < p || '0'));
$$;

-- تفكيك شجرة JSON إلى أوراق (مسار، قيمة). القيم null تُتجاهل (كما في Firebase)
CREATE FUNCTION public.rtdb_flatten(p text, v jsonb) RETURNS TABLE(path text, value jsonb)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text; e jsonb; i int := 0;
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN RETURN; END IF;
  IF jsonb_typeof(v) = 'object' THEN
    FOR k, e IN SELECT * FROM jsonb_each(v) LOOP
      RETURN QUERY SELECT * FROM public.rtdb_flatten(p || '/' || k, e);
    END LOOP;
  ELSIF jsonb_typeof(v) = 'array' THEN
    FOR e IN SELECT * FROM jsonb_array_elements(v) LOOP
      RETURN QUERY SELECT * FROM public.rtdb_flatten(p || '/' || i::text, e);
      i := i + 1;
    END LOOP;
  ELSE
    path := p; value := v; RETURN NEXT;
  END IF;
END $$;

CREATE FUNCTION public.rtdb_num(p text) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT CASE WHEN jsonb_typeof(value) = 'number' THEN (value #>> '{}')::numeric
                               WHEN jsonb_typeof(value) = 'string' AND (value #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (value #>> '{}')::numeric
                          END
                   FROM public.rtdb_nodes WHERE path = p), 0);
$$;


-- مستوى VIP الفعّال (0 إن لم يوجد أو انتهى)
CREATE FUNCTION public.rtdb_vip_tier(uid text) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.rtdb_num('users/'||uid||'/vipExpiry') > extract(epoch from now())*1000
              THEN public.rtdb_num('users/'||uid||'/vipTier')::int ELSE 0 END;
$$;


------------------------------------------------------------------------------
-- 3) قواعد القراءة
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_can_read(p text, u uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid text := u::text;
  s1 text := public.rtdb_seg(p,1);
  s2 text := public.rtdb_seg(p,2);
  s3 text := public.rtdb_seg(p,3);
  p1 text; p2 text;
BEGIN
  IF s1 IS NULL THEN RETURN false; END IF;
  -- عام (حتى قبل تسجيل الدخول)
  IF s1 IN ('settings','gameImages','gameCategories','categoryImages','customFrames','customEntrances','stats') THEN
    RETURN true;
  END IF;
  IF u IS NULL THEN RETURN false; END IF;
  IF public.rtdb_is_admin(u) THEN RETURN true; END IF;

  -- خاص بصاحبه فقط
  IF s1 IN ('conversations','contactRequests','vipInbox','gameInvites','profileVisits','bans','activeGameFor') THEN
    RETURN s2 IS NOT NULL AND s2 = uid;
  END IF;
  IF s1 IN ('blocks','friendRequests') THEN
    RETURN s2 IS NOT NULL AND (s2 = uid OR s3 = uid);
  END IF;
  -- مفتوح لكل المسجّلين
  IF s1 IN ('users','friends','follows','following','publicIdIndex','matchmaking','presence',
            'userMedia','vipRooms','vipRoomChat','vipRoomSig','broadcasts') THEN
    RETURN true;
  END IF;
  IF s1 = 'games' THEN
    IF s2 IS NULL THEN RETURN false; END IF;
    p1 := public.rtdb_val('games/'||s2||'/player1') #>> '{}';
    p2 := public.rtdb_val('games/'||s2||'/player2') #>> '{}';
    -- اللاعبان، أو لعبة بانتظار خصم (للانضمام عبر الرابط)، أو لعبة غير موجودة بعد
    RETURN p1 IS NULL OR uid IN (p1, coalesce(p2,'')) OR p2 IS NULL;
  END IF;
  RETURN false;   -- complaints, gameRequests, topupRequests, premiumIdPool ... للمدير فقط
END $$;

------------------------------------------------------------------------------
-- 4) قواعد الكتابة (v = NULL تعني حذف)
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_can_write(p text, v jsonb, u uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid text := u::text;
  s1 text := public.rtdb_seg(p,1);
  s2 text := public.rtdb_seg(p,2);
  s3 text := public.rtdb_seg(p,3);
  s4 text := public.rtdb_seg(p,4);
  p1 text; p2 text; g text; base text;
BEGIN
  IF u IS NULL OR s1 IS NULL THEN RETURN false; END IF;
  IF public.rtdb_is_admin(u) THEN RETURN true; END IF;

  IF s1 = 'users' THEN
    IF s2 IS NULL OR s3 IS NULL THEN RETURN false; END IF;
    -- حقول يكتبها صاحب الحساب فقط (كل ما عداها: العملات/الألماس/VIP/المستوى... عبر دوال الخادم)
    IF s2 = uid THEN
      RETURN s3 IN ('name','bio','avatarUrl','partnerUid','equippedFrame','hasSong','songName','lastBroadcast');
    END IF;
    RETURN s3 = 'partnerUid';   -- عند قبول الشراكة يُكتب الطرفان
  END IF;

  IF s1 = 'publicIdIndex' THEN
    RETURN s2 IS NOT NULL AND v IS NOT NULL AND v = to_jsonb(uid) AND NOT public.rtdb_exists(p);
  END IF;

  IF s1 IN ('friends','friendRequests','follows','following') THEN
    IF s2 IS NULL OR s3 IS NULL THEN RETURN false; END IF;
    IF NOT (uid IN (s2, s3)) THEN RETURN false; END IF;
    IF s1 = 'friendRequests' AND v IS NOT NULL AND s3 = uid THEN
      IF public.rtdb_exists('blocks/'||s2||'/'||s3) THEN RETURN false; END IF;  -- محظور من المستلم
    END IF;
    RETURN true;
  END IF;

  IF s1 = 'blocks' THEN RETURN s2 = uid AND s3 IS NOT NULL; END IF;

  IF s1 = 'games' THEN
    IF s2 IS NULL THEN RETURN false; END IF;
    p1 := public.rtdb_val('games/'||s2||'/player1') #>> '{}';
    p2 := public.rtdb_val('games/'||s2||'/player2') #>> '{}';
    IF p1 IS NULL THEN RETURN true; END IF;                       -- إنشاء لعبة جديدة
    IF uid IN (p1, coalesce(p2,'')) THEN RETURN true; END IF;
    IF p2 IS NULL AND s3 IN ('player2','player2Image','status') THEN   -- الانضمام للعبة منتظِرة
      RETURN s3 <> 'player2' OR v = to_jsonb(uid);
    END IF;
    RETURN false;
  END IF;

  IF s1 = 'activeGameFor' THEN
    IF s2 IS NULL THEN RETURN false; END IF;
    IF s2 = uid THEN RETURN true; END IF;
    g := coalesce(v #>> '{}', public.rtdb_val(p) #>> '{}');
    IF g IS NULL THEN RETURN false; END IF;
    p1 := public.rtdb_val('games/'||g||'/player1') #>> '{}';
    p2 := public.rtdb_val('games/'||g||'/player2') #>> '{}';
    RETURN s2 IN (coalesce(p1,''), coalesce(p2,'')) AND uid IN (coalesce(p1,''), coalesce(p2,''));
  END IF;

  IF s1 = 'gameInvites' THEN
    IF s2 IS NULL OR s3 IS NULL THEN RETURN false; END IF;
    IF s2 = uid THEN RETURN true; END IF;
    IF public.rtdb_exists('gameInvites/'||s2||'/'||s3) THEN RETURN false; END IF;   -- دعوة جديدة فقط
    RETURN s4 IS DISTINCT FROM 'fromUid' OR v = to_jsonb(uid);
  END IF;

  IF s1 = 'matchmaking' THEN RETURN s2 IS NOT NULL; END IF;
  IF s1 = 'presence'    THEN RETURN s2 = uid; END IF;
  IF s1 = 'userMedia' THEN
    IF s2 IS DISTINCT FROM uid THEN RETURN false; END IF;
    IF s3 = 'song' THEN RETURN v IS NULL OR public.rtdb_vip_tier(uid) >= 7; END IF;
    IF s3 = 'avatarAnim' THEN RETURN v IS NULL OR public.rtdb_vip_tier(uid) >= 4; END IF;
    RETURN true;
  END IF;
  IF s1 IN ('conversations','contactRequests','vipInbox') THEN RETURN s2 = uid; END IF;
  IF s1 = 'profileVisits' THEN RETURN s3 = uid; END IF;

  IF s1 = 'vipRooms' THEN
    IF s2 IS NULL THEN RETURN false; END IF;
    IF s2 = uid THEN RETURN v IS NULL OR public.rtdb_vip_tier(uid) >= 2; END IF;   -- غرفة صوتية خاصة: VIP2 فما فوق
    RETURN s3 = 'members' AND s4 = uid;
  END IF;
  IF s1 = 'vipRoomChat' THEN
    IF s2 IS NULL THEN RETURN false; END IF;
    IF s2 = uid THEN RETURN true; END IF;
    IF s3 IS NULL THEN RETURN false; END IF;
    IF public.rtdb_exists('vipRoomChat/'||s2||'/'||s3) THEN RETURN false; END IF;
    RETURN s4 IS DISTINCT FROM 'uid' OR v = to_jsonb(uid);
  END IF;
  IF s1 = 'vipRoomSig' THEN RETURN s2 IS NOT NULL; END IF;

  IF s1 IN ('complaints','gameRequests','topupRequests','broadcasts') THEN
    -- إضافة سجل جديد فقط (push)، لا تعديل سجلات موجودة
    IF s2 IS NULL OR v IS NULL THEN RETURN false; END IF;
    IF s1 = 'broadcasts'   AND public.rtdb_vip_tier(uid) < 7 THEN RETURN false; END IF;
    IF s1 = 'complaints'   AND public.rtdb_vip_tier(uid) < 3 THEN RETURN false; END IF;
    IF s1 = 'gameRequests' AND public.rtdb_vip_tier(uid) < 6 THEN RETURN false; END IF;
    RETURN NOT public.rtdb_exists(s1||'/'||s2);
  END IF;

  IF s1 = 'stats' THEN RETURN true; END IF;   -- عدّادات شكلية (زوار/متابعون)
  RETURN false;
END $$;

------------------------------------------------------------------------------
-- 5) القراءة
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_read(p_path text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r jsonb;
BEGIN
  IF NOT public.rtdb_valid_path(p_path) THEN RAISE EXCEPTION 'bad path'; END IF;
  IF NOT public.rtdb_can_read(p_path, auth.uid()) THEN RAISE EXCEPTION 'permission denied: %', p_path USING ERRCODE = '42501'; END IF;
  SELECT coalesce(jsonb_object_agg(path, value), '{}'::jsonb) INTO r
  FROM public.rtdb_nodes
  WHERE path = p_path OR (path >= p_path || '/' AND path < p_path || '0');
  RETURN r;      -- خريطة مسطّحة {المسار الكامل: القيمة}
END $$;

------------------------------------------------------------------------------
-- 6) الكتابة: ops = [{"o":"del","p":"..."}, {"o":"put","p":"...","v":<json>}]
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_apply(ops jsonb, u uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE op jsonb; p text; leaf record; n int := 0;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  IF jsonb_typeof(ops) <> 'array' OR jsonb_array_length(ops) > 500 THEN RAISE EXCEPTION 'bad ops'; END IF;
  FOR op IN SELECT * FROM jsonb_array_elements(ops) LOOP
    p := op->>'p';
    IF NOT public.rtdb_valid_path(p) THEN RAISE EXCEPTION 'bad path'; END IF;
    IF op->>'o' = 'del' THEN
      -- كل ورقة موجودة تحت المسار يجب أن يُسمح بحذفها
      FOR leaf IN SELECT path FROM public.rtdb_nodes WHERE path = p OR (path >= p || '/' AND path < p || '0') LOOP
        n := n + 1;
        IF NOT public.rtdb_can_write(leaf.path, NULL, u) THEN
          RAISE EXCEPTION 'permission denied: %', leaf.path USING ERRCODE = '42501';
        END IF;
      END LOOP;
      IF n = 0 AND NOT public.rtdb_can_write(p, NULL, u) THEN
        RAISE EXCEPTION 'permission denied: %', p USING ERRCODE = '42501';
      END IF;
      n := 0;
      DELETE FROM public.rtdb_nodes WHERE path = p OR (path >= p || '/' AND path < p || '0');
    ELSIF op->>'o' = 'put' THEN
      -- مرحلتان: نتحقق من كل الأوراق أولاً (حتى لا يرى التحقق أوراقاً أُدرجت للتو من نفس العملية) ثم نكتب
      FOR leaf IN SELECT * FROM public.rtdb_flatten(p, op->'v') LOOP
        IF NOT public.rtdb_can_write(leaf.path, leaf.value, u) THEN
          RAISE EXCEPTION 'permission denied: %', leaf.path USING ERRCODE = '42501';
        END IF;
      END LOOP;
      INSERT INTO public.rtdb_nodes(path, top, scope, value)
      SELECT f.path, split_part(f.path,'/',1), public.rtdb_scope(f.path), f.value
      FROM public.rtdb_flatten(p, op->'v') f
      ON CONFLICT (path) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
    ELSE
      RAISE EXCEPTION 'bad op';
    END IF;
  END LOOP;
END $$;

CREATE FUNCTION public.rtdb_write(ops jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.rtdb_apply(ops, auth.uid());
$$;

-- معاملة ذرّية: تنفَّذ العمليات فقط إذا كانت القيمة الحالية = المتوقعة (وإلا تعيد القيمة الحالية ليعيد العميل المحاولة)
CREATE FUNCTION public.rtdb_tx(p_path text, p_expected jsonb, p_ops jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cur jsonb;
BEGIN
  IF NOT public.rtdb_valid_path(p_path) THEN RAISE EXCEPTION 'bad path'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_path, 0));
  cur := public.rtdb_read(p_path);
  IF cur IS DISTINCT FROM coalesce(p_expected, '{}'::jsonb) THEN
    RETURN jsonb_build_object('ok', false, 'cur', cur);
  END IF;
  PERFORM public.rtdb_apply(p_ops, auth.uid());
  RETURN jsonb_build_object('ok', true);
END $$;

------------------------------------------------------------------------------
-- 7) إشعارات اللحظي (Realtime Broadcast): نبضة صغيرة تحمل المسار فقط، والعميل يعيد القراءة
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_notify_stmt() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  BEGIN
    IF TG_OP = 'DELETE' THEN
      FOR r IN SELECT top AS k, 't:'||top AS topic, array_agg(path) AS ps FROM old_rows GROUP BY top
               UNION ALL SELECT scope, 's:'||scope, array_agg(path) FROM old_rows GROUP BY scope LOOP
        PERFORM realtime.send(jsonb_build_object('p', r.ps[1:20]), 'c', r.topic, true);
      END LOOP;
    ELSE
      FOR r IN SELECT top AS k, 't:'||top AS topic, array_agg(path) AS ps FROM new_rows GROUP BY top
               UNION ALL SELECT scope, 's:'||scope, array_agg(path) FROM new_rows GROUP BY scope LOOP
        PERFORM realtime.send(jsonb_build_object('p', r.ps[1:20]), 'c', r.topic, true);
      END LOOP;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;   -- لا نُفشل الكتابة بسبب الإشعار
  END;
  RETURN NULL;
END $$;

CREATE TRIGGER rtdb_notify_ins AFTER INSERT ON public.rtdb_nodes
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.rtdb_notify_stmt();
CREATE TRIGGER rtdb_notify_upd AFTER UPDATE ON public.rtdb_nodes
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.rtdb_notify_stmt();
CREATE TRIGGER rtdb_notify_del AFTER DELETE ON public.rtdb_nodes
  REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.rtdb_notify_stmt();

-- السماح للمسجّلين (بمن فيهم الضيوف) بالاستماع للقنوات الخاصة
DO $$
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS rtdb_listen ON realtime.messages';
  EXECUTE 'CREATE POLICY rtdb_listen ON realtime.messages FOR SELECT TO authenticated USING (true)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'تعذّر إنشاء سياسة realtime.messages: %', SQLERRM;
END $$;

------------------------------------------------------------------------------
-- 8) إنشاء الملف الشخصي (يستبدل set(users/uid) الذي صار ممنوعاً)
------------------------------------------------------------------------------
-- نفس خوارزمية الواجهة: 10000000 + (hash*31 + charCode) mod 2^32 mod 90000000
CREATE FUNCTION public.rtdb_public_id(uid text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE h bigint := 0; i int;
BEGIN
  FOR i IN 1..char_length(uid) LOOP
    h := (h * 31 + ascii(substr(uid, i, 1))) % 4294967296;
  END LOOP;
  RETURN (10000000 + (h % 90000000))::text;
END $$;

CREATE FUNCTION public.ensure_profile(p_name text, p_avatar text, p_provider text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); pid text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  pid := public.rtdb_public_id(uid::text);
  IF NOT public.rtdb_exists('users/'||uid) THEN
    INSERT INTO public.rtdb_nodes(path, top, scope, value) VALUES
      ('users/'||uid||'/name', 'users', 'users/'||uid, to_jsonb(left(coalesce(nullif(p_name,''), 'مستخدم '||pid), 40))),
      ('users/'||uid||'/publicId', 'users', 'users/'||uid, to_jsonb(pid)),
      ('users/'||uid||'/createdAt', 'users', 'users/'||uid, to_jsonb((extract(epoch from now())*1000)::bigint)),
      ('users/'||uid||'/authProvider', 'users', 'users/'||uid, to_jsonb(CASE WHEN p_provider IN ('google','facebook') THEN p_provider ELSE 'guest' END));
    IF p_avatar IS NOT NULL AND length(p_avatar) < 2000 THEN
      INSERT INTO public.rtdb_nodes(path, top, scope, value)
      VALUES ('users/'||uid||'/avatarUrl', 'users', 'users/'||uid, to_jsonb(p_avatar));
    END IF;
  END IF;
  INSERT INTO public.rtdb_nodes(path, top, scope, value)
  VALUES ('publicIdIndex/'||pid, 'publicIdIndex', 'publicIdIndex/'||pid, to_jsonb(uid::text))
  ON CONFLICT (path) DO NOTHING;
  RETURN pid;
END $$;

------------------------------------------------------------------------------
-- 9) الصلاحيات
------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rtdb_is_admin(uuid), public.rtdb_num(text), public.rtdb_vip_tier(text), public.rtdb_val(text), public.rtdb_exists(text),
  public.rtdb_can_read(text,uuid), public.rtdb_can_write(text,jsonb,uuid), public.rtdb_apply(jsonb,uuid),
  public.rtdb_notify_stmt() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rtdb_read(text), public.rtdb_write(jsonb), public.rtdb_tx(text,jsonb,jsonb),
  public.ensure_profile(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rtdb_read(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rtdb_write(jsonb), public.rtdb_tx(text,jsonb,jsonb),
  public.ensure_profile(text,text,text) TO authenticated;
