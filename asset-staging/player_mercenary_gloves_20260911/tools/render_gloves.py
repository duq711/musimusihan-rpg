"""Render both actual gloves, dorsal and palmar, in two separate PNGs.

Readonly source; transient static copies keep evaluated geometry, UVs, material
slots and custom corner normals. Only translation separates the two gloves.
No source save, image edits or composites. Default output uses actual materials;
--diagnostic-clay replaces only transient copies for explicit geometry diagnosis.
"""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy
from mathutils import Matrix,Vector

def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def descendants(obj):
    return [obj] + [child for item in obj.children for child in descendants(item)]

def vec(value):
    return [float(v) for v in value]

def matrix(value):
    return [vec(row) for row in value]

def json_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()

def source_signature(objects):
    """Verify in-memory source geometry/UV/keys/weights/rig as well as disk bytes."""
    result = {}
    for obj in objects:
        item = {"matrix_world": matrix(obj.matrix_world), "hide_render": obj.hide_render}
        if obj.type == "MESH":
            mesh = obj.data
            item.update(
                vertices=[vec(v.co) for v in mesh.vertices],
                polygons=[list(p.vertices) for p in mesh.polygons],
                weights=[[(g.group, g.weight) for g in v.groups] for v in mesh.vertices],
                uv={layer.name: [vec(loop.uv) for loop in layer.data] for layer in mesh.uv_layers},
                normals=[vec(c.vector) for c in mesh.corner_normals],
                material_slots=[m.name if m else None for m in mesh.materials],
                face_materials=[p.material_index for p in mesh.polygons],
                keys={} if not mesh.shape_keys else {
                    key.name: {"value": key.value, "points": [vec(v.co) for v in key.data]}
                    for key in mesh.shape_keys.key_blocks
                },
            )
        elif obj.type == "ARMATURE":
            item["bones"] = {
                b.name: {"rest": matrix(b.matrix_local), "head": vec(b.head_local),
                         "tail": vec(b.tail_local), "parent": b.parent.name if b.parent else None,
                         "pose": matrix(obj.pose.bones[b.name].matrix_basis)}
                for b in obj.data.bones
            }
        result[obj.name] = json_digest(item)
    return result

def neutral_source(objects, rig):
    identity = Matrix.Identity(4)
    for pose in rig.pose.bones:
        assert max(abs(pose.matrix_basis[r][c] - identity[r][c])
                   for r in range(4) for c in range(4)) < 1e-6, "Source must be neutral"
    for obj in objects:
        if obj.type == "MESH" and obj.data.shape_keys:
            assert all(abs(key.value) < 1e-8 for key in obj.data.shape_keys.key_blocks), "Nonzero source key"

def static_copy(obj, ids, scene, depsgraph, label):
    """Extract selected evaluated faces, preserving each original loop's UV/normal."""
    evaluated = obj.evaluated_get(depsgraph)
    source = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    try:
        assert len(source.vertices) == len(obj.data.vertices), "Topology-changing modifiers need an explicit mapping"
        faces = [source.polygons[i] for i in ids]
        used = sorted({i for face in faces for i in face.vertices})
        remap = {old: new for new, old in enumerate(used)}
        mesh = bpy.data.meshes.new(label + "_Mesh")
        mesh.from_pydata([source.vertices[i].co for i in used], [],
                         [[remap[i] for i in face.vertices] for face in faces])
        for material in source.materials: mesh.materials.append(material)
        original_loops = []
        for new_face, old_face in zip(mesh.polygons, faces):
            new_face.material_index = old_face.material_index
            new_face.use_smooth = old_face.use_smooth
            original_loops.extend(old_face.loop_indices)
        for old_uv in source.uv_layers:
            new_uv = mesh.uv_layers.new(name=old_uv.name)
            for loop, original in zip(new_uv.data, original_loops): loop.uv = old_uv.data[original].uv
        if source.uv_layers.active:
            mesh.uv_layers.active_index = source.uv_layers.active_index
        mesh.update()
        mesh.normals_split_custom_set([source.corner_normals[i].vector for i in original_loops])
        duplicate = bpy.data.objects.new(label, mesh)
        scene.collection.objects.link(duplicate)
        duplicate.matrix_world = obj.matrix_world.copy()
        return duplicate, {"source_object": obj.name, "selected_faces": len(ids),
                           "selected_vertices": len(used), "source_face_ids_sha256": json_digest(ids),
                           "native_evaluated_geometry": True, "UV_and_materials_copied": True}
    finally:
        evaluated.to_mesh_clear()

