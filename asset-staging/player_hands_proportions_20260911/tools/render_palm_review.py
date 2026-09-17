import bpy,hashlib,json,sys
from pathlib import Path
from mathutils import Vector,Matrix
folder=Path(sys.argv[sys.argv.index('--')+1]).resolve()
models=[folder/'bilateral_hands_proportions.blend',*folder.glob('*.glb')]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
originals={p:sha(p) for p in models}
bpy.ops.wm.open_mainfile(filepath=str(models[0]))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
def hide_tree(obj):
    obj.hide_render=True
    for child in obj.children:hide_tree(child)
hide_tree(scene.objects['RIGHT_PreviewTranslationOnly'])
center=scene.objects['LEFT_PreviewTranslationOnly'].matrix_world@Vector((0,.075,0))
camera=scene.camera;camera.location=center+Vector((0,0,-1.2))
forward=(center-camera.location).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward)
camera.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();camera.data.ortho_scale=.295
scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.resolution_x=1400;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
path=folder/'hand_palm_upright.png';scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
assert all(sha(p)==h for p,h in originals.items())
(folder/'palm_review.json').write_text(json.dumps({'file':path.name,'sha256':sha(path),'actual_blender_render':True,'model_hashes_unchanged':True,'upright_world_y_camera':True},indent=2))
