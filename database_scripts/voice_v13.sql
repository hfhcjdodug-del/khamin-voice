-- =====================================================================
-- v13: قفل الروم بكلمة مرور (يُفرض من الخادم)
--  • صاحب الروم يضع كلمة مرور (4-16 حرفاً)؛ من لا يعرفها لا يدخل
--  • من كان داخل الروم لحظة وضع الكلمة يبقى فيها
--  • بعد 5 محاولات خاطئة يُمنع المحاول 10 دقائق
--  • تغيير الكلمة أو إزالتها يلغي صلاحيات الدخول السابقة
-- آمن لو أعدت تشغيله
-- =====================================================================

-- أسرار الروم في جدول منفصل لا يقرؤه العملاء إطلاقاً
CREATE TABLE IF NOT EXISTS public.room_secrets (
  room_id uuid PRIMARY KEY REFERENCES public.rooms(id) ON DELETE CASCADE,
  salt text NOT NULL,
  hash text NOT NULL,
  ver  int  NOT NULL DEFAULT 1
);
ALTER TABLE public.room_secrets ENABLE ROW LEVEL SECURITY;   -- بدون سياسات

CREATE TABLE IF NOT EXISTS public.room_access (
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ver int NOT NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);
ALTER TABLE public.room_access ENABLE ROW LEVEL SECURITY;    -- بدون سياسات

