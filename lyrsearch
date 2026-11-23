#!/usr/bin/env python3
import argparse, base64, json, os, re, sys, unicodedata
import urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from difflib import SequenceMatcher

LYR_DIR = os.path.expanduser("~/Music/Lyrics")
UA = "Mozilla/5.0 (X11; Linux x86_64) lyrics-widget/2.0"
TIMEOUT = 8
NE_HEAD = {"Referer": "https://music.163.com/", "Cookie": "appver=2.0.2"}
NET_ERRORS = [0]


def fix(s):
    return s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def norm(s):
    s = unicodedata.normalize("NFKC", fix(s or "")).casefold()
    return "".join(ch for ch in s if ch.isalnum())


def sim(a, b):
    a, b = norm(a), norm(b)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    short, long_ = (a, b) if len(a) <= len(b) else (b, a)
    r = SequenceMatcher(None, a, b).ratio()
    if len(short) >= 3 and short in long_ and len(short) / len(long_) >= 0.5:
        return max(0.88, r)
    return r


def clean_title(s):
    s = re.sub(r"\([^)]*\)|\[[^\]]*\]|（[^）]*）|【[^】]*】|《[^》]*》", " ", s)
    s = re.sub(r"\s+-\s+(remaster(ed)?|live|official|lyrics?|video|audio|single|\d{4})\b.*$", "", s, flags=re.I)
    s = re.sub(r"\s+(official|lyric video|lyrics|music video|audio|mv)\b.*$", "", s, flags=re.I)
    s = re.sub(r"\s+(feat|ft)\.?\s.*$", "", s, flags=re.I)
    return re.sub(r"\s+", " ", s).strip(" -–—|")


def artist_options(a):
    a = re.sub(r"\s*-\s*topic$", "", a.strip(), flags=re.I)
    a = re.sub(r"vevo$", "", a, flags=re.I).strip()
    opts = [a] if a else []
    for p in re.split(r"\s*(?:,|;|&|\band\b|\bx\b|\bfeat\.?|\bft\.?)\s*", a, flags=re.I):
        p = p.strip()
        if p and p not in opts:
            opts.append(p)
    return opts[:3]


def build_pairs(title, artist):
    pairs = []

    def add(ar, ti):
        ar, ti = ar.strip(), ti.strip()
        if ti and (ar, ti) not in pairs:
            pairs.append((ar, ti))

    arts = artist_options(artist)
    m = re.match(r"^(.+?)\s+[-–—|]\s+(.+)$", title.strip())
    if m:
        left, right = clean_title(m.group(1)), clean_title(m.group(2))
        add(left, right)
        add(right, left)
        if arts:
            add(arts[0], left)
            add(arts[0], right)
        add("", left)
        add("", right)
    else:
        t = clean_title(title)
        for a in arts[:2]:
            add(a, t)
        add("", t)
    return pairs[:8]


def build_keywords(pairs):
    kws = []
    for ar, ti in pairs:
        k = (ar + " " + ti).strip()
        if k and k not in kws:
            kws.append(k)
    return kws[:6]


def synced(lrc):
    return len(re.findall(r"^\[\d+:\d+", lrc or "", re.M)) >= 3


def http_get(url, headers=None):
    h = {"User-Agent": UA}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def get_json(url, headers=None):
    try:
        return json.loads(http_get(url, headers).decode("utf-8-sig", "replace"))
    except Exception:
        NET_ERRORS[0] += 1
        return None


def pmap(fn, items, workers=8):
    if not items:
        return []

    def safe(x):
        try:
            return fn(x)
        except Exception:
            return None

    with ThreadPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(safe, items))


def src_lrclib(kws, pairs):
    base = "https://lrclib.net/api/search?"
    urls = [base + urllib.parse.urlencode({"track_name": ti, "artist_name": ar}) for ar, ti in pairs if ar][:2]
    urls += [base + urllib.parse.urlencode({"q": k}) for k in kws[:4]]
    out, seen = [], set()
    for lst in pmap(lambda u: get_json(u) or [], urls):
        for r in lst if isinstance(lst, list) else []:
            rid = r.get("id")
            if rid in seen or not r.get("syncedLyrics"):
                continue
            seen.add(rid)
            out.append({
                "source": "LRCLIB", "artist": r.get("artistName") or "",
                "title": r.get("trackName") or "", "album": r.get("albumName") or "",
                "duration": float(r.get("duration") or 0),
                "_fetch": (lambda v=r["syncedLyrics"]: v),
            })
    return out


