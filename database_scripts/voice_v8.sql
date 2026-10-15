-- نتونس — التحديث 8: هدايا مصوّرة بأسعارها، مستوى للمُهدي والمستلم، إعلان عام للدعم الكبير،
-- سجل الهدايا في الشرف، وترتيب الغرف حسب الدعم. شغّله بعد voice_v7.sql (آمن لو أعدت تشغيله).

-- ===== 1) الإعدادات =====
INSERT INTO public.app_settings(key, value) VALUES
  ('gift_xp_sender', '2'),     -- نقاط خبرة لكل جوهرة يرسلها
  ('gift_xp_receiver', '1'),   -- نقاط خبرة لكل جوهرة يستلمها
  ('bcast_t1', '500'), ('bcast_t2', '2000'), ('bcast_t3', '5000')   -- حدود الإعلان العام (جواهر في إهداء واحد)
ON CONFLICT (key) DO NOTHING;

-- ===== 2) الهدايا المصوّرة (الصور داخل التطبيق: assets/gifts) =====
DELETE FROM public.gifts WHERE image_url IS NULL AND name IN ('وردة', 'قلب', 'كأس', 'تاج', 'سيارة', 'قصر');
ALTER TABLE public.gifts ADD COLUMN IF NOT EXISTS code int;   -- رقم الصورة الداخلية
INSERT INTO public.gifts(name, price, image_url, sort, emoji, code)
SELECT v.n, v.p, v.u, v.s, '🎁', v.s
FROM (VALUES
  ('دب', 1, 'asset:gifts/1.png', 1),
  ('وردة', 1, 'asset:gifts/2.png', 2),
  ('إعجاب', 2, 'asset:gifts/3.png', 3),
  ('قلب', 2, 'asset:gifts/4.png', 4),
  ('حلوى النجوم', 3, 'asset:gifts/5.png', 5),
  ('قلب الإصبع', 3, 'asset:gifts/6.png', 6),
  ('عصير ليمون', 4, 'asset:gifts/7.png', 7),
  ('كوك', 4, 'asset:gifts/8.png', 8),
  ('السلام', 5, 'asset:gifts/9.png', 9),
  ('عصير برتقال', 5, 'asset:gifts/10.png', 10),
  ('قبلة', 5, 'asset:gifts/11.png', 11),
  ('قهوة', 6, 'asset:gifts/12.png', 12),
  ('دونات', 8, 'asset:gifts/13.png', 13),
  ('فراشة', 8, 'asset:gifts/14.png', 14),
  ('كعكة', 9, 'asset:gifts/15.png', 15),
  ('برطمان العسل', 10, 'asset:gifts/16.png', 16),
  ('بودينغ الكرز', 10, 'asset:gifts/17.png', 17),
  ('كعكة الفراولة', 10, 'asset:gifts/18.png', 18),
  ('رسالة الحب', 12, 'asset:gifts/19.png', 19),
  ('كباب', 15, 'asset:gifts/20.png', 20),
  ('مسدس الحب', 15, 'asset:gifts/21.png', 21),
  ('سنجاب الفطر', 20, 'asset:gifts/22.png', 22),
  ('نجمة الأحلام', 20, 'asset:gifts/23.png', 23),
  ('صديق البالونات', 25, 'asset:gifts/24.png', 24),
  ('قلبان متشابكان', 25, 'asset:gifts/25.png', 25),
  ('أيدٍ متشابكة', 30, 'asset:gifts/26.png', 26),
  ('غرامافون', 30, 'asset:gifts/27.png', 27),
  ('كرة سحرية', 35, 'asset:gifts/28.png', 28),
  ('أرجيلة', 40, 'asset:gifts/29.png', 29),
  ('قلب الورود', 40, 'asset:gifts/30.png', 30),
  ('قلادة الوردة', 45, 'asset:gifts/31.png', 31),
  ('فتاة القمر', 50, 'asset:gifts/32.png', 32),
  ('جمل', 55, 'asset:gifts/33.png', 33),
  ('قلعة وردية', 60, 'asset:gifts/34.png', 34),
  ('هلال الأحلام', 60, 'asset:gifts/35.png', 35),
  ('ساعة رملية', 65, 'asset:gifts/36.png', 36),
  ('صندوق القمر', 70, 'asset:gifts/37.png', 37),
  ('بساط الريح', 80, 'asset:gifts/38.png', 38),
  ('صندوق الكنز', 90, 'asset:gifts/39.png', 39),
  ('منطاد الحب', 100, 'asset:gifts/40.png', 40),
  ('نافورة الذهب', 100, 'asset:gifts/41.png', 41),
  ('صندوق الجواهر', 110, 'asset:gifts/42.png', 42),
  ('ساعة ذهبية', 120, 'asset:gifts/43.png', 43),
  ('خزنة الذهب', 130, 'asset:gifts/44.png', 44),
  ('قطار الذهب', 140, 'asset:gifts/45.png', 45),
  ('تاج الأجنحة', 150, 'asset:gifts/46.png', 46),
  ('العرش', 160, 'asset:gifts/47.png', 47),
  ('سفينة الذهب', 180, 'asset:gifts/48.png', 48),
  ('الأسد الملكي', 200, 'asset:gifts/49.png', 49),
  ('قصر الأحلام', 220, 'asset:gifts/50.png', 50),
  ('قلعة القمر', 250, 'asset:gifts/51.png', 51),
  ('أرجوحة الكابلز', 280, 'asset:gifts/52.png', 52),
  ('سيف الجليد', 300, 'asset:gifts/53.png', 53),
  ('جيب النمر', 350, 'asset:gifts/54.png', 54),
  ('منصة الدي جي', 400, 'asset:gifts/55.png', 55),
  ('موكب السيارات', 450, 'asset:gifts/56.png', 56),
  ('برج الألعاب النارية', 500, 'asset:gifts/57.png', 57),
  ('سيارة رياضية فخمة', 700, 'asset:gifts/58.png', 58),
  ('قصر الجليد', 1500, 'asset:gifts/59.png', 59),
  ('الملك والملكة', 2500, 'asset:gifts/60.png', 60),
  ('حفلة الزفاف', 3000, 'asset:gifts/61.png', 61),
  ('الحفل الراقي', 5000, 'asset:gifts/62.png', 62)
) AS v(n, p, u, s)
WHERE NOT EXISTS (SELECT 1 FROM public.gifts g WHERE g.name = v.n);

