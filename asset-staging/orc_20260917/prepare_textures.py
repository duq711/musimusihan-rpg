from pathlib import Path
from PIL import Image, ImageOps
import json, hashlib
src=Path('/Users/duq711gmail.com/Downloads/texture');out=Path('godot-game/assets/3d/enemies/orc');out.mkdir(parents=True,exist_ok=True)
for kind,size in [('ork',2048),('axe',1024)]:
 for name in ['Albedo','Normal','Occlusion','Metallic','gloss','Emission']:
  im=Image.open(src/f'{kind}_{name}.tga').convert('RGB').resize((size,size),Image.Resampling.LANCZOS)
  if name=='gloss':im=ImageOps.invert(im);name='Roughness'
  im.save(out/f'{kind}_{name.lower()}.png')
manifest={}
for folder in ['animation fbx','Base mesh FBX','texture']:
 for p in sorted((src.parent/folder).iterdir()):
  if p.is_file():manifest[f'{folder}/{p.name}']={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
Path('asset-staging/orc_20260917/source_manifest.json').write_text(json.dumps(manifest,indent=2))
