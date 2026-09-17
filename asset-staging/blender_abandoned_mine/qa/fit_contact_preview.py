import bpy, sys, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
import surface_contact
report=surface_contact.fix_scene(json.loads((ROOT/'layout.json').read_text()),{})
import geology_materials
geology_materials.apply_continuous_geology()
(ROOT/'qa/surface_contact_preview.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'qa/surface_contact_preview.blend'))
print('SURFACE_CONTACT_PREVIEW_COMPLETE',flush=True)
