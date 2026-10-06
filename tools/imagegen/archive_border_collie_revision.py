#!/usr/bin/env python3
"""Replace a reviewed selected photo byte-for-byte while preserving its receipt/source."""
import argparse, hashlib, json, os, shutil
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('base',type=Path);p.add_argument('candidate',type=Path);a=p.parse_args()
base=a.base.resolve();r=json.loads(a.candidate.read_text());n=r['frame']
receipt=base/'generation'/f'frame{n:03d}.json';previous=json.loads(receipt.read_text())
target=base/r['selected_image'];source=Path(r['default_image_path'])
assert target.resolve()==base/'export'/'frames'/f'Frame_{n:03d}.png'
assert hashlib.sha256(target.read_bytes()).hexdigest()==previous['sha256']
with Image.open(source) as img: img.verify()
with Image.open(source) as img: assert img.size==(1536,1024)
sha=hashlib.sha256(source.read_bytes()).hexdigest();assert sha!=previous['sha256']
history=base/'generation'/'attempts'/f'frame{n:03d}-replaced-{previous["sha256"][:12]}.json'
history.parent.mkdir(parents=True,exist_ok=True);history.write_text(json.dumps(previous,ensure_ascii=False,indent=2)+'\n')
r.update({'resolution':[1536,1024],'sha256':sha,'bytes':source.stat().st_size,'previous_selected_receipt':str(history.relative_to(base))})
temp=target.with_suffix('.replacement.png');shutil.copyfile(source,temp)
assert hashlib.sha256(temp.read_bytes()).hexdigest()==sha
os.replace(temp,target);receipt.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'frame':n,'sha256':sha,'source_preserved':True,'previous_receipt':str(history.relative_to(base))}))