def src_netease(kws):
    def search(k):
        u = "https://music.163.com/api/search/get/web?" + urllib.parse.urlencode(
            {"csrf_token": "", "hlpretag": "", "hlposttag": "", "s": k,
             "type": 1, "offset": 0, "total": "true", "limit": 8})
        j = get_json(u, NE_HEAD) or {}
        return ((j.get("result") or {}).get("songs")) or []

    out, seen = [], set()
    for songs in pmap(search, kws[:4]):
        for s in songs or []:
            sid = s.get("id")
            if sid in seen:
                continue
            seen.add(sid)

            def fetch(sid=sid):
                u = "https://music.163.com/api/song/lyric?" + urllib.parse.urlencode(
                    {"id": sid, "lv": 1, "kv": 1, "tv": -1})
                j = get_json(u, NE_HEAD) or {}
                return (j.get("lrc") or {}).get("lyric")

            out.append({
                "source": "NetEase",
                "artist": ", ".join(a.get("name", "") for a in (s.get("artists") or [])),
                "title": s.get("name", ""), "album": (s.get("album") or {}).get("name") or "",
                "duration": float(s.get("duration") or 0) / 1000.0, "_fetch": fetch,
            })
    return out


def src_kugou(kws):
    def search(k):
        u = "http://mobilecdn.kugou.com/api/v3/search/song?" + urllib.parse.urlencode(
            {"format": "json", "keyword": k, "page": 1, "pagesize": 8, "showtype": 1})
        j = get_json(u) or {}
        return [(k, i) for i in (((j.get("data") or {}).get("info")) or [])]

    out, seen = [], set()
    for items in pmap(search, kws[:4]):
        for k, s in items or []:
            h = s.get("hash")
            if not h or h in seen:
                continue
            seen.add(h)
            dur = float(s.get("duration") or 0)

            def fetch(h=h, k=k, dur=dur):
                u = "http://lyrics.kugou.com/search?" + urllib.parse.urlencode(
                    {"ver": 1, "man": "yes", "client": "pc", "keyword": k,
                     "hash": h, "timelength": int(dur * 1000)})
                j = get_json(u) or {}
                cands = j.get("candidates") or []
                if not cands:
                    return None
                c = cands[0]
                u2 = "http://lyrics.kugou.com/download?" + urllib.parse.urlencode(
                    {"ver": 1, "client": "pc", "id": c.get("id"),
                     "accesskey": c.get("accesskey"), "fmt": "lrc", "charset": "utf8"})
                j2 = get_json(u2) or {}
                content = j2.get("content")
                if not content:
                    return None
                return base64.b64decode(content).decode("utf-8-sig", "replace")

            out.append({
                "source": "Kugou", "artist": s.get("singername", ""),
                "title": s.get("songname", ""), "album": s.get("album_name", ""),
                "duration": dur, "_fetch": fetch,
            })
    return out


def local_score(stem, pairs, raw_title):
    n = norm(stem)
    nt = norm(raw_title)
    best = 0.0
    if nt and len(nt) >= 4 and (nt in n or (len(n) >= 6 and n in nt)):
        best = 0.97
    for ar, ti in pairs:
        t, a = norm(ti), norm(ar)
        if not t:
            continue
        if t in n:
            if len(t) < 6 and not (a and a in n):
                continue
            best = max(best, 0.8 + (0.15 if a and a in n else 0.0))
        else:
            best = max(best, sim(stem, ar + " " + ti) * 0.9)
    return best


def local_candidates(pairs, raw_title, query=""):
    out = []
    for root, _, files in os.walk(LYR_DIR):
        for f in files:
            if not f.lower().endswith(".lrc"):
                continue
            path = os.path.join(root, f)
            stem = fix(os.path.splitext(f)[0])
            sc = local_score(stem, pairs, raw_title)
            if query:
                sc = max(sc, query_score("", stem, query))
            if sc < 0.75:
                continue
            try:
                with open(path, "rb") as fh:
                    lrc = fh.read().decode("utf-8-sig", "replace")
            except Exception:
                continue
            if not synced(lrc):
                continue
            out.append({"source": "local", "artist": "", "title": stem, "album": "",
                        "duration": 0.0, "score": 1.0 + sc, "lrc": lrc, "path": path})
    return out


