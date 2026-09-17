import av
from PIL import Image, ImageDraw
from pathlib import Path
root = Path(__file__).resolve().parent
ranges = {'overhead_dense':(17.3,18.3),'left_right_dense':(19.25,20.15),'right_left_dense':(21.1,22.1),'thrust_dense':(23.1,24.4),'run_dense':(8.0,9.5)}
targets=sorted(set(round(a+i/20,5) for a,b in ranges.values() for i in range(round((b-a)*20)+1)))
captured={}
with av.open(str(root/'sU7jk2OQlgc.mp4')) as c:
    for f in c.decode(video=0):
        while targets and float(f.time)>=targets[0]-.009:
            t=targets.pop(0); captured[t]=f.to_image().convert('RGB')
        if not targets:break
for name,(a,b) in ranges.items():
    ts=[round(a+i/20,5) for i in range(round((b-a)*20)+1)]
    for j in range((len(ts)+23)//24):
        sub=ts[j*24:(j+1)*24]
        w,h=384,216
        out=Image.new('RGB',(w*4,(h+24)*((len(sub)+3)//4)),'#202020');d=ImageDraw.Draw(out)
        for i,t in enumerate(sub):
            x,y=i%4*w,i//4*(h+24)
            out.paste(captured[t].resize((w,h)),(x,y+24));d.text((x+8,y+5),f'{t:.3f}s',fill='white')
        out.save(root/f'{name}_{j+1:02d}.jpg',quality=92)
print('Wrote dense sheets')