def new_scene(width, height, samples, threads):
    scene = bpy.data.scenes.new("Individual_Finger_Review_Transient")
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0
    world = bpy.data.worlds.new("Individual_Finger_Charcoal")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.035, 0.035, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
    # A constant visible charcoal background is independent of illumination.
    # These are renderer nodes, not a postprocess or an alteration of materials.
    camera_background = world.node_tree.nodes.new("ShaderNodeBackground")
    camera_background.inputs["Color"].default_value = (0.04, 0.04, 0.04, 1)
    camera_background.inputs["Strength"].default_value = 1
    light_path = world.node_tree.nodes.new("ShaderNodeLightPath")
    mix = world.node_tree.nodes.new("ShaderNodeMixShader")
    world.node_tree.links.new(light_path.outputs["Is Camera Ray"], mix.inputs[0])
    world.node_tree.links.new(world.node_tree.nodes["Background"].outputs[0], mix.inputs[1])
    world.node_tree.links.new(camera_background.outputs[0], mix.inputs[2])
    world.node_tree.links.new(mix.outputs[0], world.node_tree.nodes["World Output"].inputs["Surface"])
    scene.world = world
    return scene

def place_frame(scene, holder, frame):
    camera_data = bpy.data.cameras.new("Individual_Finger_Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = frame["ortho_scale_m"]
    camera_data.clip_start = 0.001
    camera_data.clip_end = 10
    camera = bpy.data.objects.new("Individual_Finger_Camera", camera_data)
    scene.collection.objects.link(camera)
    native = Matrix(frame["rotation_native"]).to_4x4()
    native.translation = Vector(frame["location_native"])
    camera.matrix_world = holder.matrix_world @ native
    scene.camera = camera
    objects = [camera]
    for spec in frame["lights"]:
        data = bpy.data.lights.new(spec["name"], "AREA")
        data.energy = spec["energy_w"]
        data.shape = "DISK"
        data.size = spec["size_m"]
        data.color = spec["color"]
        light = bpy.data.objects.new(spec["name"], data)
        scene.collection.objects.link(light)
        light.location = holder.matrix_world @ Vector(spec["location_native"])
        target = holder.matrix_world @ Vector(spec["target_native"])
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
        objects.append(light)
    return objects

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--output-dir',type=Path,required=True)
    p.add_argument('--width',type=int,default=1200)
    p.add_argument('--height',type=int,default=1000)
    p.add_argument('--samples',type=int,default=16)
    p.add_argument('--threads',type=int,default=2)
    p.add_argument('--views',nargs='+',choices=['dorsal','palmar'],default=['dorsal','palmar'])
    p.add_argument('--diagnostic-clay',action='store_true',help='Transient copies only: constant grey, no image or bump; diagnostic evidence, not final materials')
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert bpy.app.background and min(a.width,a.height,a.samples,a.threads)>0
    source=a.source.resolve();out=a.output_dir.resolve()
    assert source.is_file() and not out.exists()
    original=sha(source);bpy.ops.wm.open_mainfile(filepath=str(source))
    source_scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=source_scene
    source_objects=[];hands={}
    for side in ['left','right']:
        holder=source_scene.objects[side.upper()+'_PreviewTranslationOnly']
        objects=descendants(holder);rig=next(o for o in objects if o.type=='ARMATURE')
        neutral_source(objects,rig);source_objects+=objects
        skin=next(o for o in objects if o.type=='MESH' and 'Anatomical' in o.name)
        native=holder.matrix_world.inverted()@skin.matrix_world
        points=[native@v.co for v in skin.data.vertices]
        bounds={k:[min(pt[j] for pt in points),max(pt[j] for pt in points)] for j,k in enumerate('xyz')}
        hands[side]={'holder':holder,'objects':objects,'bounds':bounds}
    signature=source_signature(source_objects)
    scene=new_scene(a.width,a.height,a.samples,a.threads)
    clay=None
    if a.diagnostic_clay:
        clay=bpy.data.materials.new('Diagnostic_Constant_Grey_Transient')
        clay.use_nodes=True
        bsdf=clay.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value=(.25,.25,.25,1)
        bsdf.inputs['Roughness'].default_value=.6
    deps=bpy.context.evaluated_depsgraph_get()
    widths=[h['bounds']['x'][1]-h['bounds']['x'][0] for h in hands.values()]
    separation=sum(widths)*.25+.018
    display_bounds=[];extractions={}
    for side,h in hands.items():
        xcenter=sum(h['bounds']['x'])*.5
        shift=(-separation if side=='left' else separation)-xcenter
        translation=Matrix.Translation((shift,0,0));to_native=h['holder'].matrix_world.inverted()
        extractions[side]={'native_review_translation_m':[shift,0,0],'meshes':[]}
        for obj in h['objects']:
            if obj.type!='MESH':continue
            dup,evidence=static_copy(obj,list(range(len(obj.data.polygons))),scene,deps,'Review_'+side+'_'+obj.name)
            dup.matrix_world=translation@to_native@obj.matrix_world
            if clay:
                dup.data.materials.clear();dup.data.materials.append(clay)
                for polygon in dup.data.polygons:polygon.material_index=0
            extractions[side]['meshes'].append(evidence)
        display_bounds.append((h['bounds']['x'][0]+shift,h['bounds']['x'][1]+shift,h['bounds']['y'][0]-.036,h['bounds']['y'][1],h['bounds']['z'][0],h['bounds']['z'][1]))
    low=Vector((min(b[0] for b in display_bounds),min(b[2] for b in display_bounds),min(b[4] for b in display_bounds)))
    high=Vector((max(b[1] for b in display_bounds),max(b[3] for b in display_bounds),max(b[5] for b in display_bounds)))
    center=(low+high)*.5
    aspect=a.width/a.height
    # Blender's AUTO sensor fit defines ortho_scale along the larger image axis.
    # Convert the necessary vertical field to that axis for landscape frames.
    height=max((high.y-low.y)*1.08,(high.x-low.x)/aspect*1.10)*max(aspect,1.0)
    identity_holder=bpy.data.objects.new('Review_Display_Identity',None);scene.collection.objects.link(identity_holder)
    out.mkdir(parents=True)
    report={'status':'rendering','source':str(source),'source_sha256':original,'renderer_sha256':sha(__file__),
      'actual_blender_geometry':True,'diagnostic_clay_material_override':a.diagnostic_clay,'render':{'width':a.width,'height':a.height,'samples':a.samples,'threads':a.threads,'engine':'CYCLES','device':'CPU'},
      'scope':'Two whole-glove images, each showing the actual left and right gloves at one angle. Only review display translations; no image compositing.','extractions':extractions,'renders':{}}
    for name,outward in [('gloves_dorsal',Vector((0,0,1))),('gloves_palmar',Vector((0,0,-1)))]:
        if name.removeprefix('gloves_') not in a.views:continue
        up=Vector((0,1,0));right=up.cross(outward)
        frame={'center_native':vec(center),'location_native':vec(center+outward*.8),'rotation_native':matrix(Matrix((right,up,outward)).transposed()),'ortho_scale_m':height,'lights':[]}
        for label,offset,energy,size in [('Key',(-.24,.28,.30),8.0,.32),('Fill',(.30,.035,.22),3.0,.38)]:
            loc=center+right*offset[0]+up*offset[1]+outward*offset[2]
            frame['lights'].append({'name':'Review_'+label,'location_native':vec(loc),'target_native':vec(center),'energy_w':energy,'size_m':size,'color':[1,1,1]})
        transient=place_frame(scene,identity_holder,frame)
        path=out/(name+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True,scene=scene.name)
        report['renders'][name]={'file':path.name,'sha256':sha(path),'frame':frame,'actual_blender_geometry':True}
        for obj in transient:bpy.data.objects.remove(obj,do_unlink=True)
        (out/'render_report.json').write_text(json.dumps(report,indent=2))
    assert source_signature(source_objects)==signature and sha(source)==original
    report.update(status='complete',source_file_unchanged=True,source_datablocks_unchanged=True)
    (out/'render_report.json').write_text(json.dumps(report,indent=2))
    print('BILATERAL_GLOVES_RENDER_COMPLETE',out,flush=True)

if __name__=='__main__':main()
