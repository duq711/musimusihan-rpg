import av
from PIL import Image, ImageDraw
from pathlib import Path

root = Path(__file__).resolve().parent
video = root / 'sU7jk2OQlgc.mp4'
# Decode actual frames sequentially, once, to avoid inaccurate packet seeks.
times = sorted(set([float(i) for i in range(54)]))
frames = {}
with av.open(str(video)) as container:
    for frame in container.decode(video=0):
        t = float(frame.time)
        while times and t >= times[0] - 0.009:
            target = times.pop(0)
            frames[target] = frame.to_image().convert('RGB')
        if not times:
            break
for sheet_i in range(3):
    subset = list(frames.items())[sheet_i * 18:(sheet_i + 1) * 18]
    w, h = 384, 216
    canvas = Image.new('RGB', (w * 3, (h + 25) * 6), '#202020')
    draw = ImageDraw.Draw(canvas)
    for idx, (t, img) in enumerate(subset):
        x, y = (idx % 3) * w, (idx // 3) * (h + 25)
        canvas.paste(img.resize((w, h)), (x, y + 25))
        draw.text((x + 8, y + 5), f'{t:.2f}s', fill='white')
    canvas.save(root / f'overview_{sheet_i + 1:02d}.jpg', quality=90)
print('Wrote sheets', len(frames))

# Detailed intervals for locomotion and attacks. Labels use real decoded timestamps.
groups = {
    'locomotion_06_14': (6, 14, 4),
    'jump_14_17': (14, 17.5, 6),
    'attack_17_21': (17.5, 21, 8),
    'attack_21_25': (21, 25, 8),
    'attack_25_29': (25, 29, 8),
    'attack_29_33': (29, 33.5, 8),
    'guard_33_35': (33.5, 35.5, 6),
}
targets = sorted(set(round(start + i / fps, 5) for start,end,fps in groups.values() for i in range(round((end-start)*fps)+1)))
captured = {}
with av.open(str(video)) as container:
    for frame in container.decode(video=0):
        t = float(frame.time)
        while targets and t >= targets[0] - 0.009:
            target = targets.pop(0)
            captured[target] = frame.to_image().convert('RGB')
        if not targets: break
for name,(start,end,fps) in groups.items():
    keys = [round(start+i/fps,5) for i in range(round((end-start)*fps)+1)]
    for sheet_i in range((len(keys)+17)//18):
        subset = keys[sheet_i*18:(sheet_i+1)*18]
        w,h=480,270
        canvas=Image.new('RGB',(w*3,(h+25)*((len(subset)+2)//3)),'#202020')
        draw=ImageDraw.Draw(canvas)
        for idx,t in enumerate(subset):
            x,y=(idx%3)*w,(idx//3)*(h+25)
            canvas.paste(captured[t].resize((w,h)),(x,y+25))
            draw.text((x+8,y+5),f'{t:.3f}s',fill='white')
        canvas.save(root/f'{name}_{sheet_i+1:02d}.jpg',quality=92)
print('Wrote detailed groups')
