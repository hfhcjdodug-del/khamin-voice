-- =====================================================================
-- v18: المزرعة — مراقبة المدير + تعديل المضاعفات + تسمية العنصر الأخير
--  • admin_farm_overview(): رهانات الجولة الحالية لكل عنصر، وآخر 20 جولة (الرهان/المدفوع)
--  • المدير يعدّل مضاعف كل عنصر (farm_items.mult). احتمال كل عنصر = 1/المضاعف تلقائياً
--    (العنصر ذو المضاعف الأعلى أندر)، ونسبة الدفع farm_payout_pct تحدد ربح اللعبة.
--  آمن لو أعدت تشغيله
-- =====================================================================
UPDATE public.farm_items SET name = 'ستيك', emoji = '🍖' WHERE idx = 7 AND name = 'ذهب';

DROP POLICY IF EXISTS farm_items_admin ON public.farm_items;
CREATE POLICY farm_items_admin ON public.farm_items FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT UPDATE ON public.farm_items TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_farm_overview() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rd farm_rounds%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO rd FROM farm_rounds WHERE NOT settled ORDER BY id DESC LIMIT 1;
  RETURN jsonb_build_object(
    'round_id', rd.id,
    'ends_in', CASE WHEN rd.id IS NULL THEN NULL
                    ELSE greatest(0, extract(epoch FROM rd.ends_at - now()))::numeric(6,1) END,
    'live', coalesce((
      SELECT jsonb_agg(jsonb_build_object('item', i.idx, 'name', i.name, 'emoji', i.emoji, 'mult', i.mult,
                                          'staked', coalesce(s.a, 0), 'players', coalesce(s.p, 0)) ORDER BY i.idx)
      FROM farm_items i
      LEFT JOIN (SELECT item, sum(amount)::int AS a, count(*)::int AS p FROM farm_bets
                  WHERE round_id = rd.id GROUP BY item) s ON s.item = i.idx), '[]'::jsonb),
    'rounds', coalesce((
      SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id DESC) FROM (
        SELECT fr.id, fr.result, coalesce(sum(b.amount), 0)::int AS staked, coalesce(sum(b.payout), 0)::int AS paid
        FROM farm_rounds fr LEFT JOIN farm_bets b ON b.round_id = fr.id
        WHERE fr.settled GROUP BY fr.id ORDER BY fr.id DESC LIMIT 20) r), '[]'::jsonb),
    'today_staked', coalesce((SELECT sum(amount) FROM farm_bets WHERE created_at >= date_trunc('day', now())), 0),
    'today_paid', coalesce((SELECT sum(payout) FROM farm_bets WHERE created_at >= date_trunc('day', now())), 0)
  );
END $$;
REVOKE ALL ON FUNCTION public.admin_farm_overview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_farm_overview() TO authenticated;
