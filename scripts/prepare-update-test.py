#!/usr/bin/env python3
"""Create isolated, signed Sparkle fixtures. Never edits the production app or preferences."""
import argparse, json, plistlib, shutil, subprocess
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root',type=Path,default=Path('build/update-test'))
parser.add_argument('--base-build',type=int,default=100)
parser.add_argument('--notarize',action='store_true')
args=parser.parse_args()
assert args.base_build > 0
r=json.loads(Path('release.json').read_text());root=args.root.resolve()
next_build=args.base_build+1
root.mkdir(parents=True,exist_ok=True)
assert not (root/'installed').exists(), 'Keep existing evidence; use a fresh build/update-test directory.'
for directory,build in [('installed',args.base_build),('candidate',next_build)]:
    app=root/directory/'Magic Hinge.app';shutil.copytree('build/Magic Hinge.app',app,symlinks=True)
    path=app/'Contents/Info.plist';p=plistlib.loads(path.read_bytes())
    p.update(CFBundleIdentifier='be.elevenways.MacBookDuo.UpdateTest',CFBundleVersion=str(build),
             CFBundleShortVersionString=f'2.3.0-test.{build}',SUFeedURL='http://127.0.0.1:8766/appcast.xml')
    path.write_bytes(plistlib.dumps(p))
    subprocess.run(['python3','scripts/sign-bundle.py',str(app),r['signingIdentity']],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    if args.notarize:
        archive=root/f'notarization-{build}.zip'
        subprocess.run(['ditto','-c','-k','--keepParent',str(app),str(archive)],check=True)
        subprocess.run(['python3','scripts/notarize.py',str(archive)],check=True)
        subprocess.run(['xcrun','stapler','staple',str(app)],check=True)
        subprocess.run(['xcrun','stapler','validate',str(app)],check=True)
        subprocess.run(['spctl','--assess','--type','execute','--verbose=2',str(app)],check=True)
served=root/'served';served.mkdir()
archive=served/f'Magic-Hinge-test-{next_build}.zip'
subprocess.run(['ditto','-c','-k','--keepParent',str(root/'candidate/Magic Hinge.app'),str(archive)],check=True)
tool='.build/artifacts/sparkle/Sparkle/bin/sign_update'
sig=subprocess.check_output([tool,'--account',r['sparkleKeyAccount'],'-p',str(archive)],text=True).strip()
subprocess.run([tool,'--account',r['sparkleKeyAccount'],'--verify',str(archive),sig],check=True)
corrupt=served/'corrupt.zip';data=bytearray(archive.read_bytes());data[len(data)//2]^=1;corrupt.write_bytes(data)
result=subprocess.run([tool,'--account',r['sparkleKeyAccount'],'--verify',str(corrupt),sig],capture_output=True,text=True)
assert result.returncode != 0, 'Corrupt archive must not verify'
(root/'signature-test.json').write_text(json.dumps(dict(validArchiveAccepted=True,corruptArchiveRejected=True)))
feed=f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Magic Hinge private update test</title><item><title>Internal update {next_build}</title><sparkle:version>{next_build}</sparkle:version><sparkle:shortVersionString>2.3.0-test.{next_build}</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion><enclosure url="http://127.0.0.1:8766/{archive.name}" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{sig}" /></item></channel></rss>'''
(served/'appcast.xml').write_text(feed)
print('Isolated local update fixtures ready. Production feed remains HTTPS.')
