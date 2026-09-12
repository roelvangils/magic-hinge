#!/usr/bin/env python3
import argparse, json, re, xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--release',action='store_true');args=p.parse_args()
root=Path('website')
metadata={}
class Check(HTMLParser):
    def handle_starttag(self, tag, attributes):
        a=dict(attributes)
        if tag=="meta":
            key=a.get("property",a.get("name"))
            if key:
                assert key not in metadata, f"Duplicate metadata: {key}"
                metadata[key]=a.get("content","")
        if tag=='img': assert a.get('alt') is not None, a
        for key in ['src','href','data-sequence','data-dark-sequence','data-idle-sequence','data-dark-idle-sequence']:
            value=a.get(key,'')
            if value and not value.startswith(('https://','#')):
                assert (root/value).is_file(), value
Check().feed((root/'index.html').read_text())
# Social crawlers must get the complete preview without running JavaScript.
base='https://roelvangils.github.io/magic-hinge/'
for key in ['og:type','og:site_name','og:title','og:description','og:url','og:image','og:image:alt']:
    assert metadata.get(key), f'Missing social metadata: {key}'
assert metadata['og:type']=='website' and metadata['og:url']==base
assert metadata['description']==metadata['og:description']==metadata['twitter:description']
assert metadata['twitter:card']=='summary_large_image'
assert metadata['twitter:title']==metadata['og:title']
assert metadata['twitter:image']==metadata['og:image']
assert metadata['twitter:image:alt']==metadata['og:image:alt']
assert metadata['og:image'].startswith(base+'assets/')
social_image=root/metadata['og:image'][len(base):]
data=social_image.read_bytes()
assert data[:8]==b'\x89PNG\r\n\x1a\n' and metadata['og:image:type']=='image/png'
assert int.from_bytes(data[16:20],'big')==int(metadata['og:image:width'])
assert int.from_bytes(data[20:24],'big')==int(metadata['og:image:height'])
for manifest in (root/'assets').glob('*/sequence.json'):
    sequence=json.loads(manifest.read_text())
    assert sequence['schema']==1 and len(sequence['frames'])>=2
    assert sequence['poster'] in sequence['frames']
    for name in sequence['frames']:
        assert Path(name).name==name and (manifest.parent/name).is_file(), name
framing=json.loads((root/'sequence-framing.json').read_text())
for path in re.findall(r'data-(?:dark-)?(?:idle-)?sequence="([^"]+)"',(root/'index.html').read_text()):
    sequence=json.loads((root/path).read_text()); measured=framing[path]
    assert (measured['width'],measured['height']) == (sequence['width'],sequence['height'])
    assert len(measured['bounds']) == len(sequence['frames'])
    assert all(len(b)==2 and 0<=b[0]<b[1]<=1 for b in measured['bounds'])
assert 'lang="en"' in (root/'index.html').read_text()
if args.release:
    r=json.loads((root/'release.json').read_text())
    canonical=json.loads(Path('release.json').read_text())
    assert 'href="'+r['url']+'"' in (root/'index.html').read_text()
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
