"""Auth settings that the app relies on (Supabase Management API).

Run after changing the email templates or when setting up a fresh project:
    python tool/auth_config.py

- Sign-up must be confirmed with a 6-digit code emailed to the member
  (mailer_autoconfirm off, OTP length 6, 15 minutes).
- Manual identity linking on, so Settings can link/unlink Google.
- Confirmation email shows the code ({{ .Token }}) instead of a link.
"""
import io, json, urllib.request

TOKEN = io.open(r"C:\Users\Admin\.supabase\car-meet-access-token.txt").read().strip()
REF = "gsoaoabefjavdaiqhahu"
LOGO = "https://creatiqai.github.io/TTSpot/logo.png"


def code_mail(title, intro, footer):
    return f"""<!doctype html><html><body style="margin:0;padding:0;background:#F5F5F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F5F7;padding:32px 12px;">
<tr><td align="center">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:480px;background:#ffffff;border-radius:20px;padding:36px 32px;text-align:center;">
<tr><td align="center"><img src="{LOGO}" width="120" alt="TT Spot" style="display:block;margin:0 auto 18px;"></td></tr>
<tr><td style="font-size:22px;font-weight:800;color:#0F1115;padding-bottom:8px;">{title}</td></tr>
<tr><td style="font-size:15px;line-height:1.55;color:#5c5c5c;padding-bottom:24px;">{intro}</td></tr>
<tr><td align="center" style="padding-bottom:22px;">
<div style="display:inline-block;background:#0F1115;color:#ffffff;font-weight:800;font-size:34px;letter-spacing:10px;padding:16px 28px 16px 38px;border-radius:14px;font-family:'SF Mono',Menlo,Consolas,monospace;">{{{{ .Token }}}}</div>
</td></tr>
<tr><td style="font-size:13px;line-height:1.5;color:#8a8a8a;">{footer}</td></tr>
</table>
<div style="font-size:12px;color:#9a9a9a;padding-top:18px;">TT Spot · Malaysia's car meet spot · Questions? ttspotmy@gmail.com</div>
</td></tr></table></body></html>"""


confirmation = code_mail(
    "Your TT Spot code",
    "Type this code in the app to confirm your email. It expires in 15 minutes.",
    "If you didn't sign up for TT Spot, you can ignore this email.",
)
email_change = code_mail(
    "Confirm your new email",
    "You asked to change the email on your TT Spot account. Type this code in the app to confirm.",
    "If you didn't ask for this, secure your account by changing your password.",
)

body = {
    "mailer_autoconfirm": False,
    "mailer_otp_length": 6,
    "mailer_otp_exp": 900,
    "security_manual_linking_enabled": True,
    "mailer_subjects_confirmation": "Your TT Spot code",
    "mailer_templates_confirmation_content": confirmation,
    "mailer_subjects_email_change": "Confirm your new TT Spot email",
    "mailer_templates_email_change_content": email_change,
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
