#!/usr/bin/env python3
import json, os, plistlib, sys
from pathlib import Path
app, mode = Path(sys.argv[1]), sys.argv[2]
r = json.loads(Path('release.json').read_text())
p = dict(CFBundleIdentifier=r['bundleIdentifier'], CFBundleExecutable='MagicHinge',
         CFBundleName='Magic Hinge', CFBundleDisplayName='Magic Hinge', CFBundleDevelopmentRegion='en',
         CFBundleLocalizations=['en','nl'], CFBundlePackageType='APPL', CFBundleIconFile='Magic Hinge', CFBundleIconName='Magic Hinge',
         CFBundleShortVersionString=r['version'], MagicHingeDisplayVersion=r.get('displayVersion',r['version']), CFBundleVersion=str(r['build']),
         LSMinimumSystemVersion=r['minimumSystemVersion'], LSArchitecturePriority=['arm64'],
         NSHighResolutionCapable=True,
         NSScreenCaptureUsageDescription='Magic Hinge uses a temporary screen capture to animate your desktop. Images stay in memory on your Mac.',
         SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
         SUEnableSystemProfiling=False)
# A DSN is a public ingestion address, never a Sentry auth token.
dsn = os.environ.get('SENTRY_DSN', r.get('sentryDsn', '')).strip()
if dsn:
    from urllib.parse import urlparse
    url = urlparse(dsn)
    assert url.scheme == 'https' and url.hostname and url.username and not url.password
    assert url.path.rstrip('/').split('/')[-1].isdigit() and not url.query and not url.fragment
    p.update(SentryDSN=dsn, SentryEnvironment='production' if mode == 'distribution' else 'development')
if mode == 'distribution':
    p.update(SUFeedURL=r['website']+'appcast.xml', SUPublicEDKey=r['sparklePublicKey'])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
