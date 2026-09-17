"""Bake the supplied high-resolution sculpt onto its direct reduced mesh.

No photographed or generated replacement geometry/textures are used. Color is
authored procedurally; actual high-poly relief supplies the tangent normal map.
"""
from pathlib import Path
import bpy,hashlib

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def material(role):
    mat=bpy.data.materials.new('Baking_'+role);mat.use_nodes=True;n=mat.node_tree.nodes;l=mat.node_tree.links;n.clear()
    tex=n.new('ShaderNodeTexCoord');noise=n.new('ShaderNodeTexNoise');l.new(tex.outputs['Object'],noise.inputs['Vector']);noise.inputs['Scale'].default_value=75;noise.inputs['Detail'].default_value=3
    mix=n.new('ShaderNodeMixRGB');l.new(noise.outputs['Fac'],mix.inputs[0])
    if role=='Supplied_Skin':
        mix.inputs[1].default_value=(.235,.126,.078,1);mix.inputs[2].default_value=(.315,.181,.119,1)
    else:mix.inputs[1].default_value=(.29,.172,.140,1);mix.inputs[2].default_value=(.38,.254,.217,1)
    grain=n.new('ShaderNodeTexNoise');l.new(tex.outputs['Object'],grain.inputs['Vector']);grain.inputs['Scale'].default_value=2200;grain.inputs['Detail'].default_value=2
    mult=n.new('ShaderNodeMath');mult.operation='MULTIPLY';l.new(grain.outputs['Fac'],mult.inputs[0]);mult.inputs[1].default_value=.14 if role=='Supplied_Skin' else .07
    rough=n.new('ShaderNodeMath');rough.operation='ADD';l.new(mult.outputs[0],rough.inputs[0]);rough.inputs[1].default_value=.48 if role=='Supplied_Skin' else .29
    bsdf=n.new('ShaderNodeBsdfPrincipled');l.new(mix.outputs[0],bsdf.inputs['Base Color']);l.new(rough.outputs[0],bsdf.inputs['Roughness']);bsdf.inputs['Specular IOR Level'].default_value=.3
    out=n.new('ShaderNodeOutputMaterial');l.new(bsdf.outputs[0],out.inputs['Surface']);em=n.new('ShaderNodeEmission');target=n.new('ShaderNodeTexImage')
    return {'material':mat,'basecolor':mix.outputs[0],'roughness':rough.outputs[0],'bsdf':bsdf,'out':out,'em':em,'target':target}

def bake_supplied(scene,low_high_pairs,out,resolution=4096,samples=4):
    """Pairs are (role, low_object, high_object), each object's geometry canonical."""
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=samples
    bpy.context.window.scene=scene
    records={role:material(role) for role in {r for r,lo,hi in low_high_pairs}}
    originals={};visibility={};modifiers={}
    for role,low,high in low_high_pairs:
        originals[low]=list(low.data.materials);originals[high]=list(high.data.materials)
        for obj in [low,high]:
            visibility[obj]=(obj.hide_get(),obj.hide_render,obj.hide_viewport)
            obj.hide_set(False);obj.hide_render=False;obj.hide_viewport=False
            obj.data.materials.clear();obj.data.materials.append(records[role]['material'])
            for p in obj.data.polygons:p.material_index=0;p.use_smooth=True
        modifiers[low]=[(m,m.show_render,m.show_viewport) for m in low.modifiers]
        for m,unused,unused2 in modifiers[low]:m.show_render=False;m.show_viewport=False
    images={};report={'resolution':resolution,'high_to_low_normal_bake':True,'samples':samples,'maps':{},'pairs':[]}
    try:
        for mode in ('basecolor','roughness','normal'):
            image=bpy.data.images.new('Supplied_Bake_'+mode,width=resolution,height=resolution,alpha=True)
            image.generated_color=(.5,.5,1,1) if mode=='normal' else (.21,.12,.07,1) if mode=='basecolor' else (.55,.55,.55,1)
            image.colorspace_settings.name='sRGB' if mode=='basecolor' else 'Non-Color'
            for r in records.values():
                nodes=r['material'].node_tree.nodes;links=r['material'].node_tree.links;r['target'].image=image;nodes.active=r['target']
                for node in nodes:node.select=node==r['target']
                if mode=='normal':links.new(r['bsdf'].outputs[0],r['out'].inputs[0])
                else:links.new(r[mode],r['em'].inputs['Color']);links.new(r['em'].outputs[0],r['out'].inputs[0])
            for role,low,high in low_high_pairs:
                bpy.ops.object.select_all(action='DESELECT');low.select_set(True);bpy.context.view_layer.objects.active=low
                if mode=='normal':high.select_set(True)
                scene.render.bake.use_selected_to_active=mode=='normal';scene.render.bake.normal_space='TANGENT'
                scene.render.bake.cage_extrusion=.001;scene.render.bake.max_ray_distance=.003
                bpy.context.view_layer.update()
                print('SUPPLIED_BAKE',mode,low.name,flush=True)
                bpy.ops.object.bake(type='NORMAL' if mode=='normal' else 'EMIT',use_clear=False,margin=4)
            path=out/('supplied_hand_'+mode+'.png');image.filepath_raw=str(path.resolve());image.file_format='PNG';image.save()
            fresh=bpy.data.images.load(str(path.resolve()),check_existing=False);fresh.colorspace_settings.name=image.colorspace_settings.name;fresh.pack()
            assert hashlib.sha256(fresh.packed_file.data).hexdigest()==sha(path)
            fresh.name='Supplied_Hand_Packed_'+mode;images[mode]=fresh;report['maps'][mode]={'file':path.name,'sha256':sha(path),'packed_bytes_match':True}
            for r in records.values():r['target'].image=None
            bpy.data.images.remove(image)
        final={}
        for role in records:
            mat=bpy.data.materials.get(role) or bpy.data.materials.new(role);mat.use_nodes=True;n=mat.node_tree.nodes;l=mat.node_tree.links;n.clear()
            bsdf=n.new('ShaderNodeBsdfPrincipled');bsdf.inputs['Specular IOR Level'].default_value=.3
            output=n.new('ShaderNodeOutputMaterial');l.new(bsdf.outputs[0],output.inputs[0])
            for mode,img in images.items():
                node=n.new('ShaderNodeTexImage');node.name='Baked_'+mode;node.image=img
                if mode=='normal':
                    normal=n.new('ShaderNodeNormalMap');l.new(node.outputs['Color'],normal.inputs['Color']);l.new(normal.outputs[0],bsdf.inputs['Normal'])
                else:l.new(node.outputs['Color'],bsdf.inputs['Base Color' if mode=='basecolor' else 'Roughness'])
            final[role]=mat
        for role,low,high in low_high_pairs:
            low.data.materials.clear();low.data.materials.append(final[role]);high.data.materials.clear()
            for old in originals[high]:high.data.materials.append(old)
            report['pairs'].append({'role':role,'low':low.name,'high':high.name,'low_vertices':len(low.data.vertices),'high_vertices':len(high.data.vertices)})
    finally:
        for obj,(hide,render,viewport) in visibility.items():obj.hide_set(hide);obj.hide_render=render;obj.hide_viewport=viewport
        for obj,states in modifiers.items():
            for m,render,viewport in states:m.show_render=render;m.show_viewport=viewport
        for r in records.values():
            if r['material'].users==0:bpy.data.materials.remove(r['material'])
    return report