CREATE TABLE IF NOT EXISTS public.room_pass_attempts (
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  fails int NOT NULL DEFAULT 0,
  blocked_until timestamptz,
  PRIMARY KEY (room_id, user_id)
);
ALTER TABLE public.room_pass_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._room_hash(p_salt text, p_pass text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT encode(sha256(convert_to(p_salt || ':' || p_pass, 'UTF8')), 'hex') $$;

-- هل يستطيع المستخدم الحالي دخول الروم؟
CREATE OR REPLACE FUNCTION public.can_enter_room(p_room uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE lk boolean; hid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  SELECT locked, host_id INTO lk, hid FROM rooms WHERE id = p_room;
  IF NOT FOUND THEN RETURN false; END IF;
  IF NOT lk OR hid = auth.uid() THEN RETURN true; END IF;
  RETURN EXISTS (
    SELECT 1 FROM room_access a JOIN room_secrets s ON s.room_id = a.room_id AND s.ver = a.ver
    WHERE a.room_id = p_room AND a.user_id = auth.uid());
END $$;

-- وضع / تغيير / إزالة كلمة المرور (للمالك فقط). كلمة فارغة = إزالة القفل
CREATE OR REPLACE FUNCTION public.set_room_password(p_room uuid, p_pass text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE hid uuid; pw text := coalesce(btrim(p_pass), ''); s text; v int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT host_id INTO hid FROM rooms WHERE id = p_room;
  IF NOT FOUND OR hid <> auth.uid() THEN RAISE EXCEPTION 'owner only'; END IF;
  IF pw = '' THEN
    UPDATE rooms SET locked = false WHERE id = p_room;
    DELETE FROM room_secrets WHERE room_id = p_room;
    DELETE FROM room_access WHERE room_id = p_room;
    DELETE FROM room_pass_attempts WHERE room_id = p_room;
    RETURN;
  END IF;
  IF char_length(pw) < 4 OR char_length(pw) > 16 THEN RAISE EXCEPTION 'bad password'; END IF;
  s := gen_random_uuid()::text;
  SELECT coalesce(max(ver), 0) + 1 INTO v FROM room_secrets WHERE room_id = p_room;
  INSERT INTO room_secrets(room_id, salt, hash, ver) VALUES (p_room, s, _room_hash(s, pw), v)
  ON CONFLICT (room_id) DO UPDATE SET salt = excluded.salt, hash = excluded.hash, ver = excluded.ver;
  UPDATE rooms SET locked = true WHERE id = p_room;
  DELETE FROM room_access WHERE room_id = p_room;
  DELETE FROM room_pass_attempts WHERE room_id = p_room;
  -- الموجودون الآن داخل الروم يبقون فيها
  INSERT INTO room_access(room_id, user_id, ver)
  SELECT p_room, m.user_id, v FROM room_members m
  WHERE m.room_id = p_room AND m.user_id <> hid AND m.last_seen > now() - interval '60 seconds'
  ON CONFLICT DO NOTHING;
END $$;

-- محاولة الدخول بكلمة مرور. ترجع: ok | wrong:<المتبقي> | blocked
CREATE OR REPLACE FUNCTION public.join_room_with_password(p_room uuid, p_pass text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE hid uuid; sec room_secrets%ROWTYPE; att room_pass_attempts%ROWTYPE; f int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT host_id INTO hid FROM rooms WHERE id = p_room AND is_live;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not live'; END IF;
  IF hid = auth.uid() THEN RETURN 'ok'; END IF;
  IF EXISTS (SELECT 1 FROM room_flags WHERE room_id = p_room AND user_id = auth.uid() AND kicked_until > now()) THEN
    RAISE EXCEPTION 'kicked';
  END IF;
  SELECT * INTO sec FROM room_secrets WHERE room_id = p_room;
  IF NOT FOUND THEN RETURN 'ok'; END IF;
  SELECT * INTO att FROM room_pass_attempts WHERE room_id = p_room AND user_id = auth.uid();
  IF FOUND AND att.blocked_until IS NOT NULL AND att.blocked_until > now() THEN RETURN 'blocked'; END IF;
  IF _room_hash(sec.salt, coalesce(p_pass, '')) = sec.hash THEN
    INSERT INTO room_access(room_id, user_id, ver) VALUES (p_room, auth.uid(), sec.ver)
    ON CONFLICT (room_id, user_id) DO UPDATE SET ver = excluded.ver, granted_at = now();
    DELETE FROM room_pass_attempts WHERE room_id = p_room AND user_id = auth.uid();
    RETURN 'ok';
  END IF;
  f := coalesce(att.fails, 0) + 1;
  IF f >= 5 THEN
    INSERT INTO room_pass_attempts(room_id, user_id, fails, blocked_until)
    VALUES (p_room, auth.uid(), 0, now() + interval '10 minutes')
    ON CONFLICT (room_id, user_id) DO UPDATE SET fails = 0, blocked_until = now() + interval '10 minutes';
    RETURN 'blocked';
  END IF;
  INSERT INTO room_pass_attempts(room_id, user_id, fails) VALUES (p_room, auth.uid(), f)
  ON CONFLICT (room_id, user_id) DO UPDATE SET fails = f, blocked_until = NULL;
  RETURN 'wrong:' || (5 - f);
END $$;

-- القفل القديم (بدون كلمة) لم يعد موجوداً: النسخ القديمة من التطبيق لا تستطيع إغلاق الروم بلا كلمة
CREATE OR REPLACE FUNCTION public.set_room_locked(p_room uuid, p_locked boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_locked THEN RAISE EXCEPTION 'update the app'; END IF;
  PERFORM set_room_password(p_room, NULL);
END $$;

-- التحقق عند كل نبضة: صلاحية الدخول بدل «كان عضواً من قبل»
CREATE OR REPLACE FUNCTION public.room_heartbeat(p_room uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE live boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF EXISTS (SELECT 1 FROM room_flags WHERE room_id = p_room AND user_id = auth.uid() AND kicked_until > now()) THEN
    RAISE EXCEPTION 'kicked';
  END IF;
  SELECT is_live INTO live FROM rooms WHERE id = p_room;
  IF live IS NOT TRUE THEN RETURN false; END IF;
  IF NOT can_enter_room(p_room) THEN RAISE EXCEPTION 'room locked'; END IF;
  INSERT INTO room_members(room_id, user_id, last_seen) VALUES (p_room, auth.uid(), now())
  ON CONFLICT (room_id, user_id) DO UPDATE SET last_seen = now();
  DELETE FROM room_seats s WHERE s.room_id = p_room AND NOT EXISTS (
    SELECT 1 FROM room_members m WHERE m.room_id = s.room_id AND m.user_id = s.user_id
      AND m.last_seen > now() - interval '45 seconds');
  RETURN true;
END $$;

-- الأقفال القديمة (بلا كلمة مرور) تُفتح لأن القفل صار بكلمة فقط
UPDATE public.rooms r SET locked = false
WHERE r.locked AND NOT EXISTS (SELECT 1 FROM public.room_secrets s WHERE s.room_id = r.id);

REVOKE ALL ON FUNCTION public.can_enter_room(uuid), public.set_room_password(uuid, text),
  public.join_room_with_password(uuid, text), public.set_room_locked(uuid, boolean),
  public.room_heartbeat(uuid), public._room_hash(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_enter_room(uuid), public.set_room_password(uuid, text),
  public.join_room_with_password(uuid, text), public.set_room_locked(uuid, boolean),
  public.room_heartbeat(uuid) TO authenticated;
