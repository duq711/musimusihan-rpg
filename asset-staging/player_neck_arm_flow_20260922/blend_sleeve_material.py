"""Bake upper-sleeve textile blending without interpolating UV coordinates.

Call after geometry deformation, with the ORIGINAL world-space positions and
unmodified UVMap: bake_sleeve_material(obj, original_world_positions, out_dir).
Only upper matched-cloth faces receive a new ordinary glTF PBR material. The
original UVMap, lower sleeve, skin materials, vertices and normals stay intact.
"""
from pathlib import Path
import math
import bpy
import bmesh


SOURCE_MATERIAL = 'Gravebound_Matched_Sleeve_Cloth'
DEST_UV = 'SleeveBlendBake'
PLANAR_UV = 'SleevePlanarSource'


def bake_sleeve_material(obj, original_world_positions, output_dir,
                         resolution=2048, start_z=1.18, end_z=1.285):
    """Bake per-surface-point albedo crossfade; return a JSON-safe report.

    Source cloth uses metalness zero, roughness .9 and a weak tangent normal.
    The two source normals are evaluated in their own UV tangent frames,
    blended as surface normals, then rebaked into the destination UV frame.
    """
    mesh = obj.data
    assert len(original_world_positions) == len(mesh.vertices)
    source_slot = next(i for i, m in enumerate(mesh.materials)
                       if m and m.name == SOURCE_MATERIAL)
    source = mesh.materials[source_slot]
    bsdf = next(n for n in source.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    assert not bsdf.inputs['Roughness'].is_linked
    assert not bsdf.inputs['Metallic'].is_linked
    base_link = bsdf.inputs['Base Color'].links[0]
    assert base_link.from_node.type == 'TEX_IMAGE'
    source_image = base_link.from_node.image
    normal_node = bsdf.inputs['Normal'].links[0].from_node
    assert normal_node.type == 'NORMAL_MAP' and normal_node.space == 'TANGENT'
    normal_source = normal_node.inputs['Color'].links[0].from_node
    assert normal_source.type == 'TEX_IMAGE'
    normal_image = normal_source.image
    normal_strength = normal_node.inputs['Strength'].default_value
    original_uv = mesh.uv_layers.active
    source_uv_name = original_uv.name
    original_uv_values = [tuple(d.uv) for d in original_uv.data]
    original_material_indices = [f.material_index for f in mesh.polygons]
    upper_faces = [f.index for f in mesh.polygons
                   if f.material_index == source_slot
                   and max(original_world_positions[i].z for i in f.vertices) > start_z]
    assert upper_faces, obj.name
    selected_faces = set(upper_faces)

    if mesh.uv_layers.get(DEST_UV) or mesh.uv_layers.get(PLANAR_UV):
        raise ValueError('Apply textile bake only once to a fresh source mesh')
    destination = mesh.uv_layers.new(name=DEST_UV, do_init=True)
    planar = mesh.uv_layers.new(name=PLANAR_UV, do_init=True)
    for li, loop in enumerate(mesh.loops):
        p = original_world_positions[loop.vertex_index]
        authored_x = p.x - math.copysign(.018, p.x)
        planar.data[li].uv = (.32 + authored_x * .65,
                              .12 + (p.z - .98) * .5 + p.y * .3)

    # Unwrap the actual upper faces into an independent, non-overlapping atlas.
    # This changes only the new destination layer, never UVMap or the geometry.
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mesh.uv_layers.active_index = mesh.uv_layers.find(DEST_UV)
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    for vertex in mesh.vertices:
        vertex.select = False
    for edge in mesh.edges:
        edge.select = False
    for face in mesh.polygons:
        face.select = face.index in selected_faces
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=.012)
    bpy.ops.object.mode_set(mode='OBJECT')
    assert original_uv_values == [tuple(d.uv) for d in mesh.uv_layers[source_uv_name].data]

    side = 'L' if '_L_' in obj.name else 'R'
    image_name = 'Gravebound_Sleeve_Blend_' + side
    image = bpy.data.images.new(image_name, width=resolution, height=resolution,
                                alpha=False, float_buffer=False)
    image.colorspace_settings.name = 'sRGB'
    image.generated_color = (.02, .02, .02, 1)
    baked_normal = bpy.data.images.new(image_name + '_Normal', width=resolution,
                                       height=resolution, alpha=False, float_buffer=False)
    baked_normal.colorspace_settings.name = 'Non-Color'
    baked_normal.generated_color = (.5, .5, 1, 1)

    # Bake on an isolated temporary copy. Lower material nodes are untouched,
    # and no lower sleeve face can accidentally be baked or reassigned.
    temp_mesh = mesh.copy()
    bm = bmesh.new(); bm.from_mesh(temp_mesh)
    bm.faces.ensure_lookup_table()
    remove = [f for f in bm.faces if f.index not in selected_faces]
    bmesh.ops.delete(bm, geom=remove, context='FACES')
    bm.to_mesh(temp_mesh); bm.free()
    temp = bpy.data.objects.new('SleeveBlendBakeTemporary_' + side, temp_mesh)
    bpy.context.scene.collection.objects.link(temp)
    temp.matrix_world = obj.matrix_world.copy()
    emitter = bpy.data.materials.new('SleeveBlendBakeEmitter_' + side)
    emitter.use_nodes = True
    nt = emitter.node_tree; nt.nodes.clear()
    output = nt.nodes.new('ShaderNodeOutputMaterial')
    emission = nt.nodes.new('ShaderNodeEmission')
    mix = nt.nodes.new('ShaderNodeMixRGB'); mix.blend_type = 'MIX'
    old_uv = nt.nodes.new('ShaderNodeUVMap'); old_uv.uv_map = source_uv_name
    new_uv = nt.nodes.new('ShaderNodeUVMap'); new_uv.uv_map = PLANAR_UV
    old_tex = nt.nodes.new('ShaderNodeTexImage'); old_tex.image = source_image
    new_tex = nt.nodes.new('ShaderNodeTexImage'); new_tex.image = source_image
    geom = nt.nodes.new('ShaderNodeNewGeometry')
    separate = nt.nodes.new('ShaderNodeSeparateXYZ')
    factor = nt.nodes.new('ShaderNodeMapRange')
    factor.interpolation_type = 'SMOOTHSTEP'; factor.clamp = True
    factor.inputs['From Min'].default_value = start_z
    factor.inputs['From Max'].default_value = end_z
    target = nt.nodes.new('ShaderNodeTexImage'); target.image = image
    nt.nodes.active = target; target.select = True
    nt.links.new(old_uv.outputs['UV'], old_tex.inputs['Vector'])
    nt.links.new(new_uv.outputs['UV'], new_tex.inputs['Vector'])
    nt.links.new(geom.outputs['Position'], separate.inputs[0])
    nt.links.new(separate.outputs['Z'], factor.inputs['Value'])
    nt.links.new(factor.outputs[0], mix.inputs[0])
    nt.links.new(old_tex.outputs['Color'], mix.inputs[1])
    nt.links.new(new_tex.outputs['Color'], mix.inputs[2])
    nt.links.new(mix.outputs[0], emission.inputs['Color'])
    nt.links.new(emission.outputs[0], output.inputs['Surface'])
    temp_mesh.materials.clear(); temp_mesh.materials.append(emitter)
    for f in temp_mesh.polygons:
        f.material_index = 0
    temp_mesh.uv_layers.active_index = temp_mesh.uv_layers.find(DEST_UV)
    temp_mesh.uv_layers[DEST_UV].active_render = True
    bpy.ops.object.select_all(action='DESELECT'); temp.select_set(True)
    bpy.context.view_layer.objects.active = temp
    scene = bpy.context.scene
    old_engine = scene.render.engine
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 1
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 16
    scene.render.bake.use_clear = True
    try:
        bpy.ops.object.bake(type='EMIT')
        # Evaluate normals in ORIGINAL/PLANAR source tangent frames, then let
        # Cycles bake their blend into the independent destination UV frame.
        normal_a = nt.nodes.new('ShaderNodeNormalMap'); normal_a.uv_map = source_uv_name
        normal_b = nt.nodes.new('ShaderNodeNormalMap'); normal_b.uv_map = PLANAR_UV
        normal_a.inputs['Strength'].default_value = normal_strength
        normal_b.inputs['Strength'].default_value = normal_strength
        tex_a = nt.nodes.new('ShaderNodeTexImage'); tex_a.image = normal_image
        tex_b = nt.nodes.new('ShaderNodeTexImage'); tex_b.image = normal_image
        normal_mix = nt.nodes.new('ShaderNodeMixRGB'); normal_mix.blend_type = 'MIX'
        normalize = nt.nodes.new('ShaderNodeVectorMath'); normalize.operation = 'NORMALIZE'
        bake_bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        nt.links.new(old_uv.outputs['UV'], tex_a.inputs['Vector'])
        nt.links.new(new_uv.outputs['UV'], tex_b.inputs['Vector'])
        nt.links.new(tex_a.outputs['Color'], normal_a.inputs['Color'])
        nt.links.new(tex_b.outputs['Color'], normal_b.inputs['Color'])
        nt.links.new(factor.outputs[0], normal_mix.inputs[0])
        nt.links.new(normal_a.outputs['Normal'], normal_mix.inputs[1])
        nt.links.new(normal_b.outputs['Normal'], normal_mix.inputs[2])
        nt.links.new(normal_mix.outputs[0], normalize.inputs[0])
        nt.links.new(normalize.outputs[0], bake_bsdf.inputs['Normal'])
        nt.links.new(bake_bsdf.outputs[0], output.inputs['Surface'])
        target.image = baked_normal; nt.nodes.active = target
        scene.render.bake.normal_space = 'TANGENT'
        scene.render.bake.normal_r = 'POS_X'
        scene.render.bake.normal_g = 'POS_Y'
        scene.render.bake.normal_b = 'POS_Z'
        bpy.ops.object.bake(type='NORMAL')
    finally:
        scene.render.engine = old_engine
        bpy.data.objects.remove(temp, do_unlink=True)
        bpy.data.meshes.remove(temp_mesh)
        bpy.data.materials.remove(emitter)

    output_dir = Path(output_dir); output_dir.mkdir(parents=True, exist_ok=True)
    out = output_dir / (image_name.lower() + '.png')
    image.filepath_raw = str(out); image.file_format = 'PNG'; image.save(); image.pack()
    normal_out = output_dir / (image_name.lower() + '_normal.png')
    baked_normal.filepath_raw = str(normal_out); baked_normal.file_format = 'PNG'
    baked_normal.save(); baked_normal.pack()
    material = bpy.data.materials.new('Gravebound_Sleeve_Flow_' + side)
    material.use_nodes = True
    final_bsdf = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    final_bsdf.inputs['Roughness'].default_value = bsdf.inputs['Roughness'].default_value
    final_bsdf.inputs['Metallic'].default_value = bsdf.inputs['Metallic'].default_value
    uv_node = material.node_tree.nodes.new('ShaderNodeUVMap'); uv_node.uv_map = DEST_UV
    tex = material.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = image
    material.node_tree.links.new(uv_node.outputs['UV'], tex.inputs['Vector'])
    material.node_tree.links.new(tex.outputs['Color'], final_bsdf.inputs['Base Color'])
    final_normal_tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    final_normal_tex.image = baked_normal
    final_normal = material.node_tree.nodes.new('ShaderNodeNormalMap')
    final_normal.uv_map = DEST_UV
    final_normal.inputs['Strength'].default_value = 1.0
    material.node_tree.links.new(uv_node.outputs['UV'], final_normal_tex.inputs['Vector'])
    material.node_tree.links.new(final_normal_tex.outputs['Color'], final_normal.inputs['Color'])
    material.node_tree.links.new(final_normal.outputs['Normal'], final_bsdf.inputs['Normal'])
    index = len(mesh.materials); mesh.materials.append(material)
    for face in mesh.polygons:
        if face.index in selected_faces:
            face.material_index = index
        else:
            assert face.material_index == original_material_indices[face.index]
    # Blender 5.2 glTF export calls mesh.calc_tangents() with no UV argument
    # (primitive_extract.py:103). Its tangent basis must use the baked atlas.
    # Lower sleeve/skin destination coordinates are an EXACT copy of UVMap,
    # so both their implicit color sampling and tangent frames stay the same.
    for face in mesh.polygons:
        if face.index not in selected_faces:
            for li in face.loop_indices:
                assert tuple(mesh.uv_layers[DEST_UV].data[li].uv) == original_uv_values[li]
    mesh.uv_layers.active_index = mesh.uv_layers.find(DEST_UV)
    mesh.uv_layers[DEST_UV].active_render = True
    mesh.uv_layers.remove(mesh.uv_layers[PLANAR_UV])
    assert original_uv_values == [tuple(d.uv) for d in mesh.uv_layers[source_uv_name].data]
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return {'upper_material': material.name, 'destination_uv': DEST_UV,
            'baked_image': str(out), 'resolution': resolution,
            'baked_normal_image': str(normal_out),
            'new_material_face_count': len(upper_faces),
            'original_uv_exact': True, 'lower_materials_exact': True,
            'lower_destination_uv_exact': True, 'export_tangent_uv': DEST_UV,
            'source_normal_connected': True, 'source_normal_strength': normal_strength,
            'blend_start_z_m': start_z, 'blend_end_z_m': end_z}
