"""Export the corrected Labrador and manifest care clips for mouse preview."""
import argparse
import json
import struct
import sys
from pathlib import Path

import bpy


def export(base):
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Animations.blend'))
    rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    manifest=json.loads((base/'export/animation-manifest.json').read_text())
    rig.animation_data.action=None
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    for clip in manifest['clips']:
        action=bpy.data.actions[clip['name']]
        track=rig.animation_data.nla_tracks.new();track.name=clip['name']
        strip=track.strips.new(clip['name'],1,action)
        strip.action_slot=action.slots[0];strip.extrapolation='NOTHING';strip.blend_type='REPLACE'
        strip.frame_end=clip['frames'][1];track.mute=True
    if mesh.data.shape_keys:
        mesh.data.shape_keys.animation_data_clear()
        for key in mesh.data.shape_keys.key_blocks:key.value=0
    bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=max(c['frames'][1] for c in manifest['clips'])
    for o in bpy.context.scene.objects:o.select_set(False)
    for o in [rig,*rig.children_recursive]:o.select_set(True)
    output=base/'export/LabradorPet_Petting.glb'
    bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,
                              export_animations=True,export_animation_mode='NLA_TRACKS',
                              export_anim_slide_to_zero=True,
                              export_force_sampling=True,export_frame_step=1,
                              export_morph=True,export_morph_animation=False,
                              export_vertex_color='ACTIVE',export_all_vertex_colors=False,
                              export_yup=True,export_image_format='AUTO',export_cameras=False,
                              export_lights=False,export_extras=True)
    binary=output.read_bytes();json_length,json_kind=struct.unpack_from('<II',binary,12)
    if json_kind!=0x4e4f534a:raise RuntimeError('Missing GLB JSON')
    data=json.loads(binary[20:20+json_length])
    animation_names=[item.get('name') for item in data.get('animations',[])]
    expected=[clip['name'] for clip in manifest['clips']]
    if sorted(animation_names)!=sorted(expected):raise RuntimeError(f'Unexpected GLB animations: {animation_names}')
    timings={}
    for item in data['animations']:
        inputs=[data['accessors'][sampler['input']] for sampler in item['samplers']]
        start=min(accessor['min'][0] for accessor in inputs);end=max(accessor['max'][0] for accessor in inputs)
        spec=next(clip for clip in manifest['clips'] if clip['name']==item['name'])
        if abs(start)>1e-6 or abs(end-spec['duration'])>1e-5:raise RuntimeError(f'Unexpected GLB clip timing: {item["name"]} {start} {end}')
        timings[item['name']]={'start_seconds':start,'duration_seconds':end}
    masks=sum('COLOR_0' in primitive['attributes'] for mesh in data.get('meshes',[]) for primitive in mesh['primitives'])
    targets=[name for mesh in data.get('meshes',[]) for name in mesh.get('extras',{}).get('targetNames',[])]
    if 'target_1' not in targets:raise RuntimeError('Original eyelid morph missing')
    report={'file':str(output.relative_to(base)),'bytes':len(binary),'animations':animation_names,
            'coat_mask_primitives':masks,'morph_targets':targets,'clip_timings':timings,'coordinates':'glTF metres, +Z forward, Y up',
            'material_note':'COLOR_0.r is a scalar runtime coat mask. Disable ordinary vertexColor multiplication in the preview material and read this channel in the custom coat shader.'}
    (base/'gltf-export-summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print('LABRADOR_GLTF_EXPORTED',str(output),len(binary),animation_names,flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);export(args.base.resolve())
