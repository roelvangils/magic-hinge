#!/usr/bin/env python3
import json, re, subprocess
from pathlib import Path
def strings(path): return json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)]))
en=strings('Sources/DuoCore/Resources/en.lproj/Localizable.strings')
nl=strings('Sources/DuoCore/Resources/nl.lproj/Localizable.strings')
assert en.keys()==nl.keys()
formats=lambda s: re.findall(r'%(?:\d+\$)?[0-9.]*[df@]',s)
for k in en:
    assert nl[k] and formats(en[k])==formats(nl[k]), k
for file in Path('Sources').rglob('*.swift'):
    for key in re.findall(r'L10n\.(?:text|format)\("((?:[^"\\]|\\.)*)"',file.read_text()):
        key=json.loads('"'+key+'"')
        assert key in en, (file,key)
pf=strings('.build/checkouts/PermissionFlow/Sources/PermissionFlow/Resources/en.lproj/Localizable.strings')
pfnl=strings('resources/PermissionFlow/nl.lproj/Localizable.strings')
assert pf.keys()==pfnl.keys()
for k in pf: assert pfnl[k] and formats(pf[k])==formats(pfnl[k]),k
print(f'English/Dutch: {len(en)} app strings and {len(pf)} PermissionFlow strings verified.')
