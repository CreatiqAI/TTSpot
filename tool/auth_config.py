"""Auth settings that the app relies on (Supabase Management API).

Run after changing the email templates or when setting up a fresh project:
    python tool/auth_config.py

- Sign-up must be confirmed with a 6-digit code emailed to the member
  (mailer_autoconfirm off, OTP length 6, 15 minutes).
- Manual identity linking on, so Settings can link/unlink Google.
- Confirmation email shows the code ({{ .Token }}) instead of a link.
"""
import io, json, os, sys, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Until Resend can deliver to everyone (ttspot.my verified), sign-up skips the
# email code: `python tool/auth_config.py --no-verify`. Later: `--verify`.
VERIFY = "--no-verify" not in sys.argv

TOKEN = io.open(r"C:\Users\Admin\.supabase\car-meet-access-token.txt").read().strip()
REF = "gsoaoabefjavdaiqhahu"
from email_templates import TEMPLATES  # same design for every auth email

body = {
    "mailer_autoconfirm": not VERIFY,
    "mailer_otp_length": 6,
    "mailer_otp_exp": 900,
    "security_manual_linking_enabled": True,
    "mailer_subjects_confirmation": TEMPLATES["confirmation"][0],
    "mailer_templates_confirmation_content": TEMPLATES["confirmation"][1],
    "mailer_subjects_email_change": TEMPLATES["email_change"][0],
    "mailer_templates_email_change_content": TEMPLATES["email_change"][1],
}
req = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{REF}/config/auth",
    data=json.dumps(body).encode(),
    method="PATCH",
    headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
)
with urllib.request.urlopen(req) as r:
    d = json.load(r)
for k in ("mailer_autoconfirm", "mailer_otp_length", "mailer_otp_exp", "security_manual_linking_enabled", "mailer_subjects_confirmation"):
    print(k, "=", d.get(k))
