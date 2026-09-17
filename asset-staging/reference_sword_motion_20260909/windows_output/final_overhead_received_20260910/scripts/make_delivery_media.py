"""Encode only the actual rendered 60fps frames; produce final review stills."""
from pathlib import Path
import av,json,hashlib,sys
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
FOLDER=ROOT/'output'/sys.argv[1];FRAMES=FOLDER/'delivery_frames';OUT=FOLDER/'final_media';OUT.mkdir(exist_ok=True)
KEYS=[0,2,4,7,34,38,40,42,43,44,46,49,70,78,85,93]
REF=ROOT.parent/'reference_sword_motion_20260909/reference_original_01'
reference=json.loads((REF/'reference_extraction.json').read_text())
videos=[]
for filename,repetitions in [('Overhead_Final_60fps.mp4',1),('Overhead_Final_Loop_60fps.mp4',3)]:
    target=OUT/filename
    with av.open(str(target),'w',options={'movflags':'+faststart'}) as output:
        st=output.add_stream('libx264',rate=60);st.width=1280;st.height=720;st.pix_fmt='yuv420p';st.options={'crf':'17','preset':'slow'}
        for repeat in range(repetitions):
            for frame in range(93):
                with Image.open(FRAMES/f'{frame:03d}.png') as im:
                    for pkt in st.encode(av.VideoFrame.from_image(im.convert('RGB'))):output.mux(pkt)
        for pkt in st.encode():output.mux(pkt)
    with av.open(str(target)) as inp:
        stream=inp.streams.video[0];count=sum(1 for _ in inp.decode(stream));duration=float(stream.duration*stream.time_base)
    assert count==93*repetitions and abs(duration-1.55*repetitions)<1e-7
    videos.append({'file':filename,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'width':1280,'height':720,'fps':60,'decoded_frames':count,'duration_seconds':duration,'repetitions':repetitions})
sheet=Image.new('RGB',(1280,202*8),(17,21,26));draw=ImageDraw.Draw(sheet)
for i,frame in enumerate(KEYS):
    x=(i%2)*640;y=(i//2)*202
    src=REF/next(r['file'] for r in reference['frames'] if r['source_frame_index']==1040+frame)
    for off,path,label in [(0,src,f'SOURCE  {(1040+frame)/60:.3f}s'),(320,FRAMES/f'{frame:03d}.png',f'FINAL  {frame/60:.3f}s')]:
        with Image.open(path) as im:sheet.paste(im.resize((320,180)),(x+off,y+22))
        draw.text((x+off+6,y+5),label,fill='white')
sheet.save(OUT/'Source_vs_Final.webp',quality=84,method=6)
side=Image.new('RGB',(1440,292*2),(17,21,26));draw=ImageDraw.Draw(side)
for i,sample in enumerate([8,80,84,86,91,92]):
    x=(i%3)*480;y=(i//3)*292
    with Image.open(FOLDER/'finish_side'/f'{sample:03d}.png') as im:side.paste(im.resize((480,270)),(x,y+22))
    draw.text((x+6,y+5),f'SURFACE  {sample/120:.6f}s'+(' | MAXIMUM ELBOW BEND' if sample==91 else ''),fill='white')
side.save(OUT/'Finished_Arm_Surface.webp',quality=88,method=6)
for frame in [0,42,43,78,93]:
    with Image.open(FRAMES/f'{frame:03d}.png') as im:im.save(OUT/f'Pose_{frame:03d}.png')
(OUT/'media_verification.json').write_text(json.dumps({'status':'PASS','videos':videos,'all_media_from_actual_blender_render':True,'source_clip_seconds':1.55,'frames_include_endpoint':94,'mp4_excludes_duplicate_endpoint':True},indent=2),encoding='utf-8')
print(json.dumps(videos,indent=2))