def pair_score(c_artist, c_title, pairs):
    best = 0.0
    for ar, ti in pairs:
        ts = sim(ti, c_title)
        s = 0.75 * ts + 0.25 * sim(ar, c_artist) if ar else 0.9 * ts
        best = max(best, s)
    return best


def _tokens(s):
    out = []
    for t in re.findall(r"\w+", unicodedata.normalize("NFKC", fix(s or "")).casefold()):
        if len(t) >= 2 or ord(t[0]) > 127:
            out.append(t)
    return out


def query_score(c_artist, c_title, query):
    cn = norm(c_artist + " " + c_title)
    qn = norm(query)
    if not cn or not qn:
        return 0.0
    if cn == qn:
        return 1.0
    ratio = SequenceMatcher(None, qn, cn).ratio()
    qt, tt = _tokens(query), _tokens(c_title)
    if not qt or not tt:
        return ratio
    c1 = sum(len(t) for t in qt if norm(t) in cn) / float(sum(len(t) for t in qt))
    c2 = sum(len(t) for t in tt if norm(t) in qn) / float(sum(len(t) for t in tt))
    return max(0.6 * c1 + 0.4 * c2, ratio)


def dur_factor(c_dur, length):
    if not length or not c_dur:
        return 0.7
    d = abs(c_dur - length)
    if d <= 2:
        return 1.0
    if d <= 4:
        return 0.85
    if d <= 8:
        return 0.5
    if d <= 15:
        return 0.2
    return 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", default="")
    ap.add_argument("--artist", default="")
    ap.add_argument("--length", type=float, default=0.0)
    ap.add_argument("--query", default="")
    ap.add_argument("--local-only", action="store_true")
    ap.add_argument("--online-only", action="store_true")
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()
    title, artist, query = fix(args.title), fix(args.artist), fix(args.query).strip()
    length = args.length

    if query:
        pairs, raw_title = [("", query)], query
    else:
        pairs, raw_title = build_pairs(title, artist), title
    kws = build_keywords(pairs)

    cands = [] if args.online_only else local_candidates(pairs, raw_title, query)
    if args.local_only:
        cands.sort(key=lambda c: -c["score"])
        sys.stdout.write(json.dumps({"candidates": cands[:14]}))
        return

    metas = []
    with ThreadPoolExecutor(max_workers=3) as ex:
        futs = [ex.submit(src_lrclib, kws, pairs), ex.submit(src_kugou, kws), ex.submit(src_netease, kws)]
        for f in futs:
            try:
                metas += f.result()
            except Exception:
                pass

    for m in metas:
        base = query_score(m["artist"], m["title"], query) if query else pair_score(m["artist"], m["title"], pairs)
        m["score"] = base * (0.5 + 0.5 * dur_factor(m["duration"], length))
    if args.debug:
        sys.stderr.write("pairs: %r\nkeywords: %r\nlength: %r\nnetwork errors: %d\nraw hits: %d\n"
                         % (pairs, kws, length, NET_ERRORS[0], len(metas)))
        for m in sorted(metas, key=lambda x: -x["score"])[:10]:
            sys.stderr.write("  %.2f  %s | %s - %s | %.0fs\n"
                             % (m["score"], m["source"], m["artist"], m["title"], m["duration"]))
    metas = [m for m in metas if m["score"] >= 0.3]
    metas.sort(key=lambda m: -m["score"])

    per, chosen = {}, []
    for m in metas:
        if per.get(m["source"], 0) >= 5:
            continue
        per[m["source"]] = per.get(m["source"], 0) + 1
        chosen.append(m)

    seen = set()
    for m, lrc in zip(chosen, pmap(lambda x: x["_fetch"](), chosen)):
        if not synced(lrc) or hash(lrc) in seen:
            continue
        seen.add(hash(lrc))
        item = {k: v for k, v in m.items() if k != "_fetch"}
        item["lrc"], item["path"] = lrc, ""
        cands.append(item)

    cands.sort(key=lambda c: -c["score"])
    cands = cands[:14]
    for c in cands:
        c["score"] = round(c["score"], 3)
    sys.stdout.write(json.dumps({"candidates": cands, "net_errors": NET_ERRORS[0]}))


try:
    main()
except Exception as e:
    sys.stdout.write(json.dumps({"candidates": [], "error": str(e)}))
