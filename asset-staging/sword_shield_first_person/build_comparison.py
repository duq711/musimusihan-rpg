"""Arrange verified, unretouched renderer frames for reference review."""
from pathlib import Path
import sys, json, hashlib, re, math
from PIL import Image

STAGE=Path(__file__).resolve().parent
ROOT=STAGE.parents[1]
iteration=sys.argv[1]
assert re.fullmatch(r'[a-zA-Z0-9_-]+',iteration)
folder=ROOT/'godot-game/artifacts/visual_qa/sword_shield'/iteration
manifest=json.loads((folder/'capture_manifest.json').read_text())
assert manifest['actual_renderer']=='vulkan' and manifest['display_driver']=='embedded'
assert manifest['session_and_cursor_preserved'] and not manifest['failures']
poses=['idle','guard','impact','riposte']
assert [c['pose'] for c in manifest['captures']]==poses
for path,expected in manifest['source_sha256'].items():
    source=ROOT/'godot-game'/path.removeprefix('res://')
    assert hashlib.sha256(source.read_bytes()).hexdigest()==expected, path

grid=Image.new('RGB',(2560,1440))
for index,pose in enumerate(poses):
    pixels=Image.open(folder/(pose+'.png')).convert('RGB')
    assert pixels.size==(1280,720)
    grid.paste(pixels,((index%2)*1280,(index//2)*720))
grid.save(folder/'four_poses.png')
reference=Image.open(STAGE/'reference.png').convert('RGB')
comparison=Image.new('RGB',(1672,1880))
for index,pose in enumerate(poses):
    x=(index%2)*836;y=(index//2)*470
    comparison.paste(reference.crop((x,y,x+836,y+470)),(0,index*470))
    actual=Image.open(folder/(pose+'.png')).convert('RGB').resize((836,470),Image.Resampling.LANCZOS)
    comparison.paste(actual,(836,index*470))
comparison.save(folder/'reference_left_game_right.png')

sequence=manifest['sequence']
if sequence:
    frames=[Image.open(folder/entry['image']).convert('RGB') for entry in sequence]
    assert len(frames)==53 and manifest['sequence_fps']==20
    frames[0].save(folder/'guard_counterattack.png',save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=0,blend=0)
    with Image.open(folder/'guard_counterattack.png') as animation:assert animation.n_frames==53
    contact_sheet=Image.new('RGB',(1920,1080))
    for cell,index in enumerate([0,8,15,24,30,32,34,39,52]):
        contact_sheet.paste(frames[index].resize((640,360),Image.Resampling.LANCZOS),((cell%3)*640,(cell//3)*360))
    contact_sheet.save(folder/'sequence_contact_sheet.png')

reference_tips={'idle':(575,97),'guard':(586,83),'riposte':(250,140)}
measurements={}
for capture in manifest['captures']:
    pose=capture['pose']
    if pose not in reference_tips:continue
    actual=tuple(map(float,re.findall(r'-?[0-9]+\.?[0-9]*',capture['sword_tip'])))
    target=(reference_tips[pose][0]*1280/836,reference_tips[pose][1]*720/470)
    measurements[pose]={'reference_tip_1280x720':target,'rendered_tip':actual,'distance_pixels':math.dist(target,actual)}
record={'iteration':iteration,'composition':'Only unretouched renderer frames; reference on left, game on right. The comparison sheet uniformly resizes game frames to the reference panel size. The four-pose sheet and APNG retain native renderer pixels.','sword_tip_landmarks_only':measurements,'not_a_global_similarity_score':True,'sequence_frames':len(sequence),'reference_sha256':hashlib.sha256((STAGE/'reference.png').read_bytes()).hexdigest()}
(folder/'comparison_record.json').write_text(json.dumps(record,indent=2))
print(json.dumps(record,indent=2))
