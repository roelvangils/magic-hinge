#!/usr/bin/env python3
import json, plistlib, sys
from pathlib import Path
app, mode = Path(sys.argv[1]), sys.argv[2]
r = json.loads(Path('release.json').read_text())
p = dict(CFBundleIdentifier=r['bundleIdentifier'], CFBundleExecutable='MagicHinge',
         CFBundleName='Magic Hinge', CFBundleDisplayName='Magic Hinge', CFBundleDevelopmentRegion='en',
         CFBundleLocalizations=['en','nl'], CFBundlePackageType='APPL', CFBundleIconFile='AppIcon',
         CFBundleShortVersionString=r['version'], MagicHingeDisplayVersion=r.get('displayVersion',r['version']), CFBundleVersion=str(r['build']),
         LSMinimumSystemVersion=r['minimumSystemVersion'], LSArchitecturePriority=['arm64'],
         NSHighResolutionCapable=True,
         NSScreenCaptureUsageDescription='Magic Hinge uses a temporary screen capture to animate your desktop. Images stay in memory on your Mac.',
         SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
         SUEnableSystemProfiling=False)
if mode == 'distribution':
    p.update(SUFeedURL=r['website']+'appcast.xml', SUPublicEDKey=r['sparklePublicKey'])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
