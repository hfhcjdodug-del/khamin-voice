-- نتونس — التحديث 9: الياقوت ♦ (يحصل عليه مستلم الهدايا ويحوّله إلى جواهر).
-- كل 20 جوهرة تُهدى لك = ياقوتة، وكل ياقوتة تُحوَّل إلى 10 جواهر. آمن لو أعدت تشغيله.

ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS ruby_pts int NOT NULL DEFAULT 0 CHECK (ruby_pts >= 0);

DROP FUNCTION IF EXISTS public.my_wallet();
CREATE FUNCTION public.my_wallet()
RETURNS TABLE(gems int, ads_free boolean, ruby_pts int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT w.gems FROM wallets w WHERE w.user_id = auth.uid()), 0),
         coalesce((SELECT w.ads_free FROM wallets w WHERE w.user_id = auth.uid()), false),
         coalesce((SELECT w.ruby_pts FROM wallets w WHERE w.user_id = auth.uid()), 0);
$$;

INSERT INTO public.app_settings(key, value) VALUES ('ruby_pts_per', '20'), ('ruby_to_gems', '10')
ON CONFLICT (key) DO NOTHING;

-- تحويل الياقوت إلى جواهر: p_count = 0 يعني تحويل الكل
CREATE OR REPLACE FUNCTION public.convert_rubies(p_count int)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE per int := setting_int('ruby_pts_per', 20); mult int := setting_int('ruby_to_gems', 10); pts int; n int; g int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT ruby_pts INTO pts FROM wallets WHERE user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'no rubies'; END IF;
  n := pts / per;
  IF p_count > 0 THEN n := least(n, p_count); END IF;
  IF n < 1 THEN RAISE EXCEPTION 'no rubies'; END IF;
  g := n * mult;
  UPDATE wallets SET ruby_pts = ruby_pts - n * per, gems = gems + g WHERE user_id = auth.uid();
  RETURN g;
END $$;

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
  -- الياقوت: كل 20 جوهرة مستلمة = ياقوتة (تُحفظ كنقاط ليبقى الكسر)
  INSERT INTO wallets(user_id) VALUES (p_to) ON CONFLICT DO NOTHING;
  UPDATE wallets SET ruby_pts = ruby_pts + total WHERE user_id = p_to;
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


REVOKE ALL ON FUNCTION public.my_wallet(), public.convert_rubies(int), public.send_gift(uuid, uuid, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_wallet(), public.convert_rubies(int), public.send_gift(uuid, uuid, uuid, int) TO authenticated;
