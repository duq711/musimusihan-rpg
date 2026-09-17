import bpy,sys,json,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
iteration=sys.argv[sys.argv.index('--')+1];folder=ROOT/'output'/iteration;out=folder/'delivery_frames';out.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(folder/'Overhead_Review.blend'),load_ui=False,use_scripts=False)
s=bpy.context.scene;prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.refresh_devices()
for d in prefs.devices:d.use=d.type=='OPTIX' and '4090' in d.name
s.render.engine='CYCLES';s.cycles.device='GPU';s.cycles.samples=32;s.cycles.use_denoising=True
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB';s.render.use_persistent_data=True;s.render.use_compositing=False
report={'resolution':[1280,720],'sample_count':32,'engine':'Cycles OptiX RTX4090','frames':[]}
for frame in range(94):
    tick=time.monotonic();s.frame_set(frame*2);bpy.context.view_layer.update();s.render.filepath=str(out/f'{frame:03d}.png');bpy.ops.render.render(write_still=True)
    report['frames'].append({'frame':frame,'time_seconds':frame/60,'file':f'{frame:03d}.png','render_seconds':time.monotonic()-tick});print('FRAME '+str(frame),flush=True)
report['status']='completed';(out/'render_report.json').write_text(json.dumps(report,indent=2))
