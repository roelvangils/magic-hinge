#!/usr/bin/env python3
import argparse, json, xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--release',action='store_true');args=p.parse_args()
root=Path('website')
class Check(HTMLParser):
    def handle_starttag(self, tag, attributes):
        a=dict(attributes)
        if tag=='img': assert a.get('alt') is not None, a
        for key in ['src','href','data-sequence','data-dark-sequence','data-idle-sequence','data-dark-idle-sequence']:
            value=a.get(key,'')
            if value and not value.startswith(('https://','#')):
                assert (root/value).is_file(), value
Check().feed((root/'index.html').read_text())
for manifest in (root/'assets').glob('*/sequence.json'):
    sequence=json.loads(manifest.read_text())
    assert sequence['schema']==1 and len(sequence['frames'])>=2
    assert sequence['poster'] in sequence['frames']
    for name in sequence['frames']:
        assert Path(name).name==name and (manifest.parent/name).is_file(), name
assert 'lang="en"' in (root/'index.html').read_text()
if args.release:
    r=json.loads((root/'release.json').read_text())
    canonical=json.loads(Path('release.json').read_text())
    assert r['version']==canonical['version'] and r['build']==canonical['build']
    if canonical.get('prerelease'):
        assert r.get('prerelease') is True
        assert r.get('displayVersion')==canonical['displayVersion']
        assert canonical['displayVersion'] in (root/'index.html').read_text()
    item=ET.parse(root/'appcast.xml').find('channel/item');enclosure=item.find('enclosure')
    assert enclosure.attrib['url']==r['url'] and int(enclosure.attrib['length'])==r['length']
    assert enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']==r['signature']
    assert len(r['sha256'])==64
print('Website assets and metadata verified'+(' for release.' if args.release else '.'))
