#!/usr/bin/env python3
"""Sign nested Mach-O code, XPC services, helpers, framework, then host app."""
import os, subprocess, sys
from pathlib import Path
app, identity = Path(sys.argv[1]), sys.argv[2]
flags = ['--force', '--sign', identity]
if identity != '-': flags += ['--options', 'runtime', '--timestamp']
def sign(path): subprocess.run(['codesign', *flags, str(path)], check=True)
framework = app/'Contents/Frameworks/Sparkle.framework'
for path in sorted(framework.rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink(): continue
    if path.is_file() and 'Mach-O' in subprocess.check_output(['file', '-b', str(path)], text=True): sign(path)
    elif path.suffix in ('.xpc', '.app') and path.is_dir(): sign(path)
sign(framework)
sign(app)
