"""Render lib/core/legal/legal_text.dart -> docs/privacy.html + docs/terms.html."""
import re, html
import os
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..') + '/'
src = open(R + 'lib/core/legal/legal_text.dart', encoding='utf-8').read()
updated = re.search(r"kLegalUpdated = '([^']+)'", src).group(1)
contact = re.search(r"kLegalContact = '([^']+)'", src).group(1)

def grab(name):
    m = re.search(r"const %s = '''\n?(.*?)''';" % name, src, re.S)
    body = m.group(1)
    body = body.replace('$kLegalContact', contact).replace('$kLegalUpdated', updated).replace(r"\$", "$")
    return body

def render(body):
    out, in_list = [], False
    for line in body.split('\n'):
        line = line.rstrip()
        if line.startswith('- '):
            if not in_list:
                out.append('<ul>'); in_list = True
            out.append('<li>%s</li>' % html.escape(line[2:]))
            continue
        if in_list:
            out.append('</ul>'); in_list = False
        if line.startswith('# '):
            out.append('<h2>%s</h2>' % html.escape(line[2:]))
        elif line.strip():
            out.append('<p>%s</p>' % html.escape(line))
    if in_list:
        out.append('</ul>')
    return '\n'.join(out)

TPL = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · TT Spot</title>
<link rel="icon" href="logo.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@700&family=Inter:wght@400;600&display=swap">
<style>
  :root {{ --brand:#E00008; --ink:#101010; --text:#1c1c1c; --muted:#6b6b6b; --bg:#ffffff; --line:#ececec; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --ink:#ffffff; --text:#e6e6e6; --muted:#9a9a9a; --bg:#101010; --line:#262626; }} }}
  body {{ margin:0; background:var(--bg); color:var(--text); font:16px/1.6 Inter, system-ui, -apple-system, sans-serif; padding-block:0 64px; padding-inline:20px; }}
  header {{ max-width:720px; margin:0 auto; padding:28px 0 8px; display:flex; align-items:center; gap:12px; border-bottom:1px solid var(--line); }}
  header img {{ width:36px; height:36px; border-radius:9px; }}
  header b {{ font-family:'Barlow Condensed', Impact, sans-serif; font-size:24px; letter-spacing:.5px; color:var(--ink); text-transform:uppercase; }}
  main {{ max-width:720px; margin:0 auto; }}
  h1 {{ font-family:'Barlow Condensed', Impact, sans-serif; font-size:44px; line-height:1; margin:36px 0 6px; color:var(--ink); text-transform:uppercase; }}
  .meta {{ color:var(--muted); font-size:13.5px; margin-bottom:28px; }}
  h2 {{ font-size:18px; margin:30px 0 8px; color:var(--ink); }}
  p, li {{ max-width:68ch; }}
  ul {{ padding-left:20px; }}
  a {{ color:var(--brand); }}
  footer {{ max-width:720px; margin:48px auto 0; padding-top:16px; border-top:1px solid var(--line); color:var(--muted); font-size:13px; display:flex; gap:16px; flex-wrap:wrap; }}
</style>
</head>
<body>
<header><img src="logo.png" alt=""><b>TT Spot</b></header>
<main>
<h1>{title}</h1>
<div class="meta">Last updated {updated} · <a href="mailto:{contact}">{contact}</a></div>
{body}
</main>
<footer><a href="privacy.html">Privacy Policy</a><a href="terms.html">Terms of Use</a><a href="index.html">ttspot.my</a></footer>
</body>
</html>
'''
for name, title, fn in [('kPrivacyPolicy', 'Privacy Policy', 'privacy.html'), ('kTerms', 'Terms of Use', 'terms.html')]:
    open(R + 'docs/' + fn, 'w', encoding='utf-8').write(TPL.format(title=title, updated=updated, contact=contact, body=render(grab(name))))
print('ok legal')