-- ===== 3) الإعلان العام للدعم الكبير =====
CREATE TABLE IF NOT EXISTS public.gift_broadcasts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id uuid REFERENCES public.rooms(id) ON DELETE SET NULL,
  from_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_name text NOT NULL,
  to_name text NOT NULL,
  gems int NOT NULL,
  tier int NOT NULL CHECK (tier BETWEEN 1 AND 3),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.gift_broadcasts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gb_read ON public.gift_broadcasts;
CREATE POLICY gb_read ON public.gift_broadcasts FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.gift_broadcasts TO authenticated;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.gift_broadcasts; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ===== 4) إهداء: خصم + نقاط خبرة للطرفين + إعلان عام + دعم الترند =====
CREATE OR REPLACE FUNCTION public.send_gift(p_room uuid, p_to uuid, p_gift uuid, p_qty int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g gifts%ROWTYPE; r rooms%ROWTYPE; total int; w int; me_name text; to_name text; sup int; tier int := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_qty < 1 OR p_qty > 99 THEN RAISE EXCEPTION 'bad qty'; END IF;
  IF p_to = auth.uid() THEN RAISE EXCEPTION 'not allowed'; END IF;
  SELECT * INTO g FROM gifts WHERE id = p_gift AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'bad gift'; END IF;
  SELECT * INTO r FROM rooms WHERE id = p_room AND is_live;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not live'; END IF;
  IF p_to <> r.host_id AND NOT EXISTS (
       SELECT 1 FROM room_members m WHERE m.room_id = p_room AND m.user_id = p_to
         AND m.last_seen > now() - interval '60 seconds') THEN
    RAISE EXCEPTION 'target not in room';
  END IF;
  total := g.price * p_qty;
  INSERT INTO wallets(user_id) VALUES (auth.uid()) ON CONFLICT DO NOTHING;
  SELECT gems INTO w FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF w < total THEN RAISE EXCEPTION 'not enough gems'; END IF;
  UPDATE wallets SET gems = gems - total WHERE user_id = auth.uid();
  INSERT INTO gift_log(room_id, from_id, to_id, gift_id, qty, gems) VALUES (p_room, auth.uid(), p_to, p_gift, p_qty, total);
  SELECT name INTO me_name FROM profiles WHERE id = auth.uid();
  SELECT name INTO to_name FROM profiles WHERE id = p_to;
  INSERT INTO room_messages(room_id, user_id, body, kind, meta)
  VALUES (p_room, auth.uid(),
          'أهدى ' || to_name || ' ' || g.name || ' ×' || p_qty, 'gift',
          jsonb_build_object('gift_id', g.id, 'name', g.name, 'emoji', g.emoji, 'image_url', g.image_url,
                             'qty', p_qty, 'gems', total, 'to_id', p_to, 'to_name', to_name));
  -- مستوى المُهدي والمستلم
  UPDATE profiles SET xp = xp + total * setting_int('gift_xp_sender', 2) WHERE id = auth.uid();
  UPDATE profiles SET xp = xp + total * setting_int('gift_xp_receiver', 1) WHERE id = p_to;
  -- إعلان عام في كل الغرف كلما كبر الدعم
  IF total >= setting_int('bcast_t3', 5000) THEN tier := 3;
  ELSIF total >= setting_int('bcast_t2', 2000) THEN tier := 2;
  ELSIF total >= setting_int('bcast_t1', 500) THEN tier := 1; END IF;
  IF tier > 0 THEN
    INSERT INTO gift_broadcasts(room_id, from_id, to_id, from_name, to_name, gems, tier)
    VALUES (p_room, auth.uid(), p_to, me_name, to_name, total, tier);
  END IF;
  -- دعم صاحب الغرفة فقط يرفع الروم (ترند + ترتيب)
  sup := r.support_total;
  IF p_to = r.host_id THEN
    sup := r.support_total + total;
    UPDATE rooms SET support_total = sup,
      trend_until = CASE WHEN sup >= setting_int('trend_threshold', 700)
                         THEN now() + make_interval(hours => setting_int('trend_hours', 3)) ELSE trend_until END
    WHERE id = p_room;
  END IF;
  RETURN sup;
END $$;

-- ===== 5) الهدايا المستلمة (تظهر في الشرف) =====
CREATE OR REPLACE FUNCTION public.user_gifts(p_id uuid)
RETURNS TABLE(gift_id uuid, name text, emoji text, image_url text, qty bigint, gems bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT g.id, g.name, g.emoji, g.image_url, sum(l.qty), sum(l.gems)
  FROM gift_log l JOIN gifts g ON g.id = l.gift_id
  WHERE l.to_id = p_id
  GROUP BY g.id, g.name, g.emoji, g.image_url
  ORDER BY sum(l.gems) DESC LIMIT 60;
$$;

CREATE OR REPLACE FUNCTION public.user_gift_totals(p_id uuid)
RETURNS TABLE(received bigint, sent bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT sum(gems) FROM gift_log WHERE to_id = p_id), 0)::bigint,
         coalesce((SELECT sum(gems) FROM gift_log WHERE from_id = p_id), 0)::bigint;
$$;

-- ===== 6) قائمة الغرف: الترند أولاً مرتّبة حسب الدعم (المركز 1 ثم 2 ثم 3) =====
DROP FUNCTION IF EXISTS public.list_rooms();
CREATE FUNCTION public.list_rooms()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text,
              listeners int, seated int, created_at timestamptz,
              host_xp int, friends int, bg_preset text, bg_url text, trending boolean, support int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         (SELECT count(*)::int FROM room_seats s WHERE s.room_id = r.id),
         r.created_at,
         p.xp,
         (SELECT count(*)::int FROM room_members m JOIN follows f ON f.followee = m.user_id AND f.follower = auth.uid()
           WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         r.bg_preset, r.bg_url,
         coalesce(r.trend_until > now(), false),
         r.support_total
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 14 DESC, (CASE WHEN coalesce(r.trend_until > now(), false) THEN r.support_total ELSE 0 END) DESC, 7 DESC, r.created_at DESC
  LIMIT 100;
$$;

REVOKE ALL ON FUNCTION public.user_gifts(uuid), public.user_gift_totals(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_gifts(uuid), public.user_gift_totals(uuid), public.send_gift(uuid, uuid, uuid, int),
  public.list_rooms() TO authenticated;
