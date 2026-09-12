#!/usr/bin/env python3
"""Install immutable frame URLs and update the website's appearance mapping."""
import argparse, hashlib, json, re, shutil
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source',type=Path)
p.add_argument('--appearance',choices=['light','dark'],required=True)
a=p.parse_args()
manifest=json.loads((a.source/'sequence.json').read_text())
names=['sequence.json',*manifest['frames']]
hash=hashlib.sha256()
for name in names:
    assert Path(name).name==name
    hash.update(name.encode());hash.update((a.source/name).read_bytes())
folder=f'air-front-{a.appearance}-{hash.hexdigest()[:12]}'
destination=Path('website/assets')/folder
if destination.exists():
    assert all((destination/name).read_bytes()==(a.source/name).read_bytes() for name in names)
else:
    shutil.copytree(a.source,destination)
index=Path('website/index.html');html=index.read_text()
attribute='data-sequence' if a.appearance=='light' else 'data-dark-sequence'
match=re.search(attribute+r'="(assets/[^"/]+/sequence.json)"',html)
assert match, 'Missing sequence reference'
old_folder=match[1].rsplit('/',1)[0]
html=html.replace(old_folder+'/',f'assets/{folder}/')
if a.appearance=='light':
    html=re.sub(r'(id="hinge-poster" src=")[^"]+',lambda m:m[1]+f'assets/{folder}/'+manifest['frames'][29],html)
index.write_text(html)
print(f'{a.appearance}: assets/{folder}/sequence.json')
