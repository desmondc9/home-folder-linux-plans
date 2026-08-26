import json

cfg = json.load(open('dr-config-clean.json'))

# Sites confirmed to auto-switch with the OS color scheme (pass 1 flip test + pass 2 dark-boot test)
CONFIRMED = [
    "github.com",
    "claude.ai",
    "kimi.com",
    "cursor.com",
    "cloudflare.com",
    "google.com",
    "youtube.com",
    "x.com",
    "okx.com",
    "v.qq.com",
    "__ADULT_SITE_REDACTED__",
]

# Rebuild the 4 built-in cssFilter customThemes (Office/SharePoint/Docs/OneDrive)
FILTER_SITES = ["*.officeapps.live.com", "*.sharepoint.com", "docs.google.com", "onedrive.live.com"]
ct = cfg.get('customThemes')
base_theme = ct['theme'] if isinstance(ct, dict) and 'theme' in ct else None
if base_theme is None:
    raise SystemExit('cannot recover customThemes base theme')
cfg['customThemes'] = [{"builtIn": True, "theme": dict(base_theme), "url": [u]} for u in FILTER_SITES]

existing = cfg.get('disabledFor') or []
merged = sorted(set(existing) | set(CONFIRMED))
cfg['disabledFor'] = merged

json.dump(cfg, open('Dark-Reader-Settings.json', 'w'), ensure_ascii=False, indent=4)
print('disabledFor (%d):' % len(merged))
for s in merged:
    print('  -', s)
print()
print('other fields preserved: enabled=%s automation=%s syncSettings=%s' % (cfg['enabled'], cfg['automation'], cfg['syncSettings']))
print('customThemes entries:', len(cfg['customThemes']))
print('total fields:', len(cfg))
