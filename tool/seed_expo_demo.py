"""Seed the MIAPEX / AICOVE / AIAS 2025 demo floor plan + exhibitors into an event.

    python tool/seed_expo_demo.py <event_id>              # refuses if the event already has levels/exhibitors
    python tool/seed_expo_demo.py <event_id> --replace    # deletes the event's levels + exhibitors first
    python tool/seed_expo_demo.py <event_id> --dry-run    # print the SQL, touch nothing
    python tool/seed_expo_demo.py <event_id> --check      # read-only: event, table columns, storage access

Data comes from design/expo_demo/ (built from docs/Visitor Guide MIAPEX-AICOVE-AIAS2025.PDF1.pdf):
    floorplan.png   page 3 plan, 3600 px wide
    manifest.json   image size + level name
    booths.json     [{code, x, y, w, h}]  box as fractions of the image
    landmarks.json  [{label, kind, x, y}] registration, entrances, stages, first aid, cafes, toilets
    exhibitors.json [{name, booths, country, category, phone, email, website, address}]

What it writes (one transaction, after the image upload):
    event_floor_levels  1 row "Hall A · B · C" -> event-floorplans/<event_id>/miapex-hall-abc.png
    event_floor_pins    one 'booth' pin per booth (label = code, x/y = box centre, w/h = box size)
                        + landmark pins (info / entrance / stage / food / toilet)
    event_exhibitors    one row per exhibitor (sort = list order)
    pins.exhibitor_id   booth pin -> first exhibitor (by sort) whose booths contain the pin label

Uses the Supabase Management API with the token in ~/.supabase/car-meet-access-token.txt.
The image upload needs the service-role key, fetched from the Management API (never printed).
"""
import io, json, os, sys, urllib.error, urllib.request

REF = "gsoaoabefjavdaiqhahu"
API = f"https://api.supabase.com/v1/projects/{REF}"
STORAGE = f"https://{REF}.supabase.co/storage/v1"
BUCKET = "event-floorplans"
UA = "ttspot-seed-expo-demo/1.0"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "design", "expo_demo")
TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".supabase", "car-meet-access-token.txt")

LIMITS = {"name": 120, "category": 60, "country": 40, "phone": 60, "email": 120, "website": 200, "address": 300}
LANDMARK_KINDS = {"info", "entrance", "stage", "food", "toilet"}


# ------------------------------------------------------------------ http
def _req(url, method="GET", body=None, headers=None, raw=False):
    h = {"User-Agent": UA}
    h.update(headers or {})
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    if data is not None and "Content-Type" not in h and "content-type" not in h:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            out = r.read()
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", "replace")
        raise SystemExit(f"HTTP {e.code} on {method} {url.split('?')[0]}: {msg[:800]}")
    return out if raw else (json.loads(out) if out else None)


def token():
    return io.open(TOKEN_FILE, encoding="utf-8").read().strip()


def sql(query):
    return _req(f"{API}/database/query", "POST", {"query": query},
                {"Authorization": f"Bearer {token()}"})


def service_key():
    """Legacy service_role JWT. `?reveal=true` needs the secrets privilege (403 for this
    token), but the plain listing already returns the legacy JWT unmasked."""
    auth = {"Authorization": f"Bearer {token()}", "User-Agent": UA}
    keys = None
    for path in ("/api-keys?reveal=true", "/api-keys"):
        try:
            with urllib.request.urlopen(urllib.request.Request(API + path, headers=auth), timeout=60) as r:
                keys = json.load(r)
            break
        except urllib.error.HTTPError as e:
            if e.code != 403:
                raise SystemExit(f"HTTP {e.code} on GET {path}: {e.read()[:300]!r}")
    k = next((k for k in keys or [] if k.get("name") == "service_role"), None)
    v = (k or {}).get("api_key") or ""
    if v.count(".") != 2 or len(v) < 100:  # masked or missing
        raise SystemExit("Could not read the service_role key from the Management API.")
    return v


def storage_headers(key):
    return {"apikey": key, "Authorization": f"Bearer {key}"}


