# TT Spot builds

One line per build that went to a phone. Newest first. Bump `version:` in `pubspec.yaml`
before every push you intend to install (`0.2.0+2` → `0.2.1+3`: the part before `+` is the
file name, the number after `+` must only go up). The version shows in iPhone Settings → TT Spot.

Files are simply `TTSpot-<version>.ipa` / `.apk`, kept in `build/ios-artifact/` (not committed).
`python tool/fetch_ipa.py` downloads the latest green GitHub build there and adds the row below.

| Version | Date | Commit | What changed |
|---|---|---|---|
| 0.2.1 | 2026-09-15 | _next build_ | iPhone-style wheel for meet date/time; @handle moved to the left on the Me tab with a moments hint; Chats gets a friends row (green dot = on the map) and a Say hi list for friends you haven't messaged. |
| 0.2.0 | 2026-09-15 | 8885da2 | TT now one field; Places search in Spots; meet visibility (friends / everyone) + trimmed form; friend suggestions; profile Posts · Garage · Saved with moments row; account switcher (personal / club / partner); club admins; post as club. |
| 0.1.1 | 2026-09-15 | 3f2a5eb | Same features as 0.2.0, built before versioning started (shows as 0.1.0 on the phone). |
| 0.1.0 | 2026-09-14 | dc65ba9 | Profile v3 (centered identity, car circles, sticky tabs, showroom garage); Rewards + vouchers merged. |
