#!/usr/bin/env python3
"""Pre-commit audit. Reports paths and rule names, never the potentially sensitive value."""
import re, subprocess
from pathlib import Path
files=set(subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z']).decode().split('\0'))-{''}
rules={
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'GitHub token': rb'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}',
    'personal absolute path': rb'/Users/[A-Za-z][^\s"\']*',
}
failures=[]
for name in sorted(files):
    path=Path(name)
    if not path.is_file():continue
    if path.suffix in ['.p12','.p8','.pem','.dmg','.usdz','.usda'] or name.startswith(('.build/','build/')):
        failures.append((name,'generated or sensitive artifact'));continue
    if path.suffix in ['.jpg','.png','.aiff','.hdr','.icns']: continue
    data=path.read_bytes()
    for rule,pattern in rules.items():
        if re.search(pattern,data):failures.append((name,rule))
if failures:
    for name,rule in failures:print(f'{name}: {rule}')
    raise SystemExit(1)
print(f'Audited {len(files)} source paths: no private keys, token patterns, personal absolute paths or generated releases.')
