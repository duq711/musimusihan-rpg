from pathlib import Path
import json,math,hashlib
from zipfile import ZipFile,ZIP_DEFLATED
p=Path(__file__).resolve().parent
# Manual observed 2D pixels: frame,W wrist joint,G blade/guard junction,B visible
# blade endpoints (base->tip),T visible tip,R highest visible shield rim,notes.
groups={
'left_reverse':[
(1156,None,[1008,610],[[993,570],[945,0]],None,[175,577],'Near-neutral lead-in before the leftward load; wrist below crop.'),
(1157,None,[948,610],[[931,560],[884,0]],None,[160,590],'Load begins: sword moving toward center-left; glove lower-right.'),
(1160,[755,716],[614,598],[[602,550],[454,0]],None,[92,683],'Wrist partly at bottom border; forearm enters from bottom-right. Shield dropping.'),
(1162,[438,708],[258,667],[[220,620],[0,325]],None,None,'Wrist partly clipped bottom; arm crosses body from bottom-right to lower-left. Blade exits left.'),
(1191,None,None,None,None,None,'Loaded offscreen; both weapons absent.'),
(1193,[193,612],[9,563],None,None,None,'Crossguard partially clipped left. Forearm stretches across lower screen; proximal arm continues bottom-right.'),
(1194,[392,583],[216,559],[[180,565],[0,553]],None,None,'Grip moves left-to-right; continuous nearly horizontal forearm across lower screen.'),
(1195,[643,567],[491,541],[[450,540],[0,480]],None,None,'Wrist passes center. Forearm connects through right/bottom border; blade points left.'),
(1197,[1040,551],[922,516],[[900,504],[414,399]],[414,399],None,'Wrist reaches right; forearm continues right edge. Sword tip is now visible left of center.'),
(1200,None,None,[[1280,507],[905,399]],[905,399],None,'Hand/guard/arm offscreen right; only blade remains at right edge.'),
(1232,None,None,[[1187,646],[1173,272]],[1173,272],[173,560],'Recovery: sword rises near far right; guard lower/right crop. Shield already returned.'),
(1245,None,[1052,610],[[1051,560],[1019,0]],None,[162,589],'Upright return pose; glove lower-right, wrist below crop.')],
'right_diagonal':[
(1269,None,[1100,625],[[1080,583],[1004,0]],None,[166,575],'Near-neutral lead-in; wrist lower/right offscreen.'),
(1270,None,[1117,641],[[1109,596],[1004,0]],None,[171,577],'Load begins to right; blade keeps leaning left as whole weapon leaves right.'),
(1272,None,None,[[1280,365],[1182,0]],None,[155,611],'Only blade and partial guard edge at far right; guard center/wrist offscreen right.'),
(1311,None,None,None,None,None,'Both weapons offscreen during right-side preparation.'),
(1312,[1261,567],None,None,None,None,'Wrist partially clipped at right boundary; grip/pommel enters from right. Blade still offscreen right.'),
(1313,[1018,564],[1020,444],[[1044,428],[1280,310]],None,None,'Continuous forearm extends down-right to right/bottom crop. Wrist moves left; blade points up-right.'),
(1314,[849,600],[836,468],[[863,448],[1075,302]],[1075,302],None,'Forearm still down-right. Tip visible upper-right; hand crosses toward center.'),
(1316,[469,709],[409,551],[[433,520],[632,338]],[632,338],None,'Wrist partly clipped bottom-center-left. Blade passes reticle region while hand goes below it.'),
(1318,None,[80,663],[[105,620],[296,372]],[296,372],None,'Hand/guard enter lower-left crop; wrist/forearm below frame. Tip still left of center.'),
(1320,None,None,[[0,676],[46,451]],[46,451],None,'Only faint motion-blurred blade strip near left edge; endpoint confidence reduced.'),
(1351,None,[1010,687],[[997,640],[837,203]],[837,203],[165,555],'Recovery from low-right; wrist offscreen bottom; shield returns first.'),
(1365,None,[1048,616],[[1034,576],[997,0]],None,[176,585],'Upright slightly left-leaning return, both equipment pieces in neutral framing.')],
'jump':[
(889,None,[1040,637],[[1030,590],[988,0]],None,[165,577],'Lead-in at14.816667 before selected takeoff interval; near-neutral sword.'),
(890,None,[1034,661],[[1025,613],[988,0]],None,[174,594],'First lowering; right glove starts leaving lower edge.'),
(900,None,None,[[1000,720],[860,0]],None,[255,668],'Takeoff inertia low point: guard/hand below frame; shield nearly leaves bottom.'),
(910,None,[1015,660],[[1007,550],[807,0]],None,[241,610],'Rebound starts while sword leans farther left; wrist still below crop.'),
(920,None,[1013,574],[[985,531],[903,0]],None,[196,538],'Airborne rebound raises both equipment pieces; glove visible but wrist joint not reliably localizable.'),
(930,[1220,709],[1038,513],[[1018,470],[973,0]],None,[131,480],'Wrist joint partly cropped lower-right; more connected right forearm/glove visible at high pose.'),
(940,[1232,700],[1041,500],[[1024,465],[973,0]],None,[112,466],'High pose continues; shield rim reaches highest observed sampled position.'),
(950,None,[1005,680],[[990,638],[908,17]],[908,17],[138,612],'Second rapid dip/landing response: full blade tip comes into frame; hand drops below.'),
(960,None,[977,678],[[965,645],[895,117]],[895,117],[134,536],'Sword foreshortened with visible tip and left lean; not enlarged/tilted up-right. Shield begins rebound.'),
(970,None,[1006,650],[[995,612],[950,0]],None,[144,569],'Damped recovery; blade rises beyond top again.'),
(980,None,[1050,640],[[1038,600],[1005,0]],None,[155,590],'Returns toward ordinary locomotion framing at16.333333.'),
(981,None,[1047,630],[[1035,590],[1001,0]],None,[152,584],'One-source-frame follow-through after the selected jump range; no isolated clip cut.')],
'run':[
(707,None,[1065,621],[[1048,577],[1017,0]],None,[225,543],'Cycle start: upright left lean; low cropped shield and glove.'),
(710,None,[1067,631],[[1057,585],[1020,0]],None,[219,555],'Early down-bob.'),
(714,None,[1071,638],[[1060,596],[1018,0]],None,[213,588],'First low portion; shield lower than cycle start.'),
(717,None,[1072,641],[[1062,599],[1021,0]],None,[208,601],'Low portion continues with small wrist roll visible in blade orientation.'),
(721,None,[1064,628],[[1056,585],[1048,0]],None,[189,586],'Rising with blade closer to vertical.'),
(724,None,[1040,613],[[1036,570],[1045,0]],None,[176,567],'Rising/left shift; slight right lean begins.'),
(728,None,[1036,590],[[1035,558],[1060,0]],None,[144,557],'High/leftward phase; blade slight right lean. Wrist joint remains below crop.'),
(731,None,[1051,603],[[1045,556],[1075,0]],None,[188,572],'Next down-bob begins while blade remains near vertical.'),
(735,None,[1037,635],[[1034,598],[1047,0]],None,[165,579],'Second low portion; blade face becomes narrower than initial phase.'),
(738,None,[1041,656],[[1035,614],[1027,0]],None,[169,588],'Second low point with guard lowest among sampled cycle frames.'),
(742,None,[1058,639],[[1045,593],[1014,0]],None,[205,554],'Return rises toward original blade orientation and shield height.'),
(745,None,[1065,621],[[1048,577],[1017,0]],None,[225,543],'Matching cycle endpoint38 source frames later. Same pose boundary as f707; small compression/tracking error remains.')]
}
notes={
'left_reverse':[
'Boundary: sampled lead-in f1156=19.266667s, visible leftward load f1157=19.283333s; final return f1245=20.750000s. These are observation boundaries, not known source animation-asset start/end markers.',
'Hand loads from lower-right toward left/down (19.283333→19.366667), then leaves the view. In the cutting pass19.883333→19.950000 it travels LEFT→RIGHT while the blade points left. Do not mirror it with the other cut.',
'Wrist x progresses0.151→0.306→0.502→0.813 at19.883333,19.900000,19.916667,19.950000. The first three steps are consecutive60fps frames; this visible cross-screen pass is very fast.',
'At19.900000 and19.916667 the forearm spans the lower screen and remains continuously attached toward bottom/right. The elbow-side body can remain cropped; no top-entry dangling shoulder/cut surface is visible.',
'Shield is absent during the loaded hold and cutting pass, reappearing before the sword has fully recovered by20.533333. Retain this coordinated lowering rather than pinning the shield in neutral.',
'Blade axis is broadly horizontal, about−86°/−82°/−78° from up during19.900000/19.916667/19.950000. These are screen angles only, not3D rotations.'],
'right_diagonal':[
'Boundary: lead-in f1269=21.150000s, rightward load f1270=21.166667s, final return f1365=22.750000s. Source asset boundary markers are not visible.',
'Preparation exits the RIGHT edge. During21.866667→21.966667 the grip moves RIGHT→LEFT and down, while the blade points up-right. This differs from the left_reverse direction.',
'Observed wrist x≈0.985→0.795→0.663→0.366 at21.866667,21.883333,21.900000,21.933333. Forearm extends down-right toward the viewer body, then crosses the bottom crop. Wrist and guard do not rotate as an unanchored rigid forearm.',
'Tip moves from upper-right(0.840,0.419) at21.900000 toward center(0.494,0.469) at21.933333 then left(0.231,0.517) at21.966667. The hand lies BELOW the tip, crossing the lower half of the view.',
'Shield is offscreen through the pass; it returns from low-left before the upright sword recovers. The faint blade at22.000000 has lower measurement confidence due motion blur.',
'Null entries are offscreen or not reliably localizable. They are not zero-valued transforms.'],
'jump':[
'Boundary includes f889=14.816667s lead-in, f890=14.833333s first selected lowering, through f980=16.333333s recovery plus f981=16.350000s continuity check. The video shows continuous motion; these are not hard animation cuts.',
'Observed pose order: both equipment pieces sink (15.000000), rebound high (15.500000–15.666667), dip/foreshorten again (15.833333–16.000000), then settle (16.166667–16.350000).',
'Shield top rim moves y≈0.817 at14.833333→0.928 at15.000000→0.647 at15.666667. Left-arm movement is a major visual cue; a shield remaining at y≈0.65 during takeoff would miss it.',
'At15.000000 the sword guard and wrist are below frame. At15.500000–15.666667 the glove and some connected wrist appear lower-right. None of these poses show a detached shoulder entering from above.',
'At16.000000 the sword tip is visible at(0.699,0.163), guard≈(0.763,0.942), blade leans left. The visible full blade and reduced projected length are essential to the landing response; expanding it toward upper-right produces the wrong silhouette.',
'Takeoff/air/landing names describe visible inertia interpretation. Exact foot-ground contact time, trajectory height, gravity and3D pose cannot be measured from these first-person frames; game landing should remain grounded in actual collision.'],
'run':[
'Chosen complete faster-locomotion screen cycle: f707=11.783333s→f745=12.416667s, exactly38 source-frame intervals =0.633333s. Includes both endpoints; avoid duplicating the endpoint dwell when looping.',
'Measurement: normalized template correlation of the crossguard patch over original frames420–840 found a38-frame recurrence in the faster11–14s section. The ten-frame position pattern f707..716 vs f745..754 differs by mean1.2243 original pixels. Contact-sheet visual inspection confirms near-identical sword/shield boundary silhouettes.',
'Earlier7–9s locomotion repeats around58 frames=0.966667s. Do not use the earlier approximately1s estimate for this faster section. Input state and legs are absent, so this is a measured viewmodel cycle, not proven full-body stride or sprint-key state.',
'Sword remains nearly upright throughout. Guard moves roughly x0.81–0.84,y0.82–0.91 in sampled frames. Blade tilt changes only a few degrees either side of vertical; no horizontal tucked-running pose.',
'Two unequal vertical bobs occur inside the cycle: first low near11.90–11.95, rise by12.133333, second low near12.25–12.30, return by12.416667. Do not replace this shape with only one slow uniform sine.',
'Shield stays cropped bottom-left and follows the stride with its own small roll/height change, upper rim around y0.75–0.83. Wrist joints mostly stay outside the lower crop; only fingers/glove are visible. The source floor gives real camera/world motion cues, absent from an empty-background turntable.']
}
norm=lambda a:[round(a[0]/1280,4),round(a[1]/720,4)] if a else None
files=[]
for name,rows in groups.items():
 manifest=json.loads((p/f'{name}_extraction_manifest.json').read_text()); rec=[]
 for idx,w,g,b,t,r,n in rows:
  frame=next(x for x in manifest['frames'] if x['frame_index']==idx)
  rec.append({'f':idx,'t':frame['time_seconds'],'png':frame['image'],'W':norm(w),'G':norm(g),'B':[norm(x) for x in b] if b else None,'B_angle_deg':round(math.degrees(math.atan2(b[1][0]-b[0][0],b[0][1]-b[1][1])),1) if b else None,'T':norm(t),'R':norm(r),'observation':n})
 result={'name':name,'source_video':'sU7jk2OQlgc.mp4','source_size':[1280,720],'fps':60,'coordinate_system':'screen normalized x right/y down; origin upper-left','legend':{'W':'wrist joint center, NOT glove/grip center','G':'blade-axis/crossguard intersection','B':'two observed visible blade-axis endpoints, base toward tip','B_angle_deg':'image angle from up, positive right; not3D Euler','T':'tip only when visible','R':'highest visible shield rim point','null':'offscreen or not confidently localizable; never infer zero/3D'},'confidence':'Manual observed2D landmarks: medium; typical tolerance±20 original pixels; cropped/blurred points lower confidence as noted. Exact decoded timestamps. No3D reconstruction.','frames':rec,'direction':notes[name]}
 if name=='run':result['period_measurement']={k:manifest[k] for k in ['period_frames','period_seconds','period_measurement']}
 json_name=f'{name}_screen_observations.json';(p/json_name).write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
 lines=[f'# {name}: reference screen targets','', 'Actual decoded source at60fps,1280×720. Coordinates are manual2D observations, normalized x right/y down. Typical tolerance±20px; cropped/blurred landmarks are less certain. Null/offscreen is not a3D value. W=wrist joint, G=guard-axis junction, T=visible tip, R=topmost shield rim. Blade angle is image-plane only.','']
 lines.extend('- '+x for x in notes[name]);lines+=['','| f / source seconds | W | G | blade angle | T | R |','|---|---|---|---|---|---|']
 fmt=lambda x:'('+','.join(f'{v:.3f}' for v in x)+')' if x else 'offscreen'
 for v in rec:lines.append(f"| {v['f']} / {v['t']:.6f} | {fmt(v['W'])} | {fmt(v['G'])} | {v['B_angle_deg'] if v['B_angle_deg'] is not None else 'offscreen'} | {fmt(v['T'])} | {fmt(v['R'])} |")
 lines+=['','The contact-sheet cells are ordered left-to-right,top-to-bottom to match these rows. Exact original PNG filenames and all axis endpoints are in the JSON. Full PNGs remain local; the small transfer packet contains WebP+JSON+this document+extraction manifest only.','']
 md_name=f'{name}_reference_targets.md';(p/md_name).write_text('\n'.join(lines))
 names=[f'{name}_reference_transfer.webp',json_name,md_name,f'{name}_extraction_manifest.json']
 zip_name=f'{name}_reference_transfer_packet.zip'
 with ZipFile(p/zip_name,'w',ZIP_DEFLATED,compresslevel=9) as z:
  for f in names:z.write(p/f,f)
 for f in [f'{name}_reference_transfer.webp',zip_name,json_name,md_name]:
  data=(p/f).read_bytes();files.append({'file':f,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
print(json.dumps(files,indent=2))
(p/'followup_transfer_index.json').write_text(json.dumps(files,indent=2)+'\n')
