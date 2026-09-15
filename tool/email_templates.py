"""Branded auth emails for TT Spot, pushed to Supabase via the Management API.

    python tool/email_templates.py            # push all templates
    python tool/email_templates.py --preview  # also email a sample to ttspotmy@gmail.com

One shell for every email: small logo on white, a title, one line of
context, then either a big 6-digit code on a grey tile or one red button,
and a quiet footer with the contact address. Tables + inline styles so Gmail,
Apple Mail and Outlook all render it the same.
"""
import io, json, sys, urllib.request

TOKEN = io.open(r"C:\Users\Admin\.supabase\car-meet-access-token.txt").read().strip()
REF = "gsoaoabefjavdaiqhahu"
LOGO = "https://creatiqai.github.io/TTSpot/logo.png"
SITE = "https://www.ttspot.my"
CONTACT = "ttspotmy@gmail.com"
RED = "#E00008"
INK = "#101010"

FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"


def shell(title, intro, footer, *, code=False, cta=None, url=None, note=None):
    """White page, one narrow column, one thing to do. No cards, no rules."""
    if code:
        action = f"""
<tr><td align="center" style="padding:30px 0 12px;">
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>
    <td style="background:#f4f4f5;border-radius:14px;padding:18px 26px 18px 38px;">
      <span style="font-family:'SF Mono',Menlo,Consolas,'Courier New',monospace;font-size:36px;line-height:1;font-weight:700;letter-spacing:12px;color:{INK};">{{{{ .Token }}}}</span>
    </td>
  </tr></table>
</td></tr>
<tr><td align="center" style="font-family:{FONT};font-size:13px;color:#8a8a8a;padding-bottom:34px;">{note or 'Expires in 15 minutes.'}</td></tr>"""
    else:
        action = f"""
<tr><td align="center" style="padding:30px 0 12px;">
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>
    <td style="background:{RED};border-radius:999px;">
      <a href="{url}" style="display:inline-block;font-family:{FONT};font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;padding:15px 34px;">{cta}</a>
    </td>
  </tr></table>
</td></tr>
<tr><td align="center" style="font-family:{FONT};font-size:13px;color:#8a8a8a;padding-bottom:34px;">{note or 'Works once. Expires in 1 hour.'}</td></tr>"""

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{title}</title></head>
<body style="margin:0;padding:0;background:#ffffff;">
<div style="display:none;max-height:0;overflow:hidden;color:#ffffff;">{intro}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#ffffff;">
<tr><td align="center" style="padding:44px 24px 40px;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:440px;">
    <tr><td align="center" style="padding-bottom:34px;">
      <img src="{LOGO}" width="88" alt="TT Spot" style="display:block;width:88px;height:auto;border:0;">
    </td></tr>
    <tr><td align="center" style="font-family:{FONT};font-size:24px;line-height:1.2;font-weight:700;color:{INK};letter-spacing:-0.3px;padding-bottom:12px;">{title}</td></tr>
    <tr><td align="center" style="font-family:{FONT};font-size:15px;line-height:1.6;color:#555555;">{intro}</td></tr>
    {action}
    <tr><td align="center" style="font-family:{FONT};font-size:12.5px;line-height:1.6;color:#9a9a9a;padding-bottom:30px;">{footer}</td></tr>
    <tr><td style="border-top:1px solid #ededed;padding-top:18px;font-family:{FONT};font-size:12px;line-height:1.7;color:#a0a0a0;text-align:center;">
      TT Spot &middot; Malaysia&rsquo;s car meet spot<br>
      <a href="mailto:{CONTACT}" style="color:#a0a0a0;text-decoration:none;">{CONTACT}</a>
      &nbsp;&middot;&nbsp; <a href="{SITE}" style="color:#a0a0a0;text-decoration:none;">ttspot.my</a>
      &nbsp;&middot;&nbsp; <a href="{SITE}/privacy.html" style="color:#a0a0a0;text-decoration:none;">Privacy</a>
    </td></tr>
  </table>
</td></tr></table>
</body></html>"""


TEMPLATES = {
    "confirmation": (
        "Your TT Spot code",
        shell(
            "Your TT Spot code",
            "Type this code in the app to confirm your email.",
            "Didn&rsquo;t sign up? Ignore this email. The code is useless without your phone.",
            code=True,
        ),
    ),
    "recovery": (
        "Reset your TT Spot password",
        shell(
            "Reset your password",
            "Tap the button to choose a new password. It works on your phone or a computer.",
            "Didn&rsquo;t ask for this? Ignore this email. Your password stays the same.",
            cta="Reset my password",
            url="{{ .ConfirmationURL }}",
        ),
    ),
    "magic_link": (
        "Your TT Spot login link",
        shell(
            "Your login link",
            "Tap the button to log in. No password needed.",
            "Didn&rsquo;t ask for this? Ignore this email.",
            cta="Log in to TT Spot",
            url="{{ .ConfirmationURL }}",
        ),
    ),
    "email_change": (
        "Confirm your new TT Spot email",
        shell(
            "Confirm your new email",
            "Type this code in the app to move your account to {{ .NewEmail }}.",
            "Didn&rsquo;t ask for this? Change your password to be safe.",
            code=True,
        ),
    ),
}


def push():
    body = {
        "uri_allow_list": "https://creatiqai.github.io/TTSpot/reset.html,ttspot://reset-password,ttspot://login-callback",
        "site_url": "https://creatiqai.github.io/TTSpot",
    }
    for key, (subject, html) in TEMPLATES.items():
        body[f"mailer_subjects_{key}"] = subject
        body[f"mailer_templates_{key}_content"] = html
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/config/auth",
        data=json.dumps(body).encode(),
        method="PATCH",
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:
        d = json.load(r)
    print("pushed:", ", ".join(TEMPLATES))
    print("sender:", d.get("smtp_sender_name"), "<" + str(d.get("smtp_admin_email")) + ">")


def preview(to):
    """Email a sample of the code design (with a fake code) and the button design."""
    key = io.open(r"C:\Users\Admin\.supabase\ttspot-resend-key.txt").read().strip()
    samples = [
        ("[Preview] Your TT Spot code", TEMPLATES["confirmation"][1].replace("{{ .Token }}", "482913")),
        ("[Preview] Reset your TT Spot password", TEMPLATES["recovery"][1].replace("{{ .ConfirmationURL }}", SITE)),
    ]
    for subject, html in samples:
        req = urllib.request.Request(
            "https://api.resend.com/emails",
            data=json.dumps({"from": "TT Spot <noreply@ttspot.my>", "to": [to], "subject": subject, "html": html}).encode(),
            method="POST",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req) as r:
            print("sent preview:", subject, json.load(r).get("id"))


if __name__ == "__main__":
    push()
    if "--preview" in sys.argv:
        preview("ttspotmy@gmail.com")