# ------------------------------------------------------------------ sql helpers
def q(v):
    """SQL literal: NULL, number, or a single-quoted string with quotes doubled."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 6)) if isinstance(v, float) else str(v)
    s = str(v).replace("\x00", "")
    return "'" + s.replace("'", "''") + "'"


def arr(items):
    return "array[" + ",".join(q(i) for i in items) + "]::text[]" if items else "'{}'::text[]"


def clip(v, n):
    if v is None:
        return None
    v = str(v).replace("�", "").strip()
    return v[:n].rstrip() or None


def chunks(xs, n=100):
    for i in range(0, len(xs), n):
        yield xs[i:i + n]


# ------------------------------------------------------------------ data
def load():
    j = lambda f: json.load(io.open(os.path.join(DATA, f), encoding="utf-8"))
    manifest, booths, landmarks, exhibitors = j("manifest.json"), j("booths.json"), j("landmarks.json"), j("exhibitors.json")
    img = os.path.join(DATA, manifest["image"])
    if not os.path.exists(img):
        raise SystemExit(f"Missing {img}")
    for lm in landmarks:
        assert lm["kind"] in LANDMARK_KINDS, lm
    return manifest, booths, landmarks, exhibitors, img


def build_sql(event_id, image_path, manifest, booths, landmarks, exhibitors, replace):
    e = q(event_id)
    out = ["begin;"]
    if replace:
        # pins go with their level (on delete cascade); exhibitor secrets/staff/leads cascade too
        out.append(f"delete from public.event_floor_levels where event_id = {e};")
        out.append(f"delete from public.event_exhibitors where event_id = {e};")
    out.append(
        "insert into public.event_floor_levels (event_id, name, sort, image_path, image_w, image_h) values "
        f"({e}, {q(manifest['level_name'][:24])}, 0, {q(image_path)}, {int(manifest['width'])}, {int(manifest['height'])});")
    level = (f"(select id from public.event_floor_levels where event_id = {e} "
             f"and image_path = {q(image_path)} order by created_at desc limit 1)")

    pins = []
    for b in booths:
        w, h = min(max(b["w"], 1e-4), 1.0), min(max(b["h"], 1e-4), 1.0)
        x = min(max(b["x"] + b["w"] / 2, 0.0), 1.0)
        y = min(max(b["y"] + b["h"] / 2, 0.0), 1.0)
        pins.append(f"('booth', {q(b['code'][:60])}, {q(x)}, {q(y)}, {q(w)}, {q(h)})")
    for lm in landmarks:
        pins.append(f"({q(lm['kind'])}, {q(lm['label'][:60])}, {q(lm['x'])}, {q(lm['y'])}, null, null)")
    for part in chunks(pins):
        out.append("insert into public.event_floor_pins (level_id, kind, label, x, y, w, h)\n"
                   "select l.id, v.kind, v.label, v.x::real, v.y::real, v.w::real, v.h::real\n"
                   f"from {level} l(id),\n(values\n  " + ",\n  ".join(part) + ") as v(kind, label, x, y, w, h);")

    rows = []
    for i, x in enumerate(exhibitors):
        f = {k: clip(x.get(k), n) for k, n in LIMITS.items()}
        if not f["name"]:
            continue
        rows.append(f"({e}, {q(f['name'])}, {arr(x.get('booths') or [])}, {q(f['category'])}, {q(f['country'])}, "
                    f"{q(f['phone'])}, {q(f['email'])}, {q(f['website'])}, {q(f['address'])}, {i})")
    for part in chunks(rows):
        out.append("insert into public.event_exhibitors (event_id, name, booths, category, country, phone, email, website, address, sort) values\n  "
                   + ",\n  ".join(part) + ";")

    out.append(f"""update public.event_floor_pins p set exhibitor_id = (
    select x.id from public.event_exhibitors x
    where x.event_id = {e} and p.label = any(x.booths)
    order by x.sort limit 1)
  where p.level_id in (select id from public.event_floor_levels where event_id = {e}) and p.kind = 'booth';""")
    out.append("commit;")
    return "\n".join(out)


# ------------------------------------------------------------------ checks
def check(event_id):
    ev = sql(f"select id, title from public.events where id = {q(event_id)};")
    if not ev:
        raise SystemExit(f"No event {event_id}")
    print("event:", ev[0].get("title"))
    cols = sql("""select table_name, column_name, data_type from information_schema.columns
                  where table_schema = 'public'
                    and table_name in ('event_floor_levels', 'event_floor_pins', 'event_exhibitors')
                  order by table_name, ordinal_position;""")
    have = {}
    for c in cols:
        have.setdefault(c["table_name"], set()).add(c["column_name"])
    need = {
        "event_floor_levels": {"event_id", "name", "sort", "image_path", "image_w", "image_h"},
        "event_floor_pins": {"level_id", "kind", "label", "x", "y", "w", "h", "exhibitor_id"},
        "event_exhibitors": {"event_id", "name", "booths", "category", "country", "phone", "email", "website", "address", "sort"},
    }
    for t, n in need.items():
        missing = n - have.get(t, set())
        if missing:
            raise SystemExit(f"{t} is missing columns {sorted(missing)} - is migration 0118 applied?")
    print("columns: ok")
    counts = sql(f"""select (select count(*) from public.event_floor_levels where event_id = {q(event_id)}) as levels,
                            (select count(*) from public.event_exhibitors where event_id = {q(event_id)}) as exhibitors;""")[0]
    print("existing:", counts)
    return counts


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if len(args) != 1:
        raise SystemExit(__doc__)
    event_id = args[0]
    replace, dry, only_check = "--replace" in flags, "--dry-run" in flags, "--check" in flags
    manifest, booths, landmarks, exhibitors, img = load()
    image_path = f"{event_id}/miapex-hall-abc.png"
    query = build_sql(event_id, image_path, manifest, booths, landmarks, exhibitors, replace)

    if dry:
        sys.stdout.reconfigure(encoding="utf-8")
        print(query)
        print(f"-- {len(booths)} booth pins, {len(landmarks)} landmark pins, {len(exhibitors)} exhibitors", file=sys.stderr)
        return

    counts = check(event_id)
    key = service_key()
    bucket = _req(f"{STORAGE}/bucket/{BUCKET}", headers=storage_headers(key))
    print("storage bucket:", bucket.get("id"), "public" if bucket.get("public") else "private")
    if only_check:
        return
    if (int(counts["levels"]) or int(counts["exhibitors"])) and not replace:
        raise SystemExit("Event already has floor levels or exhibitors - rerun with --replace to wipe and reseed them.")

    data = io.open(img, "rb").read()
    _req(f"{STORAGE}/object/{BUCKET}/{image_path}", "POST", data,
         {**storage_headers(key), "x-upsert": "true", "content-type": "image/png", "cache-control": "31536000"})
    print(f"uploaded {BUCKET}/{image_path} ({len(data) // 1024} KB)")

    sql(query)
    res = sql(f"""select
        (select count(*) from public.event_floor_pins p join public.event_floor_levels l on l.id = p.level_id
          where l.event_id = {q(event_id)}) as pins,
        (select count(*) from public.event_floor_pins p join public.event_floor_levels l on l.id = p.level_id
          where l.event_id = {q(event_id)} and p.exhibitor_id is not null) as linked_pins,
        (select count(*) from public.event_exhibitors where event_id = {q(event_id)}) as exhibitors;""")[0]
    print("seeded:", res)


if __name__ == "__main__":
    main()
