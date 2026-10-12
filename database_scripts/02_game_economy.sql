-- 02_game_economy.sql — الاقتصاد على الخادم: العملات، الألماس، المتجر، VIP، الروليت، الهدية اليومية، الخبرة
-- كل عمليات الربح والإنفاق تتم هنا فقط (العميل لا يستطيع تعديل أرصدته مباشرة).
-- شغّله بعد 01_game_core.sql.

------------------------------------------------------------------------------
-- أدوات داخلية
------------------------------------------------------------------------------
CREATE FUNCTION public.rtdb_set(p text, v jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.rtdb_nodes(path, top, scope, value)
  VALUES (p, split_part(p,'/',1), public.rtdb_scope(p), v)
  ON CONFLICT (path) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
$$;

CREATE FUNCTION public.rtdb_del(p text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.rtdb_nodes WHERE path = p OR (path >= p || '/' AND path < p || '0');
$$;

-- شجرة JSON متداخلة لعقدة (للقراءة من الإعدادات داخل الدوال)
CREATE FUNCTION public.rtdb_tree(p text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb; r jsonb := '{}'::jsonb; k text;
BEGIN
  SELECT value INTO v FROM public.rtdb_nodes WHERE path = p;
  IF v IS NOT NULL THEN RETURN v; END IF;
  FOR k IN SELECT DISTINCT split_part(substr(path, length(p) + 2), '/', 1)
           FROM public.rtdb_nodes WHERE path >= p || '/' AND path < p || '0' LOOP
    r := r || jsonb_build_object(k, public.rtdb_tree(p || '/' || k));
  END LOOP;
  IF r = '{}'::jsonb THEN RETURN NULL; END IF;
  RETURN r;
END $$;

CREATE FUNCTION public.econ_lock(uid uuid) RETURNS void
LANGUAGE sql AS $$ SELECT pg_advisory_xact_lock(hashtextextended('econ:' || uid::text, 0)) $$;

CREATE FUNCTION public.econ_add(uid uuid, field text, amount numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF field NOT IN ('coins','diamonds','xp') THEN RAISE EXCEPTION 'bad field'; END IF;
  PERFORM public.rtdb_set('users/'||uid||'/'||field, to_jsonb(public.rtdb_num('users/'||uid||'/'||field) + amount));
END $$;

CREATE FUNCTION public.econ_spend(uid uuid, field text, amount numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cur numeric;
BEGIN
  IF field NOT IN ('coins','diamonds') THEN RAISE EXCEPTION 'bad field'; END IF;
  IF amount < 0 THEN RAISE EXCEPTION 'bad amount'; END IF;
  cur := public.rtdb_num('users/'||uid||'/'||field);
  IF cur < amount THEN RAISE EXCEPTION 'insufficient_funds' USING ERRCODE = 'P0001'; END IF;
  PERFORM public.rtdb_set('users/'||uid||'/'||field, to_jsonb(cur - amount));
END $$;

CREATE FUNCTION public.now_ms() RETURNS numeric LANGUAGE sql STABLE AS $$ SELECT floor(extract(epoch from now())*1000) $$;

------------------------------------------------------------------------------
-- 1) شراء إطار / دخولية من المتجر
------------------------------------------------------------------------------
CREATE FUNCTION public.buy_shop_item(p_kind text, p_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid(); base text; cfg jsonb; price numeric; disc numeric; cur text; ownedField text; val jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  IF p_kind NOT IN ('frame','entrance') OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_\-]{1,60}$' THEN RAISE EXCEPTION 'bad item'; END IF;
  PERFORM public.econ_lock(uid);
  base := 'settings/shop/' || CASE WHEN p_kind = 'frame' THEN 'frames/' ELSE 'entrances/' END || p_key;
  cfg := coalesce(public.rtdb_tree(base), '{}'::jsonb);
  price := coalesce((cfg->>'price')::numeric, CASE WHEN p_kind = 'frame' THEN 200 ELSE 150 END);
  disc := greatest(0, least(90, coalesce((cfg->>'discount')::numeric, 0)));
  price := greatest(0, round(price * (1 - disc/100)));
  cur := CASE WHEN cfg->>'currency' = 'diamonds' THEN 'diamonds' ELSE 'coins' END;
  ownedField := CASE WHEN p_kind = 'frame' THEN 'ownedFrames' ELSE 'ownedEntrances' END;
  IF public.rtdb_exists('users/'||uid||'/'||ownedField||'/'||p_key) THEN RAISE EXCEPTION 'already_owned' USING ERRCODE = 'P0001'; END IF;
  PERFORM public.econ_spend(uid, cur, price);
  IF coalesce(cfg->>'permanent','true') = 'false' THEN
    PERFORM public.rtdb_set('users/'||uid||'/'||ownedField||'/'||p_key||'/until',
            to_jsonb(public.now_ms() + coalesce((cfg->>'days')::numeric, 7) * 86400000));
  ELSE
    PERFORM public.rtdb_set('users/'||uid||'/'||ownedField||'/'||p_key, 'true'::jsonb);
  END IF;
  RETURN jsonb_build_object('ok', true, 'price', price, 'currency', cur);
END $$;

------------------------------------------------------------------------------
-- 2) فتح فئة مدفوعة بالألماس
------------------------------------------------------------------------------
CREATE FUNCTION public.unlock_category(p_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); price numeric;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  PERFORM public.econ_lock(uid);
  IF NOT public.rtdb_exists('gameCategories/'||p_key) THEN RAISE EXCEPTION 'no such category'; END IF;
  price := public.rtdb_num('gameCategories/'||p_key||'/price');
  IF NOT public.rtdb_exists('users/'||uid||'/unlockedCategories/'||p_key) THEN
    PERFORM public.econ_spend(uid, 'diamonds', price);
    PERFORM public.rtdb_set('users/'||uid||'/unlockedCategories/'||p_key, 'true'::jsonb);
  END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

------------------------------------------------------------------------------
-- 3) شراء VIP (شهر واحد) + جوائز المستويات الجديدة + معرّف مميز
------------------------------------------------------------------------------
CREATE FUNCTION public.buy_vip(p_tier int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid(); price numeric; cur int; got int; t int; b jsonb;
  dia numeric := 0; coi numeric := 0; frames jsonb := '[]'::jsonb; wantsId boolean := false; custom text := null;
  poolRow record; idVal text;
  defaults numeric[] := ARRAY[100,250,500,900,1500,2500,5000];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  IF p_tier IS NULL OR p_tier < 1 OR p_tier > 7 THEN RAISE EXCEPTION 'bad tier'; END IF;
  PERFORM public.econ_lock(uid);
  cur := public.rtdb_vip_tier(uid::text);
  IF cur >= p_tier THEN RAISE EXCEPTION 'already_owned' USING ERRCODE = 'P0001'; END IF;
  price := CASE WHEN public.rtdb_exists('settings/shop/vipPrices/'||p_tier)
                THEN public.rtdb_num('settings/shop/vipPrices/'||p_tier) ELSE defaults[p_tier] END;
  PERFORM public.econ_spend(uid, 'diamonds', price);
  PERFORM public.rtdb_set('users/'||uid||'/vipTier', to_jsonb(p_tier));
  PERFORM public.rtdb_set('users/'||uid||'/vipExpiry', to_jsonb(public.now_ms() + 2592000000::numeric));
  -- جوائز المستويات التي لم تُمنح بعد
  got := public.rtdb_num('users/'||uid||'/vipBonusTier')::int;
  FOR t IN got + 1 .. p_tier LOOP
    b := public.rtdb_tree('settings/shop/vipBonuses/'||t);
    IF b IS NULL THEN CONTINUE; END IF;
    dia := dia + coalesce((b->>'diamonds')::numeric, 0);
    coi := coi + coalesce((b->>'coins')::numeric, 0);
    IF coalesce(b->>'frameId','') <> '' THEN
      PERFORM public.rtdb_set('users/'||uid||'/ownedFrames/'||(b->>'frameId'), 'true'::jsonb);
      frames := frames || to_jsonb(b->>'frameId');
    END IF;
    IF coalesce(b->>'grantPremiumId','false') IN ('true','t','1') THEN wantsId := true; END IF;
  END LOOP;
  IF p_tier > got THEN PERFORM public.rtdb_set('users/'||uid||'/vipBonusTier', to_jsonb(p_tier)); END IF;
  IF dia > 0 THEN PERFORM public.econ_add(uid, 'diamonds', dia); END IF;
  IF coi > 0 THEN PERFORM public.econ_add(uid, 'coins', coi); END IF;
  IF wantsId THEN
    FOR poolRow IN SELECT path, value FROM public.rtdb_nodes WHERE path >= 'premiumIdPool/' AND path < 'premiumIdPool0' ORDER BY path LOOP
      idVal := btrim(poolRow.value #>> '{}');
      IF idVal IS NULL OR idVal = '' OR idVal !~ '^[^/]{1,30}$' THEN CONTINUE; END IF;
      IF public.rtdb_exists('publicIdIndex/'||idVal) THEN CONTINUE; END IF;
      PERFORM public.rtdb_set('publicIdIndex/'||idVal, to_jsonb(uid::text));
      PERFORM public.rtdb_set('users/'||uid||'/customId', to_jsonb(idVal));
      PERFORM public.rtdb_del(poolRow.path);
      custom := idVal;
      EXIT;
    END LOOP;
  END IF;
  RETURN jsonb_build_object('ok', true, 'tier', p_tier, 'diamonds', dia, 'coins', coi, 'frames', frames, 'customId', custom);
END $$;

-- يُستدعى عند اكتشاف انتهاء الاشتراك
CREATE FUNCTION public.vip_expire_check() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RETURN; END IF;
  IF public.rtdb_exists('users/'||uid||'/vipTier')
     AND public.rtdb_num('users/'||uid||'/vipExpiry') < public.now_ms() THEN
    PERFORM public.rtdb_del('users/'||uid||'/vipTier');
    PERFORM public.rtdb_del('users/'||uid||'/vipExpiry');
  END IF;
END $$;

------------------------------------------------------------------------------
-- 4) الروليت اليومي (السحب والجائزة على الخادم)
------------------------------------------------------------------------------
CREATE FUNCTION public.spin_roulette() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid(); cfg jsonb; k text; p jsonb; prizes jsonb[] := ARRAY[]::jsonb[];
  total numeric := 0; r numeric; i int; chosen jsonb; idx int := 0;
  defaults jsonb := '[
    {"id":"c1","type":"coins","amount":50,"weight":26},
    {"id":"c2","type":"coins","amount":150,"weight":18},
    {"id":"d1","type":"diamonds","amount":5,"weight":20},
    {"id":"d2","type":"diamonds","amount":15,"weight":12},
    {"id":"d3","type":"diamonds","amount":40,"weight":5},
    {"id":"x1","type":"coins","amount":20,"weight":15},
    {"id":"e1","type":"entrance","itemId":"s_comet","weight":1}]';
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  PERFORM public.econ_lock(uid);
  IF public.rtdb_num('users/'||uid||'/lastRoulette') > public.now_ms() - 86400000 THEN
    RAISE EXCEPTION 'cooldown' USING ERRCODE = 'P0001';
  END IF;
  cfg := public.rtdb_tree('settings/shop/roulette');
  IF cfg IS NULL THEN
    FOR p IN SELECT * FROM jsonb_array_elements(defaults) LOOP prizes := prizes || p; END LOOP;
  ELSE
    FOR k IN SELECT kk FROM jsonb_object_keys(cfg) kk ORDER BY kk::int LOOP
      prizes := prizes || (cfg->k);
    END LOOP;
  END IF;
  -- نفس تصفية الواجهة: عملات/ألماس بكمية > 0، وغيرها يحتاج itemId
  prizes := ARRAY(SELECT x FROM unnest(prizes) x
                  WHERE CASE WHEN x->>'type' IN ('coins','diamonds') THEN coalesce((x->>'amount')::numeric,0) > 0
                             ELSE coalesce(x->>'itemId','') <> '' END);
  IF coalesce(array_length(prizes,1),0) = 0 THEN RAISE EXCEPTION 'no_prizes' USING ERRCODE = 'P0001'; END IF;
  FOREACH p IN ARRAY prizes LOOP total := total + coalesce(nullif((p->>'weight')::numeric,0), 1); END LOOP;
  r := random() * total;
  FOR i IN 1 .. array_length(prizes,1) LOOP
    r := r - coalesce(nullif((prizes[i]->>'weight')::numeric,0), 1);
    IF r <= 0 THEN idx := i - 1; EXIT; END IF;
  END LOOP;
  chosen := prizes[idx + 1];
  PERFORM public.rtdb_set('users/'||uid||'/lastRoulette', to_jsonb(public.now_ms()));
  IF chosen->>'type' = 'coins' THEN PERFORM public.econ_add(uid, 'coins', (chosen->>'amount')::numeric);
  ELSIF chosen->>'type' = 'diamonds' THEN PERFORM public.econ_add(uid, 'diamonds', (chosen->>'amount')::numeric);
  ELSIF chosen->>'type' = 'frame' THEN PERFORM public.rtdb_set('users/'||uid||'/ownedFrames/'||(chosen->>'itemId'), 'true'::jsonb);
  ELSIF chosen->>'type' = 'entrance' THEN PERFORM public.rtdb_set('users/'||uid||'/ownedEntrances/'||(chosen->>'itemId'), 'true'::jsonb);
  END IF;
  RETURN jsonb_build_object('ok', true, 'idx', idx, 'id', chosen->>'id');
END $$;

------------------------------------------------------------------------------
-- 5) هدية اليوم
------------------------------------------------------------------------------
CREATE FUNCTION public.claim_daily_gift() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); cfg jsonb; n int; day int; g jsonb; k text; gifts jsonb[] := ARRAY[]::jsonb[];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  PERFORM public.econ_lock(uid);
  cfg := public.rtdb_tree('settings/dailyGifts');
  IF cfg IS NULL OR jsonb_typeof(cfg) <> 'object' THEN RAISE EXCEPTION 'no_gifts' USING ERRCODE = 'P0001'; END IF;
  IF public.rtdb_num('users/'||uid||'/lastDailyGift') > public.now_ms() - 86400000 THEN
    RAISE EXCEPTION 'cooldown' USING ERRCODE = 'P0001';
  END IF;
  FOR k IN SELECT kk FROM jsonb_object_keys(cfg) kk ORDER BY kk::int LOOP gifts := gifts || (cfg->k); END LOOP;
  n := array_length(gifts, 1);
  day := public.rtdb_num('users/'||uid||'/dailyGiftDay')::int % n;
  g := gifts[day + 1];
  PERFORM public.rtdb_set('users/'||uid||'/lastDailyGift', to_jsonb(public.now_ms()));
  IF g->>'type' = 'coins' THEN PERFORM public.econ_add(uid, 'coins', coalesce((g->>'amount')::numeric, 0));
  ELSIF g->>'type' = 'diamonds' THEN PERFORM public.econ_add(uid, 'diamonds', coalesce((g->>'amount')::numeric, 0));
  ELSIF g->>'type' = 'frame' AND coalesce(g->>'frameId','') <> '' THEN
    IF coalesce(g->>'permanent','true') = 'false' THEN
      PERFORM public.rtdb_set('users/'||uid||'/ownedFrames/'||(g->>'frameId')||'/until',
              to_jsonb(public.now_ms() + coalesce((g->>'days')::numeric, 7) * 86400000));
    ELSE
      PERFORM public.rtdb_set('users/'||uid||'/ownedFrames/'||(g->>'frameId'), 'true'::jsonb);
    END IF;
  END IF;
  PERFORM public.rtdb_set('users/'||uid||'/dailyGiftDay', to_jsonb((day + 1) % n));
  RETURN jsonb_build_object('ok', true, 'day', day, 'gift', g);
