# TT Spot builds

One line per build that went to a phone. Newest first. The version is `pubspec.yaml`'s
`version:` (`major.minor.patch+build`); bump it before every push you intend to install.
The build number also shows in iPhone Settings → TT Spot, so testers can tell you what they run.

IPA / APK file names: `TTSpot-v<version>-<yyyymmdd>-<commit>-unsigned.ipa`.
Local copies live in `build/ios-artifact/` (not committed). `python tool/fetch_ipa.py` downloads
the latest successful GitHub build into that folder with this name and adds a row below.

| Version | Date | Commit | What changed |
|---|---|---|---|
| 0.2.0+2 | 2026-09-15 | 8885da2 | Versioned builds + changelog. TT now one field; Places search in Spots; meet visibility (friends / everyone) + trimmed form; friend suggestions; profile Posts · Garage · Saved with moments row; account switcher (personal / club / partner); club admins; post as club. |
| 0.1.0+1 | 2026-09-15 | 3f2a5eb | Same features as 0.2.0+2 but built before the version bump (shows as 0.1.0 on the phone). |
| 0.1.0+1 | 2026-09-14 | dc65ba9 | Profile v3 (centered identity, car circles, sticky tabs, showroom garage); Rewards + vouchers merged. |
