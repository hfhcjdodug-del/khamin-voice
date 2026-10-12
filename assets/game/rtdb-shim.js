/*
 * rtdb-shim.js — طبقة توافق: تجعل كود اللعبة (المكتوب لـ Firebase v8) يعمل على Supabase.
 * تنفّذ الجزء المستخدم من firebase.database() / firebase.auth() فوق دوال Postgres في 01_game_core.sql.
 * تُحمَّل بعد supabase.js وبعد config.js.
 */
(function () {
  'use strict';
  var CFG = window.KHAMIN_CONFIG || {};
  var sb = window.supabase.createClient(CFG.url, CFG.key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: 'khamin-auth' },
    realtime: { params: { eventsPerSecond: 20 } }
  });

  /* ---------------------------------------------------------------- أدوات المسارات */
  function normPath(p) {
    p = String(p == null ? '' : p).replace(/^\/+|\/+$/g, '');
    return p;
  }
  function joinPath(a, b) { a = normPath(a); b = normPath(b); return a && b ? a + '/' + b : (a || b); }
  function isPrefix(a, b) { return a === b || b.indexOf(a + '/') === 0; }
  function related(a, b) { return !a || !b || isPrefix(a, b) || isPrefix(b, a); }

  var TS = { '.sv': 'timestamp' };
  function resolveSv(v) {
    if (v && typeof v === 'object') {
      if (v['.sv'] === 'timestamp') return Date.now();
      if (Array.isArray(v)) return v.map(resolveSv);
      var o = {};
      Object.keys(v).forEach(function (k) { var r = resolveSv(v[k]); if (r !== undefined) o[k] = r; });
      return o;
    }
    return v;
  }

  // خريطة مسطّحة {المسار الكامل: قيمة} -> شجرة تحت base
  function unflatten(map, base) {
    var keys = Object.keys(map);
    if (!keys.length) return null;
    if (map.hasOwnProperty(base)) return map[base];
    var root = {};
    var cut = base ? base.length + 1 : 0;
    keys.forEach(function (full) {
      var segs = full.substring(cut).split('/');
      var node = root;
      for (var i = 0; i < segs.length - 1; i++) {
        if (typeof node[segs[i]] !== 'object' || node[segs[i]] === null) node[segs[i]] = {};
        node = node[segs[i]];
      }
      node[segs[segs.length - 1]] = map[full];
    });
    return arrayify(root);
  }
  function arrayify(o) {
    if (o === null || typeof o !== 'object') return o;
    var ks = Object.keys(o);
    ks.forEach(function (k) { o[k] = arrayify(o[k]); });
    if (ks.length && ks.every(function (k) { return /^\d+$/.test(k); })) {
      var max = Math.max.apply(null, ks.map(Number));
      if (max === ks.length - 1) { var a = []; for (var i = 0; i <= max; i++) a.push(o[String(i)]); return a; }
    }
    return o;
  }
  // شجرة -> خريطة مسطّحة (لحساب القيمة المتوقعة في المعاملات)
  function flatten(val, base, out) {
    out = out || {};
    if (val === null || val === undefined) return out;
    if (typeof val === 'object') {
      Object.keys(val).forEach(function (k) { flatten(val[k], base + '/' + k, out); });
    } else out[base] = val;
    return out;
  }

  /* ---------------------------------------------------------------- RPC */
  function rpc(name, args) {
    return sb.rpc(name, args || {}).then(function (r) {
      if (r.error) { var e = new Error(r.error.message || 'rpc error'); e.code = r.error.code; e.details = r.error; throw e; }
      return r.data;
    });
  }
  function readFlat(path) { return rpc('rtdb_read', { p_path: path }); }

  /* ---------------------------------------------------------------- لقطة البيانات */
  function Snapshot(path, val) {
    this._path = path; this._val = val === undefined ? null : val;
    this.key = path ? path.split('/').pop() : null;
    this.ref = new Reference(path);
  }
  Snapshot.prototype.val = function () { return this._val === undefined ? null : clone(this._val); };
  Snapshot.prototype.exists = function () { return this._val !== null && this._val !== undefined; };
  Snapshot.prototype.child = function (p) {
    var v = this._val, segs = normPath(p).split('/').filter(Boolean);
    for (var i = 0; i < segs.length; i++) { v = (v && typeof v === 'object') ? v[segs[i]] : null; if (v === undefined) v = null; }
    return new Snapshot(joinPath(this._path, p), v);
  };
  Snapshot.prototype.hasChildren = function () { return !!this._val && typeof this._val === 'object' && Object.keys(this._val).length > 0; };
  Snapshot.prototype.numChildren = function () { return this.hasChildren() ? Object.keys(this._val).length : 0; };
  Snapshot.prototype.forEach = function (cb) {
    if (!this.hasChildren()) return false;
    var self = this, keys = this._order || Object.keys(this._val);
    for (var i = 0; i < keys.length; i++) {
      if (cb(new Snapshot(joinPath(self._path, keys[i]), self._val[keys[i]])) === true) return true;
    }
    return false;
  };
  Snapshot.prototype.toJSON = function () { return this.val(); };
  function clone(v) { return v && typeof v === 'object' ? JSON.parse(JSON.stringify(v)) : v; }

  /* ---------------------------------------------------------------- ترتيب الاستعلامات */
  function typeRank(v) {
    if (v === null || v === undefined) return 0;
    if (v === false) return 1; if (v === true) return 2;
    if (typeof v === 'number') return 3; if (typeof v === 'string') return 4; return 5;
  }
  function cmpVal(a, b) {
    var ra = typeRank(a), rb = typeRank(b);
    if (ra !== rb) return ra - rb;
    if (ra === 3) return a - b;
    if (ra === 4) return a < b ? -1 : a > b ? 1 : 0;
    return 0;
  }
  function applyQuery(val, q) {
    // يعيد {val, order} بعد الترتيب/التصفية/الحد
    if (!q || !Object.keys(q).length || !val || typeof val !== 'object') return { val: val, order: null };
    var keys = Object.keys(val);
    var getv = function (k) {
      if (q.orderBy === 'child') { var c = val[k]; return (c && typeof c === 'object') ? (c[q.child] === undefined ? null : c[q.child]) : null; }
      if (q.orderBy === 'value') return val[k];
      return k;
    };
    if (q.orderBy) keys.sort(function (a, b) { var d = cmpVal(getv(a), getv(b)); return d || (a < b ? -1 : a > b ? 1 : 0); });
    else keys.sort();
    if (q.equalTo !== undefined) keys = keys.filter(function (k) { return cmpVal(getv(k), q.equalTo) === 0; });
    if (q.startAt !== undefined) keys = keys.filter(function (k) { return cmpVal(getv(k), q.startAt) >= 0; });
    if (q.endAt !== undefined) keys = keys.filter(function (k) { return cmpVal(getv(k), q.endAt) <= 0; });
    if (q.limitLast != null) keys = keys.slice(Math.max(0, keys.length - q.limitLast));
    if (q.limitFirst != null) keys = keys.slice(0, q.limitFirst);
    var out = {};
    keys.forEach(function (k) { out[k] = val[k]; });
    return { val: keys.length ? out : null, order: keys };
  }

  /* ---------------------------------------------------------------- معرّف push مرتّب زمنياً */
  var _lastPush = 0, _rnd = [];
  function pushKey() {
    var now = Date.now(), dup = now === _lastPush; _lastPush = now;
    var t = now.toString(36); while (t.length < 9) t = '0' + t;
    var r = '';
    if (!dup) { _rnd = []; for (var i = 0; i < 8; i++) _rnd.push(Math.floor(Math.random() * 36)); }
    else { for (var j = 7; j >= 0; j--) { if (_rnd[j] < 35) { _rnd[j]++; break; } _rnd[j] = 0; } }
    for (var k = 0; k < 8; k++) r += _rnd[k].toString(36);
    return '-' + t + r;
  }

  /* ---------------------------------------------------------------- المستمعون + Realtime */
  var listeners = [];       // {id, path, event, cb, q, last, lastKeys, fetching, dirty}
  var channels = {};        // topic -> {ch, refs}
  var seq = 0;

  function topicFor(path) {
    var s = path.split('/').filter(Boolean);
    if (!s.length) return null;
    return s.length === 1 ? 't:' + s[0] : 's:' + s[0] + '/' + s[1];
  }
  function ensureChannel(topic) {
    if (!topic) return;
    var c = channels[topic];
    if (c) { c.refs++; return; }
    var ch = sb.channel(topic, { config: { private: true, broadcast: { self: false } } });
    ch.on('broadcast', { event: 'c' }, function (msg) {
      var ps = msg && msg.payload && msg.payload.p;
      pingPaths(Array.isArray(ps) ? ps : null);
    });
    ch.subscribe(function (status) {
      if (status === 'SUBSCRIBED') refreshAll();   // بعد (إعادة) الاتصال: نزامن الجميع
    });
    channels[topic] = { ch: ch, refs: 1 };
  }
  function releaseChannel(topic) {
    var c = channels[topic]; if (!c) return;
    if (--c.refs <= 0) { try { sb.removeChannel(c.ch); } catch (e) {} delete channels[topic]; }
  }
  function pingPaths(paths) {
    listeners.forEach(function (l) {
      if (!paths || paths.length >= 20 || paths.some(function (p) { return related(l.path, p); })) schedule(l);
    });
  }
  function refreshAll() { listeners.forEach(schedule); }

  function schedule(l) {
    if (l.dead) return;
    if (l.fetching) { l.dirty = true; return; }
    if (l.timer) return;
    l.timer = setTimeout(function () { l.timer = null; run(l); }, 25);
  }
  function run(l) {
    if (l.dead) return;
    l.fetching = true; l.dirty = false;
    readFlat(l.path).then(function (map) {
      if (l.dead) return;
      var val = unflatten(map, l.path);
      deliver(l, val);
    }).catch(function (e) {
      if (!l.errored) { l.errored = true; console.warn('[rtdb] listen failed', l.path, e && e.message); }
    }).then(function () {
      l.fetching = false;
      if (l.dirty) schedule(l);
    });
  }
  function deliver(l, val) {
    var q = applyQuery(val, l.q);
    var shown = q.val;
    var sig = JSON.stringify(shown) + '|' + JSON.stringify(q.order);
    if (l.event === 'value') {
      if (l.first || sig !== l.sig) {
        l.first = false; l.sig = sig;
        var s = new Snapshot(l.path, shown); s._order = q.order; try { l.cb(s); } catch (e) { console.error(e); }
      }
      return;
    }
    var prev = l.prevVal || {}, cur = shown && typeof shown === 'object' ? shown : {};
    var order = q.order || Object.keys(cur);
    if (l.event === 'child_added') {
      order.forEach(function (k) { if (!(k in prev)) { try { l.cb(new Snapshot(joinPath(l.path, k), cur[k])); } catch (e) { console.error(e); } } });
    } else if (l.event === 'child_removed') {
      Object.keys(prev).forEach(function (k) { if (!(k in cur)) { try { l.cb(new Snapshot(joinPath(l.path, k), prev[k])); } catch (e) { console.error(e); } } });
    } else if (l.event === 'child_changed') {
      order.forEach(function (k) { if (k in prev && JSON.stringify(prev[k]) !== JSON.stringify(cur[k])) { try { l.cb(new Snapshot(joinPath(l.path, k), cur[k])); } catch (e) { console.error(e); } } });
    }
    l.prevVal = clone(cur); l.first = false;
  }
  function addListener(path, event, cb, q) {
    var l = { id: ++seq, path: path, event: event, cb: cb, q: q, first: true, prevVal: {}, topic: topicFor(path) };
    listeners.push(l);
    ensureChannel(l.topic);
    schedule(l);
    return l;
  }
  function removeListeners(path, event, cb) {
    listeners = listeners.filter(function (l) {
      var hit = l.path === path && (!event || l.event === event) && (!cb || l.cb === cb);
      if (hit) { l.dead = true; releaseChannel(l.topic); }
      return !hit;
    });
  }
  // مزامنة دورية احتياطية (ضياع إشعار لحظي)
  setInterval(function () { if (!document.hidden) refreshAll(); }, 45000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) refreshAll(); });
  window.addEventListener('online', function () { refreshAll(); connectedEmit(true); });
  window.addEventListener('offline', function () { connectedEmit(false); });

  /* ---------------------------------------------------------------- الكتابة */
  function writeOps(ops, touched) {
    return rpc('rtdb_write', { ops: ops }).then(function () { touchLocal(touched); });
  }
  function touchLocal(paths) {
    // نُعيد القراءة فوراً للمستمعين المعنيّين (دون انتظار بث Realtime)
    listeners.forEach(function (l) { if (paths.some(function (p) { return related(l.path, p); })) schedule(l); });
  }
  function opsForSet(path, value) {
    var ops = [{ o: 'del', p: path }];
    value = resolveSv(value);
    if (value !== null && value !== undefined) ops.push({ o: 'put', p: path, v: value });
    return ops;
  }

  /* ---------------------------------------------------------------- Reference / Query */
  function Query(path, q) { this.path = path; this.q = q || {}; this.key = path ? path.split('/').pop() : null; }
  Query.prototype._with = function (extra) {
    var q = {}; var self = this; Object.keys(this.q).forEach(function (k) { q[k] = self.q[k]; });
    Object.keys(extra).forEach(function (k) { q[k] = extra[k]; });
    return new Query(this.path, q);
  };
  Query.prototype.orderByChild = function (c) { return this._with({ orderBy: 'child', child: c }); };
  Query.prototype.orderByKey = function () { return this._with({ orderBy: 'key' }); };
  Query.prototype.orderByValue = function () { return this._with({ orderBy: 'value' }); };
  Query.prototype.limitToLast = function (n) { return this._with({ limitLast: n }); };
  Query.prototype.limitToFirst = function (n) { return this._with({ limitFirst: n }); };
  Query.prototype.startAt = function (v) { return this._with({ startAt: v }); };
  Query.prototype.endAt = function (v) { return this._with({ endAt: v }); };
  Query.prototype.equalTo = function (v) { return this._with({ equalTo: v }); };
  Query.prototype.once = function (event, cb) {
    var self = this;
    var p = readFlat(this.path).then(function (map) {
      var q = applyQuery(unflatten(map, self.path), self.q);
      var s = new Snapshot(self.path, q.val); s._order = q.order;
      return s;
    });
    if (typeof cb === 'function') p.then(cb);
    return p;
  };
  Query.prototype.on = function (event, cb) { addListener(this.path, event, cb, this.q); return cb; };
  Query.prototype.off = function (event, cb) { removeListeners(this.path, event, cb); };
  Query.prototype.get = function () { return this.once('value'); };

  function Reference(path) { Query.call(this, normPath(path), null); }
  Reference.prototype = Object.create(Query.prototype);
  Reference.prototype.constructor = Reference;
  Reference.prototype.child = function (p) { return new Reference(joinPath(this.path, p)); };
  Object.defineProperty(Reference.prototype, 'parent', { get: function () { var s = this.path.split('/'); s.pop(); return new Reference(s.join('/')); } });
  Object.defineProperty(Reference.prototype, 'root', { get: function () { return new Reference(''); } });
  Reference.prototype.toString = function () { return '/' + this.path; };
  Reference.prototype.set = function (value) {
    if (!this.path) return Promise.reject(new Error('cannot set root'));
    return writeOps(opsForSet(this.path, value), [this.path]);
  };
  Reference.prototype.remove = function () { return writeOps([{ o: 'del', p: this.path }], [this.path]); };
  Reference.prototype.update = function (map) {
    var ops = [], touched = [], base = this.path;
    Object.keys(map || {}).forEach(function (k) {
      var full = joinPath(base, k); touched.push(full);
      ops = ops.concat(opsForSet(full, map[k]));
    });
    if (!ops.length) return Promise.resolve();
    return writeOps(ops, touched);
  };
  Reference.prototype.push = function (value) {
    var ref = new Reference(joinPath(this.path, pushKey()));
    if (value === undefined) return ref;
    var p = ref.set(value);
    ref.then = function (a, b) { return p.then(a, b); };
    ref.catch = function (b) { return p.catch(b); };
    return ref;
  };
  Reference.prototype.transaction = function (fn) {
    var path = this.path, tries = 0;
    function attempt() {
      return readFlat(path).then(function (map) {
        var cur = unflatten(map, path);
        var next = fn(clone(cur));
        if (next === undefined) return { committed: false, snapshot: new Snapshot(path, cur) };
        next = resolveSv(next);
        var ops = opsForSet(path, next);
        return rpc('rtdb_tx', { p_path: path, p_expected: map, p_ops: ops }).then(function (r) {
          if (r && r.ok) { touchLocal([path]); return { committed: true, snapshot: new Snapshot(path, next === undefined ? null : next) }; }
          if (++tries > 8) throw new Error('transaction: too many retries');
          return attempt();
        });
      });
    }
    return attempt();
  };
  Reference.prototype.onDisconnect = function () { return new OnDisconnect(this.path); };

  /* ---------------------------------------------------------------- onDisconnect (حضور على الخادم + تنفيذ فوري عند الإغلاق) */
  var disc = {};   // path -> 'remove'
  function OnDisconnect(path) { this.path = path; }
  OnDisconnect.prototype.remove = function () { disc[this.path] = 'remove'; beat(); return Promise.resolve(); };
  OnDisconnect.prototype.cancel = function () {
    delete disc[this.path];
    return rpc('rtdb_ephemeral_clear', { p_path: this.path }).catch(function () {});
  };
  OnDisconnect.prototype.set = function () { return Promise.resolve(); };   // غير مستخدم
  function beat() {
    var paths = Object.keys(disc);
    if (!paths.length) return;
    rpc('rtdb_heartbeat', { p_paths: paths }).catch(function () {});
  }
  setInterval(beat, 20000);
  function flushDisconnect() {
    var ops = Object.keys(disc).map(function (p) { return { o: 'del', p: p }; });
    if (!ops.length) return;
    try { rpc('rtdb_write', { ops: ops }); } catch (e) {}
  }
  window.addEventListener('pagehide', flushDisconnect);

  // .info/connected
  var connectedCbs = [];
  function connectedEmit(v) { connectedCbs.forEach(function (cb) { try { cb(new Snapshot('.info/connected', v)); } catch (e) {} }); }

  /* ---------------------------------------------------------------- واجهة firebase.database() */
  var database = {
    ref: function (p) {
      p = normPath(p);
      if (p === '.info/connected') {
        return {
          on: function (ev, cb) { connectedCbs.push(cb); setTimeout(function () { cb(new Snapshot('.info/connected', navigator.onLine !== false)); }, 0); return cb; },
          off: function () { connectedCbs = []; }
        };
      }
      return new Reference(p);
    }
  };
  var dbFn = function () { return database; };
  dbFn.ServerValue = { TIMESTAMP: TS };

  /* ---------------------------------------------------------------- المصادقة */
  var currentUser = null, authCbs = [], authReady = null;
  function toUser(u) {
    if (!u) return null;
    var m = u.user_metadata || {};
    var prov = (u.app_metadata && u.app_metadata.provider) || 'anonymous';
    return {
      uid: u.id, email: u.email || null, isAnonymous: !!u.is_anonymous,
      displayName: m.full_name || m.name || null, photoURL: m.avatar_url || m.picture || null,
      providerId: prov
    };
  }
  sb.auth.onAuthStateChange(function (event, session) {
    var nu = toUser(session && session.user);
    var changed = (nu && nu.uid) !== (currentUser && currentUser.uid);
    currentUser = nu;
    if (changed) authCbs.slice().forEach(function (cb) { try { cb(currentUser); } catch (e) {} });
    if (changed && channels) { try { sb.realtime.setAuth(session ? session.access_token : null); } catch (e) {} }
  });
  var authObj = {
    get currentUser() { return currentUser; },
    onAuthStateChanged: function (cb) {
      authCbs.push(cb);
      (authReady || Promise.resolve()).then(function () { try { cb(currentUser); } catch (e) {} });
      return function () { authCbs = authCbs.filter(function (x) { return x !== cb; }); };
    },
    signInWithEmailAndPassword: function (email, pass) {
      return sb.auth.signInWithPassword({ email: email, password: pass }).then(function (r) {
        if (r.error) { var e = new Error(r.error.message); e.code = 'auth/wrong-password'; throw e; }
        return { user: toUser(r.data.user) };
      });
    },
    signInAnonymously: function () {
      return sb.auth.signInAnonymously().then(function (r) {
        if (r.error) throw r.error; return { user: toUser(r.data.user) };
      });
    },
    signOut: function () { return sb.auth.signOut(); }
  };
  var authFn = function () { return authObj; };
  authFn.GoogleAuthProvider = function () { this.providerId = 'google.com'; };

  window.firebase = {
    apps: [1], initializeApp: function () {},
    auth: authFn, database: dbFn,
    storage: function () { return { ref: function () { throw new Error('storage غير مدعوم بعد'); } }; }
  };

  /* ---------------------------------------------------------------- واجهة Khamin (المصادقة والاتصال بالتطبيق الأم) */
  var inApp = !!(window.KhaminBridge && window.KhaminBridge.postMessage);
  function bridge(msg) { try { window.KhaminBridge.postMessage(JSON.stringify(msg)); } catch (e) {} }

  var K = window.khamin = {
    sb: sb, rpc: rpc, inApp: inApp,
    uid: null,
    // تسجيل الدخول عبر مزوّد (google | facebook): داخل التطبيق يتولاه Flutter (متصفح النظام)، وفي المتصفح يتم بالتحويل
    signInWithProvider: function (provider) {
      if (inApp) { bridge({ type: 'oauth', provider: provider }); return new Promise(function () {}); }
      return sb.auth.signInWithOAuth({ provider: provider, options: { redirectTo: location.href.split('#')[0] } });
    },
    // يستدعيها Flutter بعد عودة المستخدم من تسجيل الدخول
    setSession: function (access, refresh) {
      return sb.auth.setSession({ access_token: access, refresh_token: refresh }).then(function (r) {
        if (r.error) throw r.error; return r.data.session;
      });
    },
    signOut: function () { return sb.auth.signOut(); }
  };
  window.__khaminSetSession = function (a, r) {
    K.setSession(a, r).then(function () { location.reload(); }).catch(function (e) {
      console.warn('setSession failed', e); if (window.showToast) window.showToast('تعذّر تسجيل الدخول', 'error');
    });
  };

  // جاهزية الهوية: جلسة موجودة، أو عودة OAuth في الرابط، أو دخول ضيف مجهول
  K.ready = authReady = (function () {
    return new Promise(function (resolve) {
      var done = false;
      function finish(u) { if (done) return; done = true; K.uid = u ? u.uid : null; currentUser = u; resolve(u); }
      function fromHash() {
        var h = location.hash && location.hash.indexOf('access_token=') >= 0 ? location.hash.substring(1) : null;
        if (!h) return Promise.resolve(false);
        var pr = new URLSearchParams(h);
        return K.setSession(pr.get('access_token'), pr.get('refresh_token')).then(function () {
          history.replaceState(null, '', location.pathname + location.search); return true;
        }).catch(function () { return false; });
      }
      fromHash().then(function () { return sb.auth.getSession(); }).then(function (r) {
        var s = r && r.data && r.data.session;
        if (s && s.user) return finish(toUser(s.user));
        return sb.auth.signInAnonymously().then(function (r2) {
          if (r2.error) { console.error('anonymous sign-in failed', r2.error); finish(null); }
          else finish(toUser(r2.data.user));
        });
      }).catch(function (e) { console.error(e); finish(null); });
    });
  })();
})();
