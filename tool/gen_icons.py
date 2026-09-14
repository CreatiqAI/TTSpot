"""Generate lib/core/theme/app_icons.dart from Phosphor's CSS codepoints.
Run from anywhere: python tool/gen_icons.py (needs internet)."""
import io, os, re, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSS_URL = "https://unpkg.com/@phosphor-icons/web/src/regular/style.css"
css = urllib.request.urlopen(CSS_URL, timeout=30).read().decode("utf-8")
cp = {}
for m in re.finditer(r"\.ph\.ph-([a-z0-9-]+):before\s*\{\s*content:\s*\"\\([0-9a-fA-F]+)\"", css):
    cp[m.group(1)] = int(m.group(2), 16)
print("codepoints", len(cp))

# Phosphor names the app uses. Dart name = camelCase of the phosphor name.
REGULAR = """
x arrow-left arrow-right camera camera-plus trash flag flag-checkered flag-banner caret-right caret-down caret-left map-pin
images image image-broken car garage prohibit magnifying-glass plus plus-circle gps-fix crosshair navigation-arrow heart
chat-circle chat-circle-dots chats calendar-blank calendar-check bookmark-simple shield shield-check eye eye-slash paper-plane-tilt
user user-plus user-minus user-check users users-three dots-three-vertical dots-three pencil-simple note-pencil check-circle
check x-circle wifi-slash sliders-horizontal funnel clock path broadcast bell bell-ringing list sign-out clock-counter-clockwise
squares-four trophy map-trifold ghost coffee fire sparkle hand-waving share-network gear warning info question lock
arrows-clockwise medal star confetti seal-check megaphone steering-wheel wrench gauge road-horizon compass timer hourglass
users-four handshake smiley thumbs-up phone envelope link qr-code export download-simple house globe rocket lightning
chat-teardrop chat-text record pulse target binoculars footprints signpost map-pin-plus map-pin-area storefront buildings
fork-knife gas-pump tire traffic-cone police-car siren list-checks caret-up arrow-up arrow-down minus hash tag scan
chart-bar ticket receipt gift percent coins hand-coins wallet shopping-bag crown map-pin-line share-fat arrows-out corners-out
""".split()

FILL = """
map-trifold flag-checkered chat-circle user heart bookmark-simple check-circle map-pin paper-plane-tilt bell eye eye-slash
star camera calendar-blank house users car trophy ghost fire shield
""".split()


def dart_name(n):
    parts = n.split("-")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


missing = [n for n in REGULAR + FILL if n not in cp]
assert not missing, missing

out = io.StringIO()
out.write("""// GENERATED from Phosphor Icons (MIT, https://phosphoricons.com). Regular weight
// for everything, Fill weight for selected / active states. Do not edit by hand;
// re-run tool/gen_icons.py if you need more glyphs.
import 'package:flutter/widgets.dart';

/// The app's icon set. Use like `Icon(AppIcons.mapTrifold)`; selected states
/// use the `...Fill` twin.
abstract final class AppIcons {
  static const _family = 'Phosphor';
  static const _fill = 'PhosphorFill';

""")
for n in REGULAR:
    out.write(f"  static const IconData {dart_name(n)} = IconData(0x{cp[n]:x}, fontFamily: _family);\n")
out.write("\n  // ---- filled twins ----\n")
for n in FILL:
    out.write(f"  static const IconData {dart_name(n)}Fill = IconData(0x{cp[n]:x}, fontFamily: _fill);\n")
out.write("}\n")

dest = os.path.join(ROOT, "lib", "core", "theme", "app_icons.dart")
io.open(dest, "w", encoding="utf-8", newline="\n").write(out.getvalue())
print("wrote", dest, len(REGULAR), "regular,", len(FILL), "fill")
