"""Push branded auth email templates to the Supabase project via the Management API."""
import io, json, urllib.request

TOKEN = io.open(r"C:\Users\Admin\.supabase\car-meet-access-token.txt").read().strip()
REF = "gsoaoabefjavdaiqhahu"
LOGO = "https://creatiqai.github.io/TTSpot/logo.png"


def shell(title, intro, cta, url, footer):
    return f"""<!doctype html><html><body style="margin:0;padding:0;background:#F5F5F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F5F7;padding:32px 12px;">
<tr><td align="center">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:480px;background:#ffffff;border-radius:20px;padding:36px 32px;text-align:center;">
<tr><td align="center"><img src="{LOGO}" width="120" alt="TT Spot" style="display:block;margin:0 auto 18px;"></td></tr>
<tr><td style="font-size:22px;font-weight:800;color:#0F1115;padding-bottom:8px;">{title}</td></tr>
<tr><td style="font-size:15px;line-height:1.55;color:#5c5c5c;padding-bottom:24px;">{intro}</td></tr>
<tr><td align="center" style="padding-bottom:22px;">
<a href="{url}" style="display:inline-block;background:#0F1115;color:#ffffff;text-decoration:none;font-weight:700;font-size:16px;padding:15px 34px;border-radius:14px;">{cta}</a>
</td></tr>
<tr><td style="font-size:13px;line-height:1.5;color:#8a8a8a;">{footer}</td></tr>
</table>
<div style="font-size:12px;color:#9a9a9a;padding-top:18px;">TT Spot · Malaysia's car meet spot</div>
</td></tr></table></body></html>"""


recovery = shell(
    "Reset your password",
    "Someone (hopefully you) asked to reset the password for your TT Spot account. Tap the button and choose a new one. It works on your phone or a computer.",
    "Reset my password",
    "{{ .ConfirmationURL }}",
    "The link works once and expires in 1 hour. If you didn't ask for this, you can ignore this email; your password stays the same.",
)
confirmation = shell(
    "Welcome to TT Spot",
    "Confirm your email and you're in: meets on the map, your crew, check-ins, points and partner rewards.",
    "Confirm my email",
    "{{ .ConfirmationURL }}",
    "If you didn't sign up for TT Spot, you can ignore this email.",
)
magic = shell(
    "Your login link",
    "Tap the button to log in to TT Spot. No password needed.",
    "Log in to TT Spot",
    "{{ .ConfirmationURL }}",
    "The link works once and expires in 1 hour.",
)
email_change = shell(
    "Confirm your new email",
    "You asked to change the email on your TT Spot account to {{ .NewEmail }}. Confirm it below.",
    "Confirm new email",
    "{{ .ConfirmationURL }}",
    "If you didn't ask for this, secure your account by changing your password.",
)

body = {
    "mailer_subjects_recovery": "Reset your TT Spot password",
    "mailer_templates_recovery_content": recovery,
    "mailer_subjects_confirmation": "Confirm your email for TT Spot",
    "mailer_templates_confirmation_content": confirmation,
    "mailer_subjects_magic_link": "Your TT Spot login link",
    "mailer_templates_magic_link_content": magic,
    "mailer_subjects_email_change": "Confirm your new TT Spot email",
    "mailer_templates_email_change_content": email_change,
    "uri_allow_list": "https://creatiqai.github.io/TTSpot/reset.html,ttspot://reset-password,ttspot://login-callback",
    "site_url": "https://creatiqai.github.io/TTSpot",
}
req = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{REF}/config/auth",
    data=json.dumps(body).encode(),
    method="PATCH",
    headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
)
with urllib.request.urlopen(req) as r:
    d = json.load(r)
print("subject:", d.get("mailer_subjects_recovery"))
print("allow list:", d.get("uri_allow_list"))
print("site:", d.get("site_url"))
