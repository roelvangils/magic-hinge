#!/usr/bin/env python3
"""Encode original PNG renders as WebP; share byte-identical source frames."""
import argparse, hashlib, json, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source',type=Path);p.add_argument('output',type=Path)
p.add_argument('--quality',default='92');p.add_argument('--lossless',action='store_true')
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
m=json.loads((a.source/'sequence.json').read_text());seen={};frames=[]
for name in m['frames']:
    source=a.source/name
    assert source.suffix=='.png', 'Encode from lossless originals, not JPEGs'
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    if digest not in seen:
        target=source.stem+'.webp'
        subprocess.run(['cwebp','-quiet','-m','6','-metadata','icc',*(['-lossless'] if a.lossless else ['-q',a.quality,'-sharp_yuv']),str(source),'-o',str(a.output/target)],check=True)
        seen[digest]=target
    frames.append(seen[digest])
m.update(frames=frames,poster=frames[-1],encoding='WebP lossless' if a.lossless else 'WebP quality '+a.quality)
(a.output/'sequence.json').write_text(json.dumps(m,indent=2)+'\n')
print(f'{len(frames)} steps, {len(seen)} unique images, {sum(p.stat().st_size for p in a.output.glob("*.webp"))/1024**2:.1f} MiB')
