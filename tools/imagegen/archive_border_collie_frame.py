#!/usr/bin/env python3
"""Archive a selected built-in imagegen output byte-for-byte, never edit pixels."""
import argparse, hashlib, json, shutil
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser(); p.add_argument('receipt',type=Path); a=p.parse_args()
r=json.loads(a.receipt.read_text(encoding='utf-8')); base=a.receipt.parent.parent
source=Path(r['default_image_path']); target=base/r['selected_image']
target.parent.mkdir(parents=True,exist_ok=True)
if target.exists() and target.read_bytes()!=source.read_bytes():
    raise SystemExit('Refusing to replace an accepted frame')
shutil.copyfile(source,target)
with Image.open(target) as image:
    image.verify()
with Image.open(target) as image:
    r['resolution']=list(image.size)
r['sha256']=hashlib.sha256(target.read_bytes()).hexdigest(); r['bytes']=target.stat().st_size
assert r['sha256']==hashlib.sha256(source.read_bytes()).hexdigest()
a.receipt.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'frame':r['frame'],'bytes':r['bytes'],'resolution':r['resolution'],'sha256':r['sha256']}))

