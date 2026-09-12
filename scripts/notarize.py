#!/usr/bin/env python3
"""Submit and retain Apple's status/log. Credentials are read only from Keychain."""
import argparse, json, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('file',type=Path);p.add_argument('--profile',default='magic-hinge');args=p.parse_args()
evidence=Path('build/notarization');evidence.mkdir(parents=True,exist_ok=True)
result=subprocess.run(['xcrun','notarytool','submit',str(args.file),'--keychain-profile',args.profile,'--wait','--output-format','json'],capture_output=True,text=True)
if not result.stdout.strip(): raise SystemExit(result.stderr)
status=json.loads(result.stdout)
submission=status.get('id')
(evidence/(args.file.name+'.json')).write_text(json.dumps(status,indent=2))
if submission:
    subprocess.run(['xcrun','notarytool','log',submission,'--keychain-profile',args.profile,str(evidence/(submission+'.json'))],check=True)
if result.returncode or status.get('status') != 'Accepted':
    raise SystemExit('Notarization rejected or incomplete. See build/notarization; artifact must not be published.')
print('Accepted:',submission)
