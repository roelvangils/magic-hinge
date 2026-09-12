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
        for key in ['src','href']:
            value=a.get(key,'')
            if value and not value.startswith(('https://','#')):
                assert (root/value).is_file(), value
Check().feed((root/'index.html').read_text())
assert 'lang="en"' in (root/'index.html').read_text()
if args.release:
    r=json.loads((root/'release.json').read_text())
    canonical=json.loads(Path('release.json').read_text())
    assert r['version']==canonical['version'] and r['build']==canonical['build']
    item=ET.parse(root/'appcast.xml').find('channel/item');enclosure=item.find('enclosure')
    assert enclosure.attrib['url']==r['url'] and int(enclosure.attrib['length'])==r['length']
    assert enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']==r['signature']
    assert len(r['sha256'])==64
print('Website assets and metadata verified'+(' for release.' if args.release else '.'))
