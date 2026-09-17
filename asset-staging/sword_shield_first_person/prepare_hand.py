import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix
p=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(p/'anatomy_source.blend'))
body=bpy.data.objects['GEO-body_male_realistic']
body.parent=None;body.matrix_world=Matrix.Identity(4)
for mod in body.modifiers:
    if mod.type=='MULTIRES': mod.levels=2;mod.render_levels=2
bpy.context.view_layer.update()
mesh=body.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
wrist=Vector((.375,-.072,.856))
axis_y=Vector((.35,0,-.9367497)).normalized()*math.cos(math.radians(25))+Vector((0,-1,0))*math.sin(math.radians(25))
axis_x=Vector((0,-1,0))*math.cos(math.radians(25))-Vector((.35,0,-.9367497)).normalized()*math.sin(math.radians(25))
axis_z=axis_x.cross(axis_y).normalized()
points=[]
for v in mesh.vertices:
    d=v.co-wrist
    points.append(Vector((d.dot(axis_x),d.dot(axis_y),d.dot(axis_z)))*1.08)
faces=[];used=set()
for face in mesh.polygons:
    ids=list(face.vertices)
    if all(mesh.vertices[i].co.x>.28 and points[i].y>-.045 for i in ids):
        faces.append(ids);used.update(ids)
mapping={old:new for new,old in enumerate(sorted(used))}
data=bpy.data.meshes.new('AnatomicalHandMesh')
data.from_pydata([points[i] for i in sorted(used)],[],[[mapping[i] for i in f] for f in faces]);data.update()
for obj in list(bpy.data.objects): bpy.data.objects.remove(obj,do_unlink=True)
hand=bpy.data.objects.new('AnatomicalHand',data);bpy.context.scene.collection.objects.link(hand)
for f in data.polygons:f.use_smooth=True
bpy.ops.wm.save_as_mainfile(filepath=str(p/'canonical_hand.blend'))
report={'wrist_source':list(wrist),'axis_x':list(axis_x),'axis_y':list(axis_y),'axis_z':list(axis_z),'vertices':len(data.vertices),'triangles':sum(len(f.vertices)-2 for f in data.polygons),'bounds':{'min':[min(v.co[i] for v in data.vertices) for i in range(3)],'max':[max(v.co[i] for v in data.vertices) for i in range(3)]}}
(p/'canonical_hand.json').write_text(json.dumps(report,indent=2))
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH'
scene.world=bpy.data.worlds.new('ProbeWorld');scene.world.color=(.045,.045,.045)
scene.display.shading.light='STUDIO';scene.display.shading.color_type='SINGLE';scene.display.shading.single_color=(.65,.52,.42)
scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH';scene.display.shading.background_type='WORLD'
scene.render.resolution_x=800;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
for label,pos in [('back',(0,.075,.6)),('palm',(0,.075,-.6))]:
    camdata=bpy.data.cameras.new(label);cam=bpy.data.objects.new(label,camdata);scene.collection.objects.link(cam)
    target=Vector((0,.075,0));cam.location=pos;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    camdata.type='ORTHO';camdata.ortho_scale=.29;scene.camera=cam
    scene.render.filepath=str(p/('canonical_hand_'+label+'.png'));bpy.ops.render.render(write_still=True)
