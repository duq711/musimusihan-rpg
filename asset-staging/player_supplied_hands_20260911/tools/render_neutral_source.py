"""Read-only neutral-lit views of the preserved imported user OBJ."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
root=Path.cwd();stage=root/'asset-staging/player_supplied_hands_20260911';source=stage/'input/source_inspection.blend';report=json.loads((stage/'input/source_inspection.json').read_text());out=stage/'review/neutral';assert not out.exists();out.mkdir()
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();original=sha(source)
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene;center=Vector(report['pca_center']);up=Vector(report['pca_up_axis']);length=report['pca_extent']['length'];scene.render.threads_mode='FIXED';scene.render.threads=2
result={'source_blend':str(source),'source_blend_sha256':original,'actual_user_supplied_geometry':True,'material':'Constant grey for inspection; OBJ has no authored material','renders':{}}
for name,frame in report['renders'].items():
 direction=Vector(frame['view_direction_world']);right=up.cross(direction).normalized();scene.camera.matrix_world=Matrix((right,up,direction)).transposed().to_4x4();scene.camera.location=Vector(frame['camera_location']);scene.camera.data.ortho_scale=frame['ortho_scale'];lights=[]
 for label,offset,power,size in [('Key',(-.7,.7,1),20,.9),('Fill',(.7,.05,.8),7.5,1.2)]:
  data=bpy.data.lights.new('Neutral_'+label,'AREA');data.energy=power*length*length;data.shape='DISK';data.size=size*length
  ob=bpy.data.objects.new(data.name,data);scene.collection.objects.link(ob);ob.location=center+(right*offset[0]+up*offset[1]+direction*offset[2])*length;ob.rotation_euler=(center-ob.location).to_track_quat('-Z','Y').to_euler();lights.append(ob)
 path=out/('source_'+name+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
 result['renders'][name]={'file':str(path.relative_to(stage)),'sha256':sha(path),'view_direction':list(direction),'actual_supplied_geometry':True}
 for ob in lights:bpy.data.objects.remove(ob,do_unlink=True)
assert sha(source)==original;result['source_blend_unchanged']=True;result['status']='complete';(out/'render_report.json').write_text(json.dumps(result,indent=2));print('SUPPLIED_NEUTRAL_VIEWS_COMPLETE')
