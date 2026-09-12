#!/usr/bin/env python3
import json, plistlib, subprocess, sys
from pathlib import Path
app, mode = Path(sys.argv[1]), sys.argv[2]
r = json.loads(Path('release.json').read_text())
p = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert p['CFBundleIdentifier'] == r['bundleIdentifier']
assert p['CFBundleShortVersionString'] == r['version'] and p['CFBundleVersion'] == str(r['build'])
assert p['LSMinimumSystemVersion'] == '14.2'
exe = app/'Contents/MacOS/MagicHinge'
assert subprocess.check_output(['lipo','-archs',str(exe)],text=True).strip() == 'arm64'
load = subprocess.check_output(['otool','-l',str(exe)],text=True)
assert 'minos 14.2' in load and '@executable_path/../Frameworks' in load
assert (app/'Contents/Frameworks/Sparkle.framework/Versions/Current').is_symlink()
for bundle in ['MagicHinge_DuoCore','MagicHinge_DuoGraphics','MagicHinge_DuoSimulation','MagicHinge_MagicHinge','PermissionFlow_PermissionFlow']:
    assert (app/f'Contents/Resources/{bundle}.bundle').is_dir(), bundle
for appearance in ('light','dark'):
    source=Path('Sources/DuoSimulation/Resources/ExampleScreens')/(appearance+'.png')
    copies=list((app/'Contents/Resources/MagicHinge_DuoSimulation.bundle').rglob('ExampleScreens/'+appearance+'.png'))
    assert len(copies)==1 and copies[0].read_bytes()==source.read_bytes(), appearance+' example screenshot'
permission_bundle=app/'Contents/Resources/PermissionFlow_PermissionFlow.bundle'
permission_resources=permission_bundle/'Contents/Resources' if (permission_bundle/'Contents/Resources').is_dir() else permission_bundle
assert (permission_resources/'nl.lproj/Localizable.strings').is_file()
# Check Bundle's real lookup, not merely file existence: SwiftPM has flat and Contents layouts.
subprocess.run(['swift','-e', 'import Foundation; let b=Bundle(path:CommandLine.arguments[1])!; precondition(b.localizations.contains("nl")); let nl=Bundle(path:b.path(forResource:"nl",ofType:"lproj")!)!; precondition(nl.localizedString(forKey:"permission_flow.pane.screen_recording",value:nil,table:nil)=="Schermopname")',str(permission_bundle)],check=True)
for path in app.rglob('*'):
    assert path.name not in ('DuoNight.jpg','DesertWallpaper.jpg') and path.suffix not in ('.usdz','.usda','.p12','.pem'), path
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
if mode == 'distribution':
    signature = subprocess.check_output(['codesign','-dvv',str(app)],stderr=subprocess.STDOUT,text=True)
    assert 'TeamIdentifier='+r['teamID'] in signature and 'runtime' in signature
    requirement = subprocess.check_output(['codesign','-d','-r-',str(app)],stderr=subprocess.STDOUT,text=True)
    assert 'anchor apple generic' in requirement
    assert p['SUPublicEDKey'] == r['sparklePublicKey'] and p['SUFeedURL'].startswith('https://')
print('Bundle architecture, resources, metadata and signatures verified.')
