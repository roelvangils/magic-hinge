#!/usr/bin/env python3
"""Download original Apple USDZ test fixtures (not redistributed in the app)."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

root = Path(__file__).resolve().parents[1]
assets = json.loads((root / 'Sources/DuoSimulation/Resources/AppleModels.json').read_text())
destination = root / 'build/apple-models'
destination.mkdir(parents=True, exist_ok=True)

def fetch(record):
    target = destination / record['url'].rsplit('/', 1)[1]
    data = target.read_bytes() if target.exists() else urllib.request.urlopen(record['url'], timeout=60).read()
    if hashlib.sha256(data).hexdigest() != record['sha256']:
        raise ValueError(f'Apple asset changed: {target.name}; inspect its geometry before updating the manifest')
    target.write_bytes(data)
    return target.name

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for name in pool.map(fetch, assets):
        print(name)
