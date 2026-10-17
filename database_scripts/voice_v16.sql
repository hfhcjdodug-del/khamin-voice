-- =====================================================================
-- v16: أوضاع المايكات (2 / 8 / 12 مقعد ضيوف + مقعد المضيف) وتغيير اسم الروم
--  آمن لو أعدت تشغيله
-- =====================================================================
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS mic_count smallint NOT NULL DEFAULT 8;
DO $$ BEGIN
  ALTER TABLE public.rooms ADD CONSTRAINT rooms_mic_count_chk CHECK (mic_count IN (2, 8, 12));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.room_seats DROP CONSTRAINT IF EXISTS room_seats_seat_no_check;
ALTER TABLE public.room_seats ADD CONSTRAINT room_seats_seat_no_check CHECK (seat_no BETWEEN 0 AND 12);

CREATE OR REPLACE FUNCTION public.take_seat(p_room uuid, p_seat int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.rooms%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO r FROM rooms WHERE id = p_room AND is_live;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not live'; END IF;
  IF p_seat < 0 OR p_seat > r.mic_count THEN RAISE EXCEPTION 'bad seat'; END IF;
  IF p_seat = 0 AND r.host_id <> auth.uid() THEN RAISE EXCEPTION 'host only'; END IF;
  DELETE FROM room_seats WHERE room_id = p_room AND user_id = auth.uid();
  INSERT INTO room_seats(room_id, seat_no, user_id) VALUES (p_room, p_seat, auth.uid());
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'seat taken';
END $$;

-- صاحب الروم يغيّر عدد المايكات؛ من يجلس على مقعد محذوف يُنزَل
CREATE OR REPLACE FUNCTION public.set_room_mic_count(p_room uuid, p_count int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_count NOT IN (2, 8, 12) THEN RAISE EXCEPTION 'bad count'; END IF;
  UPDATE rooms SET mic_count = p_count WHERE id = p_room AND host_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'owner only'; END IF;
  DELETE FROM room_seats WHERE room_id = p_room AND seat_no > p_count;
END $$;

CREATE OR REPLACE FUNCTION public.room_rename(p_room uuid, p_title text, p_topic text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t text := btrim(coalesce(p_title, ''));
BEGIN
  IF char_length(t) < 2 OR char_length(t) > 60 THEN RAISE EXCEPTION 'bad title'; END IF;
  UPDATE rooms SET title = t, topic = left(btrim(coalesce(p_topic, '')), 120)
  WHERE id = p_room AND host_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'owner only'; END IF;
END $$;

REVOKE ALL ON FUNCTION public.take_seat(uuid, int), public.set_room_mic_count(uuid, int),
  public.room_rename(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.take_seat(uuid, int), public.set_room_mic_count(uuid, int),
  public.room_rename(uuid, text, text) TO authenticated;