END $$;

------------------------------------------------------------------------------
-- 6) إرسال دعم (عملات/ألماس) لمستخدم آخر
------------------------------------------------------------------------------
CREATE FUNCTION public.send_support(p_to uuid, p_currency text, p_amount bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); f text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  IF p_to IS NULL OR p_to = uid OR p_amount IS NULL OR p_amount < 1 OR p_amount > 1000000000 THEN RAISE EXCEPTION 'bad request'; END IF;
  IF NOT public.rtdb_exists('users/'||p_to) THEN RAISE EXCEPTION 'no such user'; END IF;
  f := CASE WHEN p_currency = 'diamonds' THEN 'diamonds' ELSE 'coins' END;
  -- ترتيب ثابت للأقفال لتفادي التشابك
  IF uid < p_to THEN PERFORM public.econ_lock(uid); PERFORM public.econ_lock(p_to);
  ELSE PERFORM public.econ_lock(p_to); PERFORM public.econ_lock(uid); END IF;
  PERFORM public.econ_spend(uid, f, p_amount);
  PERFORM public.econ_add(p_to, f, p_amount);
  RETURN jsonb_build_object('ok', true);
END $$;

------------------------------------------------------------------------------
-- 7) الخبرة (XP): فتح التطبيق مرة كل 12 ساعة، مباراة مرة لكل لعبة وبحد يومي
------------------------------------------------------------------------------
CREATE FUNCTION public.award_xp(p_kind text, p_ref text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); amt numeric; p1 text; p2 text; today text; cnt numeric;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  PERFORM public.econ_lock(uid);
  IF p_kind = 'open' THEN
    IF public.rtdb_num('users/'||uid||'/lastOpenXp') > public.now_ms() - 43200000 THEN RETURN jsonb_build_object('ok', false); END IF;
    amt := coalesce(nullif(public.rtdb_num('settings/levelConfig/xpPerOpen'),0), 5);
    PERFORM public.rtdb_set('users/'||uid||'/lastOpenXp', to_jsonb(public.now_ms()));
  ELSIF p_kind = 'match' THEN
    IF p_ref IS NULL OR p_ref !~ '^[A-Za-z0-9_\-]{1,40}$' THEN RAISE EXCEPTION 'bad ref'; END IF;
    p1 := public.rtdb_val('games/'||p_ref||'/player1') #>> '{}';
    p2 := public.rtdb_val('games/'||p_ref||'/player2') #>> '{}';
    IF uid::text NOT IN (coalesce(p1,''), coalesce(p2,'')) THEN RAISE EXCEPTION 'not a player'; END IF;
    IF public.rtdb_exists('games/'||p_ref||'/xpGiven/'||uid) THEN RETURN jsonb_build_object('ok', false); END IF;
    today := to_char(now() AT TIME ZONE 'UTC', 'YYYYMMDD');
    IF public.rtdb_val('users/'||uid||'/xpMatchDate') #>> '{}' IS DISTINCT FROM today THEN
      PERFORM public.rtdb_set('users/'||uid||'/xpMatchDate', to_jsonb(today));
      PERFORM public.rtdb_set('users/'||uid||'/xpMatchCount', to_jsonb(0));
    END IF;
    cnt := public.rtdb_num('users/'||uid||'/xpMatchCount');
    IF cnt >= 30 THEN RETURN jsonb_build_object('ok', false, 'reason', 'daily_cap'); END IF;
    PERFORM public.rtdb_set('users/'||uid||'/xpMatchCount', to_jsonb(cnt + 1));
    PERFORM public.rtdb_set('games/'||p_ref||'/xpGiven/'||uid, 'true'::jsonb);
    amt := coalesce(nullif(public.rtdb_num('settings/levelConfig/xpPerMatch'),0), 15);
  ELSE
    RAISE EXCEPTION 'bad kind';
  END IF;
  PERFORM public.econ_add(uid, 'xp', amt);
  RETURN jsonb_build_object('ok', true, 'xp', amt);
END $$;

------------------------------------------------------------------------------
-- الصلاحيات
------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rtdb_set(text,jsonb), public.rtdb_del(text), public.rtdb_tree(text),
  public.econ_lock(uuid), public.econ_add(uuid,text,numeric), public.econ_spend(uuid,text,numeric),
  public.now_ms() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.buy_shop_item(text,text), public.unlock_category(text), public.buy_vip(int), public.vip_expire_check(),
  public.spin_roulette(), public.claim_daily_gift(), public.send_support(uuid,text,bigint), public.award_xp(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buy_shop_item(text,text), public.unlock_category(text), public.buy_vip(int), public.vip_expire_check(),
  public.spin_roulette(), public.claim_daily_gift(), public.send_support(uuid,text,bigint), public.award_xp(text,text) TO authenticated;
