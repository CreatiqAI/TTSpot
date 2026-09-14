"""Download the latest successful iOS build from GitHub Actions into build/ios-artifact/
with a proper name, and add a row to CHANGELOG.md if that build isn't listed yet.

    python tool/fetch_ipa.py            # latest successful run of ios.yml
    python tool/fetch_ipa.py <run-id>   # a specific run

Needs the GitHub CLI (`gh`) logged in. The workflow names the file
TTSpot-<version>.ipa; the date and commit go into CHANGELOG.md, not the file name.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "ios-artifact"
CHANGELOG = ROOT / "CHANGELOG.md"


def gh(*args):
    return subprocess.run(["gh", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def main():
    if len(sys.argv) > 1:
        run_id = sys.argv[1]
    else:
        runs = json.loads(gh("run", "list", "--workflow=ios.yml", "--limit", "10",
                             "--json", "databaseId,conclusion,status,headSha"))
        ok = [r for r in runs if r["conclusion"] == "success"]
        if not ok:
            sys.exit("No successful iOS run yet. Check GitHub → Actions.")
        run_id = str(ok[0]["databaseId"])
    run = json.loads(gh("run", "view", run_id, "--json", "headSha,createdAt"))
    sha = run["headSha"][:7]
    date = run["createdAt"][:10]

    tmp = OUT / "tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    OUT.mkdir(parents=True, exist_ok=True)
    gh("run", "download", run_id, "-n", "TTSpot-ios-unsigned", "-D", str(tmp))
    ipas = list(tmp.rglob("*.ipa"))
    if not ipas:
        sys.exit("Run downloaded but no .ipa inside.")
    src = ipas[0]
    dest = OUT / src.name
    if dest.exists():
        dest.unlink()
    shutil.move(str(src), dest)
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"Saved: {dest}")

    m = re.match(r"TTSpot-(?P<ver>[\d.]+)\.ipa", dest.name)
    if not m:
        return
    ver = m["ver"]
    text = CHANGELOG.read_text(encoding="utf-8")
    if sha in text:
        return
    pretty = date
    subject = subprocess.run(["git", "log", "-1", "--format=%s", sha], cwd=ROOT,
                             capture_output=True, text=True).stdout.strip() or "(see git log)"
    # Replace a "_next build_" placeholder for this version, else insert a new row.
    placeholder = f"| {ver} | "
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith(placeholder) and "_next build_" in line:
            lines[i] = line.replace("_next build_", sha)
            break
    else:
        header = next(i for i, l in enumerate(lines) if l.startswith("|---"))
        lines.insert(header + 1, f"| {ver} | {pretty} | {sha} | {subject} |")
    CHANGELOG.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"CHANGELOG.md updated for {ver} ({sha}).")


if __name__ == "__main__":
    main()
