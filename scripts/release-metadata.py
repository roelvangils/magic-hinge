#!/usr/bin/env python3
"""Generate the website data, cask and appcast from the FINAL stapled download."""
import base64, hashlib, json, subprocess, sys, xml.etree.ElementTree as ET
from pathlib import Path
r=json.loads(Path('release.json').read_text());dmg=Path(sys.argv[1]).resolve()
assert dmg.name == f'Magic-Hinge-{r["version"]}.dmg'
subprocess.run(['xcrun','stapler','validate',str(dmg)],check=True)
tool=Path('.build/artifacts/sparkle/Sparkle/bin/sign_update')
signature=subprocess.check_output([str(tool),'--account',r['sparkleKeyAccount'],'-p',str(dmg)],text=True).strip()
assert len(base64.b64decode(signature,validate=True))==64
subprocess.run([str(tool),'--account',r['sparkleKeyAccount'],'--verify',str(dmg),signature],check=True)
sha=hashlib.sha256(dmg.read_bytes()).hexdigest();url=f'https://github.com/{r["repository"]}/releases/download/v{r["version"]}/{dmg.name}'
(dmg.parent/'SHA256SUMS').write_text(f'{sha}  {dmg.name}\n')
data=dict(displayVersion=r.get('displayVersion',r['version']),prerelease=r.get('prerelease',False),version=r['version'],build=r['build'],minimumSystemVersion=r['minimumSystemVersion'],url=url,sha256=sha,length=dmg.stat().st_size,signature=signature)
(dmg.parent/'release-final.json').write_text(json.dumps(data,indent=2)+'\n')
Path('website/release.json').write_text(json.dumps(data,indent=2)+'\n')
ns='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',ns)
rss=ET.Element('rss',version='2.0');channel=ET.SubElement(rss,'channel')
ET.SubElement(channel,'title').text='Magic Hinge';ET.SubElement(channel,'link').text=r['website']
item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text='Magic Hinge '+r.get('displayVersion',r['version'])
ET.SubElement(item,'{'+ns+'}version').text=str(r['build'])
ET.SubElement(item,'{'+ns+'}shortVersionString').text=r['version']
ET.SubElement(item,'{'+ns+'}minimumSystemVersion').text=r['minimumSystemVersion']
ET.SubElement(item,'enclosure',{'url':url,'length':str(dmg.stat().st_size),'type':'application/octet-stream','{'+ns+'}edSignature':signature})
ET.indent(rss);ET.ElementTree(rss).write('website/appcast.xml',encoding='utf-8',xml_declaration=True)
cask=f'''cask "magic-hinge" do
  version "{r['version']}"
  sha256 "{sha}"

  url "{url}"
  name "Magic Hinge {r.get('displayVersion',r['version'])}"
  desc "A frosted-glass desktop effect controlled by your MacBook hinge"
  homepage "{r['website']}"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"
  # Sonoma 14.0/14.1 are insufficient for SCScreenshotManager.
  preflight do
    if MacOS.version < MacOSVersion.new("14.2")
      odie "Magic Hinge requires macOS 14.2 or later."
    end
  end
  auto_updates true
  app "Magic Hinge.app"
end
'''
(dmg.parent/'magic-hinge.rb').write_text(cask)
print('Final artifact metadata generated:',sha)
