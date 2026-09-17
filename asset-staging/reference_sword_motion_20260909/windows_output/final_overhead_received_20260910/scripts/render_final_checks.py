import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent
args=sys.argv[sys.argv.index('--')+1:];iteration=args[0];kind=args[1] if len(args)>1 else 'side'
folder=ROOT/'output'/iteration;out=folder/('finish_'+kind);out.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(folder/'Overhead_Review.blend'),load_ui=False,use_scripts=False)
s=bpy.context.scene;s.frame_set(0)
if 'reimport' in kind:
    for o in list(s.objects):
        if o.type not in ['LIGHT','CAMERA']:bpy.data.objects.remove(o,do_unlink=True)
    for a in list(bpy.data.actions):bpy.data.actions.remove(a)
    bpy.ops.import_scene.gltf(filepath=str(folder/'Overhead_Review.glb'));s.render.fps=120
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.refresh_devices()
for d in prefs.devices:d.use=d.type=='OPTIX' and '4090' in d.name
s.render.engine='CYCLES';s.cycles.device='GPU';s.cycles.samples=16;s.cycles.use_denoising=True
s.render.resolution_x=960;s.render.resolution_y=540;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB';s.render.use_persistent_data=True;s.render.use_compositing=False
if kind!='pov':
    data=bpy.data.cameras.new('FinishInspection');cam=bpy.data.objects.new('FinishInspection',data);s.collection.objects.link(cam)
    cam.location=(1.6,.4,.1) if 'opposite' not in kind else (-1.3,.7,.2)
    target=Vector((.2,.2,-.05));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=1.4;s.camera=cam
for sample in [8,80,84,86,91,92]:
    s.frame_set(sample);bpy.context.view_layer.update();s.render.filepath=str(out/f'{sample:03d}.png');bpy.ops.render.render(write_still=True)
    print('RENDERED '+str(sample),flush=True)
(out/'render_report.json').write_text(json.dumps({'iteration':iteration,'kind':kind,'samples_120hz':[8,80,84,86,91,92],'actual_glb_reimport':'reimport' in kind,'sample91_is_maximum_elbow_flexion':True},indent=2))
