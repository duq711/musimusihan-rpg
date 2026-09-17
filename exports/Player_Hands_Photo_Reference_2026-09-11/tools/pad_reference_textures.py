"""Fill only unused atlas pixels before game export; preserve all baked surface pixels."""
import argparse,hashlib,json,subprocess
from pathlib import Path
import numpy as np
from PIL import Image
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();source=a.source;output=a.output;output.mkdir(exist_ok=True,parents=True)
    paths={c:source/f'reference_hands_{c}.png' for c in ('basecolor','normal','roughness')}
    data={c:np.asarray(Image.open(path).convert('RGB')) for c,path in paths.items()}
    # EMIT maps have different sRGB/linear quantization at antialiased edges.
    # Preserve the union of all authored pixels; use stronger interior pixels
    # for distant padding so 1/255 edge samples cannot propagate dark streaks.
    base_valid=data['basecolor'].max(2)>0;rough_valid=data['roughness'].max(2)>0
    valid=base_valid|rough_valid
    seeds=(data['basecolor'].max(2)>8)&(data['roughness'].max(2)>8)
    assert seeds.any() and not (seeds&~valid).any()
    height,width=valid.shape;diag=output/'padding_data';diag.mkdir(exist_ok=True)
    (diag/'seed_mask.u8').write_bytes(seeds.astype('u1').tobytes())
    executable=diag/'nearest_seed';fieldpath=diag/'nearest_seed.u32'
    subprocess.run(['/usr/bin/clang++','-O3','-std=c++17',str(Path(__file__).with_name('atlas_nearest_seed.cpp')),'-o',str(executable)],check=True)
    subprocess.run([str(executable),str(width),str(height),str(diag/'seed_mask.u8'),str(fieldpath)],check=True)
    field=np.fromfile(fieldpath,dtype='<u4').reshape(height,width)
    assert seeds.reshape(-1)[field].all()
    report={'status':'passed','width':width,'height':height,'surface_seed_pixels':int(valid.sum()),'filled_background_pixels':int((~valid).sum()),'maps':{},'nearest_source_seed_pixels':int(seeds.sum()),'quantized_edge_mask_disagreement':int((base_valid^rough_valid).sum()),'method':'Preserve all nonzero base or roughness pixels exactly; fill only unused pixels from nearest jointly nonzero (>8/255) source. No surface smoothing.'}
    for channel,old in data.items():
        new=old.copy();new[~valid]=old.reshape(-1,3)[field[~valid]];assert np.array_equal(old[valid],new[valid])
        path=output/paths[channel].name;Image.fromarray(new).save(path,compress_level=6)
        report['maps'][channel]={'source_sha256':digest(paths[channel]),'output_sha256':digest(path),'all_existing_surface_pixels_exact':True,'changed_existing_surface_pixels':0}
    (output/'atlas_padding_report.json').write_text(json.dumps(report,indent=2));print(json.dumps({'status':'passed','seed_pixels':int(valid.sum()),'filled_pixels':int((~valid).sum())}))
if __name__=='__main__':main()
