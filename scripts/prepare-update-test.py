#!/usr/bin/env python3
"""Create isolated, signed Sparkle fixtures. Never edits the production app or preferences."""
import json, plistlib, shutil, subprocess
from pathlib import Path
r=json.loads(Path('release.json').read_text());root=Path('build/update-test').resolve()
root.mkdir(parents=True,exist_ok=True)
assert not (root/'installed').exists(), 'Keep existing evidence; use a fresh build/update-test directory.'
for directory,build in [('installed',100),('candidate',101)]:
    app=root/directory/'Magic Hinge.app';shutil.copytree('build/Magic Hinge.app',app,symlinks=True)
    path=app/'Contents/Info.plist';p=plistlib.loads(path.read_bytes())
    p.update(CFBundleIdentifier='be.elevenways.MacBookDuo.UpdateTest',CFBundleVersion=str(build),
             CFBundleShortVersionString=f'2.3.0-test.{build}',SUFeedURL='http://127.0.0.1:8766/appcast.xml')
    path.write_bytes(plistlib.dumps(p))
    subprocess.run(['python3','scripts/sign-bundle.py',str(app),r['signingIdentity']],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
served=root/'served';served.mkdir()
archive=served/'Magic-Hinge-test-101.zip'
subprocess.run(['ditto','-c','-k','--keepParent',str(root/'candidate/Magic Hinge.app'),str(archive)],check=True)
tool='.build/artifacts/sparkle/Sparkle/bin/sign_update'
sig=subprocess.check_output([tool,'--account',r['sparkleKeyAccount'],'-p',str(archive)],text=True).strip()
subprocess.run([tool,'--account',r['sparkleKeyAccount'],'--verify',str(archive),sig],check=True)
corrupt=served/'corrupt.zip';data=bytearray(archive.read_bytes());data[len(data)//2]^=1;corrupt.write_bytes(data)
result=subprocess.run([tool,'--account',r['sparkleKeyAccount'],'--verify',str(corrupt),sig],capture_output=True,text=True)
assert result.returncode != 0, 'Corrupt archive must not verify'
(root/'signature-test.json').write_text(json.dumps(dict(validArchiveAccepted=True,corruptArchiveRejected=True)))
feed=f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Magic Hinge private update test</title><item><title>Internal update 101</title><sparkle:version>101</sparkle:version><sparkle:shortVersionString>2.3.0-test.101</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion><enclosure url="http://127.0.0.1:8766/Magic-Hinge-test-101.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{sig}" /></item></channel></rss>'''
(served/'appcast.xml').write_text(feed)
print('Isolated local update fixtures ready. Production feed remains HTTPS.')
