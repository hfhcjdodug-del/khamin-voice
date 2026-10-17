-- =====================================================================
-- v15: ترند الأسبوع في قائمة الرومات
--  list_rooms_v2() = list_rooms() + week_support (الجواهر المُهداة لمضيف الروم داخل رومه آخر 7 أيام)
--  آمن لو أعدت تشغيله
-- =====================================================================
DROP FUNCTION IF EXISTS public.list_rooms_v2();
CREATE FUNCTION public.list_rooms_v2()
RETURNS TABLE(id uuid, title text, topic text, host_id uuid, host_name text, host_avatar text,
              listeners int, seated int, created_at timestamptz,
              host_xp int, friends int, bg_preset text, bg_url text, locked boolean, week_support bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.title, r.topic, r.host_id, p.name, p.avatar_url,
         (SELECT count(*)::int FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         (SELECT count(*)::int FROM room_seats s WHERE s.room_id = r.id),
         r.created_at,
         p.xp,
         (SELECT count(*)::int FROM room_members m JOIN follows f ON f.followee = m.user_id AND f.follower = auth.uid()
           WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds'),
         r.bg_preset, r.bg_url,
         r.locked,
         (SELECT coalesce(sum(l.gems), 0)::bigint FROM gift_log l
           WHERE l.room_id = r.id AND l.to_id = r.host_id AND l.created_at > now() - interval '7 days')
  FROM rooms r JOIN profiles p ON p.id = r.host_id
  WHERE r.is_live
    AND ( r.created_at > now() - interval '3 minutes'
          OR EXISTS (SELECT 1 FROM room_members m WHERE m.room_id = r.id AND m.last_seen > now() - interval '45 seconds') )
  ORDER BY 15 DESC, 7 DESC, r.created_at DESC
  LIMIT 100;
$$;
REVOKE ALL ON FUNCTION public.list_rooms_v2() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_rooms_v2() TO authenticated;
