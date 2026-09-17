"""Fill only untouched atlas background; preserve all authored texels and GLB geometry bytes."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess

import numpy as np
from PIL import Image


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_glb(path):
    blob=path.read_bytes();length,kind=struct.unpack_from('<II',blob,12)
    assert kind==0x4e4f534a
    document=json.loads(blob[20:20+length]);binary=blob[28+length:]
    return document,binary


def replace_images(source,target,pngs,valid):
    document,binary=read_glb(source)
    source_json=json.dumps(document,sort_keys=True)
    replacements={}
    content_checks={}
    for image in document['images']:
        index=image['bufferView'];view=document['bufferViews'][index]
        original=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        name=image['name'];old=np.asarray(Image.open(io.BytesIO(original)).convert('RGB'))
        mode=next(m for m in pngs if name.endswith(m))
        new=np.asarray(Image.open(pngs[mode]).convert('RGB')).copy()
        if mode=='roughness':
            # Blender exporter packs roughness into G; keep its other channels exact.
            packed=old.copy();packed[:,:,1]=new[:,:,1];new=packed
            stream=io.BytesIO();Image.fromarray(new).save(stream,format='PNG',compress_level=6)
            replacement=stream.getvalue()
        else: replacement=pngs[mode].read_bytes()
        assert np.array_equal(old[valid],new[valid]),name+' authored texels changed'
        replacements[index]=replacement
        content_checks[name]={'authored_pixels_exact':True,'old_sha256':sha(original),'new_sha256':sha(replacement)}
    out=bytearray();unchanged={}
    for index,view in enumerate(document['bufferViews']):
        old=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        payload=replacements.get(index,old)
        while len(out)%4:out.append(0)
        view['byteOffset']=len(out);view['byteLength']=len(payload)
        out.extend(payload)
        if index not in replacements:unchanged[str(index)]=sha(old)
    document['buffers'][0]['byteLength']=len(out)
    encoded=json.dumps(document,separators=(',',':'),ensure_ascii=False).encode()
    encoded+=b' '*((-len(encoded))%4);out+=b'\0'*((-len(out))%4)
    total=12+8+len(encoded)+8+len(out)
    target.write_bytes(struct.pack('<III',0x46546c67,2,total)+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(out),0x004e4942)+out)
    check,checkbinary=read_glb(target)
    for index,digest in unchanged.items():
        v=check['bufferViews'][int(index)]
        assert sha(checkbinary[v['byteOffset']:v['byteOffset']+v['byteLength']])==digest
    source_doc=json.loads(source_json)
    for key in source_doc:
        if key not in ('bufferViews','buffers'):assert source_doc[key]==check[key],key+' JSON changed'
    return {'source_sha256':sha(source.read_bytes()),'output_sha256':sha(target.read_bytes()),
            'nonimage_buffer_views_exact':len(unchanged),'nonimage_sha256':unchanged,
            'scene_mesh_accessors_materials_textures_json_exact':True,'images':content_checks}


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args();source=args.input_dir.resolve();output=args.output_dir.resolve()
assert not output.exists() or not any(output.iterdir()),'Output must be new or empty.'
output.mkdir(parents=True,exist_ok=True)
diagnostics=output/'padding_diagnostics';diagnostics.mkdir()
modes=('basecolor','normal','roughness')
paths={mode:source/('realistic_hands_'+mode+'.png') for mode in modes}
arrays={mode:np.asarray(Image.open(path).convert('RGB')).copy() for mode,path in paths.items()}
valid=arrays['basecolor'].max(2)>0
assert np.array_equal(valid,arrays['roughness'].max(2)>0)
height,width=valid.shape
(diagnostics/'seed_mask.u8').write_bytes(valid.astype('u1').tobytes())
Image.fromarray(valid.astype('uint8')*255).save(diagnostics/'authored_seed_mask.png')
executable=diagnostics/'atlas_nearest_seed'
subprocess.run(['/usr/bin/clang++','-O3','-std=c++17',str(Path(__file__).with_name('atlas_nearest_seed.cpp')),'-o',str(executable)],check=True)
fieldpath=diagnostics/'nearest_seed.u32'
subprocess.run([str(executable),str(width),str(height),str(diagnostics/'seed_mask.u8'),str(fieldpath)],check=True)
field=np.fromfile(fieldpath,dtype='<u4').reshape(height,width)
assert valid.reshape(-1)[field].all()
assert np.array_equal(field[valid],np.arange(width*height,dtype='uint32').reshape(height,width)[valid])
report={'status':'padded_textures_glb_ready','method':'Exact Euclidean nearest authored pixel; fill only original black BaseColor/Roughness background. Whole atlas covered, no valid-pixel averaging or blur.',
        'resolution':[width,height],'authored_pixels':int(valid.sum()),'filled_pixels':int((~valid).sum()),
        'minimum_background_padding':'Entire available blank region, partitioned at nearest-island boundaries.',
        'limitations':'Adjacent UV islands can still mix at very coarse mip levels. Actual game-distance renderer review is required.',
        'textures':{},'glb':{}}
pngs={}
for mode,old in arrays.items():
    new=old.reshape(-1,3)[field].copy()
    assert np.array_equal(old[valid],new[valid])
    destination=output/paths[mode].name;Image.fromarray(new).save(destination,compress_level=6);pngs[mode]=destination
    report['textures'][mode]={'source_sha256':sha(paths[mode].read_bytes()),'output_sha256':sha(destination.read_bytes()),
                             'authored_pixels_exact':True,'changed_authored_pixels':0,
                             'changed_background_pixels':int(np.any(old!=new,axis=2).sum()),
                             'minimum_rgb':new.reshape(-1,3).min(0).tolist(),'maximum_rgb':new.reshape(-1,3).max(0).tolist()}
    if mode in ('basecolor','roughness'):assert (new.max(2)>0).all()
for side in ('left','right'):
    name=side+'_hand_realistic.glb'
    report['glb'][side]=replace_images(source/name,output/name,pngs,valid)
(output/'atlas_padding_report.json').write_text(json.dumps(report,indent=2))
print('REALISM_PADDED_TEXTURES_GLB_READY',flush=True)
