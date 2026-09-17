"""Build the Gravebound player as fully volumetric meshes from the generated concept.

Run Blender --background --python build_player.py. All authored originals remain
untouched. The paired concepts provide front/rear projections; transitional side
surfaces carry fine cloth/leather grain and respond to ordinary scene lighting.
"""
from pathlib import Path
import bpy, bmesh, math, json, shutil, sys
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
WORK = ROOT/'asset-staging/player_gravebound'
OUT = ROOT/'godot-game/assets/3d/player'
SOURCE = ROOT/'concept-art/player_gravebound/concept_front.png'
SOURCE_BACK = ROOT/'concept-art/player_gravebound/concept_back.png'
BASE = ROOT/'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16.blend'
S = 1.78/(1454-62)
PX_C = 512
PY_F = 1454
WORK.mkdir(parents=True,exist_ok=True); OUT.mkdir(parents=True,exist_ok=True)
shutil.copy2(SOURCE,WORK/'gravebound_concept.png')
shutil.copy2(SOURCE_BACK,WORK/'gravebound_concept_back.png')
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
parts=[]

def xyz(px,py,depth=0): return ((px-PX_C)*S,depth,(PY_F-py)*S)
def proj(v): return (v.x/S+PX_C)/1024, 1-(PY_F-v.z/S)/1536
img=bpy.data.images.load(str(WORK/'gravebound_concept.png')); img.pack()
back_img=bpy.data.images.load(str(WORK/'gravebound_concept_back.png'));back_img.pack()
image_pixels=list(img.pixels[:])
def patch_color(patch):
 x0,y0,x1,y1=patch;total=[0.0,0.0,0.0];count=0
 for y in range(y0,y1,2):
  for x in range(x0,x1,2):
   i=((1535-y)*1024+x)*4
   for channel in range(3):total[channel]+=image_pixels[i+channel]
   count+=1
 # The original albedo image is sRGB; procedural constants are scene-linear.
 return tuple((value/count/12.92 if value/count<=.04045 else ((value/count+.055)/1.055)**2.4) for value in total)+(1,)

def material(name,color=(1,1,1,1),patch=None,rough=.88):
 m=bpy.data.materials.new(name); m.diffuse_color=color; m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=color;p.inputs['Roughness'].default_value=rough
 p.inputs['Specular IOR Level'].default_value=.18
 if patch is not False:
  n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=img;m.node_tree.links.new(n.outputs['Color'],p.inputs['Base Color'])
 m['projection_patch']=str(patch)
 return m
front=material('Gravebound_Concept_Front_PBR')
cloth=material('Gravebound_Weathered_Quilted_Cloth',patch=(420,460,480,575))
hoodmat=material('Gravebound_Charcoal_Woven_Hood',patch=(450,159,463,210))
leather=material('Gravebound_Dark_Worn_Leather',patch=(363,1155,421,1230),rough=.75)
skin=material('Gravebound_Weathered_Skin',patch=(482,196,498,219))
iron=material('Gravebound_Oxidized_Iron',(0.16,.17,.17,1),False,.68)
black=material('Gravebound_Hood_Interior',(.007,.008,.009,1),False,.99)

def finish(obj,name,side=cloth,front_enable=True):
 obj.name=name
 obj['project_front']=front_enable
 obj['project_back']=True
 obj['side_material']=side.name
 bpy.context.view_layer.update()
 # Bake the authored world coordinates so every submesh shares the foot origin.
 mat=obj.matrix_world.copy()
 for v in obj.data.vertices: v.co=mat@v.co
 obj.matrix_world.identity()
 obj.data.materials.clear();obj.data.materials.append(front);obj.data.materials.append(side)
 obj.data.update()
 uv=obj.data.uv_layers.new(name='ConceptProjection') if not obj.data.uv_layers else obj.data.uv_layers.active
 patch=eval(side.get('projection_patch','False'))
 for p in obj.data.polygons:
  facing = p.normal.y < -.20
  p.material_index=0 if facing and front_enable else 1
  p.use_smooth=True
  for li in p.loop_indices:
   v=obj.data.vertices[obj.data.loops[li].vertex_index].co
   if p.material_index==0: uv.data[li].uv=proj(v)
   elif patch:
    x0,y0,x1,y1=patch
    # Repeat only a cloth/skin patch from the same concept on non-front faces.
    u=((v.x*5.7+v.y*3.8)%1); q=((v.z*3.5)%1)
    uv.data[li].uv=((x0+(x1-x0)*u)/1024,1-(y0+(y1-y0)*q)/1536)
   else:uv.data[li].uv=(.5,.5)
 parts.append(obj);return obj

def mesh(name,verts,faces,side=cloth,front_enable=True):
 d=bpy.data.meshes.new(name+'Mesh'); d.from_pydata(verts,[],faces);d.update()
 bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free();d.update()
 o=bpy.data.objects.new(name,d);scene.collection.objects.link(o)
 return finish(o,name,side,front_enable)

def tube(name,rows,side=cloth,segments=64,folds=0,cap=True):
 # rows: source-image y, center x, horizontal radius px, depth metres, center y.
 refined=[]
 for j in range(len(rows)-1):
  a=rows[max(j-1,0)];b=rows[j];c=rows[j+1];d=rows[min(j+2,len(rows)-1)]
  for k in range(5):
   t=k/5
   refined.append(tuple(.5*((2*b[i])+(-a[i]+c[i])*t+(2*a[i]-5*b[i]+4*c[i]-d[i])*t*t+(-a[i]+3*b[i]-3*c[i]+d[i])*t*t*t) for i in range(5)))
 refined.append(rows[-1]);rows=refined
 v=[];f=[]
 for j,(py,cx,rx,dep,cy) in enumerate(rows):
  for k in range(segments):
   a=2*math.pi*k/segments
   corr=folds*(math.sin(a*14+.4)+.35*math.sin(a*31+j*.7))
   v.append(xyz(cx+(rx+corr/S)*math.sin(a),py,cy-(dep+corr)*math.cos(a)))
 for j in range(len(rows)-1):
  for k in range(segments):
   n=(k+1)%segments;f.append((j*segments+k,j*segments+n,(j+1)*segments+n,(j+1)*segments+k))
 if cap:
  f.append(tuple(range(segments-1,-1,-1)));f.append(tuple((len(rows)-1)*segments+k for k in range(segments)))
 return mesh(name,v,f,side)

def panel(name,points,side=hoodmat,base=-.15,bulge=.024,thickness=.008):
 # A subdivided cloth surface with genuine curvature and a sealed cloth edge.
 n=len(points);cx=sum(p[0] for p in points)/n;cy=sum(p[1] for p in points)/n
 verts=[]; faces=[];levels=12
 for back in [0,1]:
  center_bend=.132*(abs((cx-512)*S)/.271)**3 if 'Mantle' in name else 0
  verts.append(xyz(cx,cy,base-bulge+back*thickness+center_bend))
  for r in range(1,levels+1):
   t=r/levels
   for i,(x,y) in enumerate(points):
    px=cx+(x-cx)*t;py=cy+(y-cy)*t
    bend=.132*(abs((px-512)*S)/.271)**3 if 'Mantle' in name else 0
    verts.append(xyz(px,py,base-bulge*(1-t*t)+.003*math.sin(i*4+t*13)*t+back*thickness+bend))
 off=1+levels*n
 for back in [0,1]:
  z=back*off
  for i in range(n):
   face=(z,z+1+i,z+1+(i+1)%n); faces.append(face if back==0 else tuple(reversed(face)))
  for r in range(levels-1):
   for i in range(n):
    a=z+1+r*n+i;b=z+1+r*n+(i+1)%n;c=z+1+(r+1)*n+(i+1)%n;d=z+1+(r+1)*n+i
    faces.append((a,b,c,d) if back==0 else (d,c,b,a))
 for i in range(n):
  a=1+(levels-1)*n+i;b=1+(levels-1)*n+(i+1)%n;faces.append((a,b,b+off,a+off))
 return mesh(name,verts,faces,side)

def capsule(name,a,b,r,side=leather):
 A=Vector(a);B=Vector(b);mid=(A+B)/2
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,location=mid)
 o=bpy.context.object;o.scale=(r,r,(B-A).length/2+r*.42);o.rotation_euler=(B-A).to_track_quat('Z','Y').to_euler()
 return finish(o,name,side)

# Continuous padded torso; the upper region is covered by the capelet.
tube('Gravebound_QuiltedTorso',[(300,512,84,.10,0),(335,512,118,.135,0),(392,512,134,.15,0),(445,512,135,.151,0),(495,512,130,.145,0),(540,512,127,.14,0),(574,512,128,.136,0),(612,512,124,.13,0),(650,512,136,.136,0),(685,512,143,.14,0)],folds=.0016)
# Split coat panels use true rear thickness; the back skirt has its own curved volume.
panel('Gravebound_CoatSkirt_L',[(378,612),(508,617),(498,737),(479,842),(457,962),(431,1059),(375,1042),(295,999),(315,908),(344,773)],cloth,-.131,.045,.014)
panel('Gravebound_CoatSkirt_R',[(511,617),(640,612),(667,757),(697,918),(720,1006),(661,1038),(575,1061),(550,966),(526,831),(506,742)],cloth,-.130,.045,.014)
# Back and sides round the coat into a hollow garment, with modest vertical folds.
v=[];f=[];N=96
for j,(py,rx,dep) in enumerate([(600,124,.13),(680,145,.145),(800,169,.164),(920,196,.182),(1020,203,.182)]):
 for i in range(N+1):
  a=math.pi*.46+(math.pi*1.08)*i/N
  v.append(xyz(512+rx*math.sin(a),py+(10*math.cos(a*3) if j==4 else 0),-dep*math.cos(a)+.004*math.sin(a*22)))
for j in range(4):
 for i in range(N):a=j*(N+1)+i;f.append((a,a+1,a+N+2,a+N+1))
o=mesh('Gravebound_CoatBackAndSides',v,f,cloth,False)
mod=o.modifiers.new('RealCoatThickness','SOLIDIFY');mod.thickness=.008
bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)

# Trousers and layered leather boots are full circumferential geometry.
for suffix,center in [('L',401),('R',619)]:
 tube('Gravebound_Trousers_'+suffix,[(710,center,35,.064,.018),(820,center,43,.07,.025),(920,center,48,.075,.025),(1020,center,56,.074,.025),(1060,center,53,.070,.02),(1095,center,50,.067,.015),(1140,center,47,.062,.015)],cloth,folds=.002)
 c=400 if suffix=='L' else 634
 direction=-1 if suffix=='L' else 1
 tube('Gravebound_Boot_'+suffix,[(1090,c,49,.071,.015),(1128,c,53,.076,.015),(1163,c,48,.072,.01),(1210,c,44,.067,.005),(1260,c,41,.063,0),(1305,c,41,.065,-.008),(1342,c,44,.074,-.025),(1370,c+direction*5,48,.100,-.06),(1393,c+direction*17,54,.139,-.10),(1412,c+direction*26,60,.153,-.115),(1428,c+direction*27,61,.151,-.115),(1442,c+direction*25,59,.147,-.11),(1448,c+direction*25,54,.135,-.107)],leather,folds=.0013)
 tube('Gravebound_BootCuff_'+suffix,[(1105,c,54,.082,.015),(1115,c,57,.085,.015),(1144,c,54,.083,.015),(1152,c,52,.079,.015)],leather)

# Relaxed arms include visible gathers and separate leather bracers.
for suffix,rows in [('L',[(366,352,45,.073,0),(412,340,45,.075,0),(462,328,46,.078,-.005),(500,320,44,.075,-.008),(540,307,45,.073,-.01),(573,300,43,.066,-.013),(611,294,39,.061,-.021),(650,287,38,.055,-.024),(686,284,34,.05,-.030),(719,281,31,.046,-.038)]),('R',[(366,673,43,.073,0),(414,683,44,.075,0),(460,692,47,.077,-.003),(505,704,45,.072,-.01),(545,715,43,.07,-.02),(582,719,42,.065,-.025),(620,724,39,.06,-.03),(663,729,38,.055,-.04),(705,725,35,.05,-.043),(731,722,30,.045,-.046)])]:
 # End the sleeve inside the bracer and taper the concealed overlap. This
 # removes the coincident cloth/leather surfaces that caused zebra stripes.
 sleeve_rows=[list(row) for row in rows[:6]]
 sleeve_rows[-1][2]-=6;sleeve_rows[-1][3]-=.012
 py,cx,rx,dep,cy=rows[6]
 sleeve_rows.append((py,cx,rx*.72,dep*.70,cy))
 tube('Gravebound_Sleeve_'+suffix,sleeve_rows,cloth,folds=.0028)
 br=rows[5:]
 tube('Gravebound_Bracer_'+suffix,[(py,cx,rx+2,dep+.004,cy-.003) for py,cx,rx,dep,cy in br],leather,folds=.0006)

# Fingerless glove palms, exposed fingers and thumbs, all volumetric and posed.
for suffix,pts,dep in [('L',[(253,709),(307,716),(312,756),(299,786),(269,804),(249,772)],-.082),('R',[(698,717),(751,714),(755,769),(738,802),(707,792),(686,758)],-.085)]:
 panel('Gravebound_FingerlessGlove_'+suffix,pts,leather,dep,.022,.032)
leftf=[((266,787),(273,819),.009),((276,794),(289,832),.009),((286,793),(300,824),.008),((296,785),(307,812),.0075),((300,765),(306,794),.010)]
rightf=[((710,789),(699,827),.009),((720,796),(711,841),.009),((730,796),(723,838),.008),((739,788),(735,820),.0075),((695,769),(684,799),.010)]
for suffix,fingers in [('L',leftf),('R',rightf)]:
 for i,(a,b,r) in enumerate(fingers):
  A=Vector(xyz(*a,-.113));B=Vector(xyz(*b,-.113));M=A.lerp(B,.52);M.y-=.004
  capsule('Gravebound_Finger_'+suffix+str(i)+'a',A,M,r,skin)
  capsule('Gravebound_Finger_'+suffix+str(i)+'b',M,B,r*.82,skin)

# Belt and pouch silhouettes are built above the actual torso front.
tube('Gravebound_LeatherBelt',[(583,512,129,.15,0),(594,512,130,.151,0),(620,512,132,.153,0),(629,512,133,.152,0)],leather)
panel('Gravebound_BeltBuckle',[(476,588),(517,590),(518,626),(473,621)],iron,-.167,.005,.01)
panel('Gravebound_BeltTongue',[(522,593),(564,599),(586,697),(575,708),(560,701)],leather,-.159,.004,.006)
panel('Gravebound_Pouch_L',[(377,594),(420,603),(406,678),(395,695),(357,689),(348,675)],leather,-.176,.035,.072)
panel('Gravebound_PouchFlap_L',[(377,595),(419,603),(411,642),(391,665),(366,658)],leather,-.217,.013,.008)
panel('Gravebound_Pouch_R',[(601,598),(637,597),(652,662),(644,687),(610,690),(595,677),(588,625)],leather,-.176,.038,.072)
panel('Gravebound_PouchFlap_R',[(600,599),(636,600),(644,642),(628,661),(604,654)],leather,-.220,.011,.008)

# Anatomical face and neck from the CC0-based original, reprojected to new art.
with bpy.data.libraries.load(str(BASE),link=False) as (data_from,data_to):
 data_to.objects=['Mercenary_Male_HeadNeck_LOD0','Mercenary_Eyes_GameReady']
for index,head in enumerate(data_to.objects):
 scene.collection.objects.link(head)
 head.parent=None;head.matrix_world.identity();head.modifiers.clear()
 for vv in head.data.vertices:
  vv.co.z-=.055; vv.co.y-=.026
 finish(head,'Gravebound_AnatomicalHead' if index==0 else 'Gravebound_Eyes',skin)

# Hood: deep back shell with a real face aperture, a pointed crown, and rolled rim.
hood_rows=[(62,1,0,.002,.022),(72,19,0,.025,.022),(94,44,0,.066,.015),(123,63,0,.092,.005),(143,70,12,.105,-.007),(169,77,32,.111,-.01),(200,84,44,.119,-.013),(230,91,54,.127,-.015),(258,99,67,.132,-.012),(280,103,64,.131,-.005),(299,94,35,.126,.003),(315,69,2,.106,.009)]
v=[];f=[];N=112
for py,rx,opening,depth,cy in hood_rows:
 angle=math.asin(min(.96,opening/max(rx,1)))
 for i in range(N+1):
  a=angle+(2*math.pi-2*angle)*i/N
  wrinkle=.002*(math.sin(a*13+py*.018)+.4*math.sin(a*27-py*.027))
  v.append(xyz(512+(rx+wrinkle/S)*math.sin(a),py,cy-(depth+wrinkle)*math.cos(a)))
for j in range(len(hood_rows)-1):
 for i in range(N):
  a=j*(N+1)+i;f.append((a,a+1,a+N+2,a+N+1))
o=mesh('Gravebound_PointHood',v,f,hoodmat)
mod=o.modifiers.new('HoodClothThickness','SOLIDIFY');mod.thickness=.006;mod.offset=0
bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
# A deep dark aperture prevents light from revealing the back of the scalp.
# Actual head surface remains visible; hood shell surrounds it.

# Layered shoulder mantle: front halves plus rear curved shoulder drape.
cowl=tube('Gravebound_InnerNeckCowl',[(274,512,58,.102,.001),(298,512,63,.108,0),(322,512,75,.121,0),(341,512,85,.132,0)],hoodmat,folds=.001)
cowl['project_front']=False;cowl['project_back']=False
panel('Gravebound_Mantle_L',[(431,274),(467,299),(506,320),(494,376),(478,449),(420,426),(364,400),(309,347),(353,314),(403,288)],hoodmat,-.145,.035,.008)
panel('Gravebound_Mantle_R',[(535,316),(568,297),(607,274),(653,294),(692,323),(724,347),(686,382),(641,416),(532,449),(517,366)],hoodmat,-.145,.036,.008)
v=[];f=[];N=96;M=16
for j in range(M+1):
 t=j/M
 for i in range(N+1):
  a=math.pi*.46+math.pi*1.08*i/N;rx=(84+(210-84)*t);depth=.115+.091*t
  py=273+(192-107*abs(math.sin(a)))*t+4*math.sin(a*9)*t
  v.append(xyz(512+rx*math.sin(a),py,-depth*math.cos(a)))
for j in range(M):
 for i in range(N):a=j*(N+1)+i;f.append((a,a+1,a+N+2,a+N+1))
o=mesh('Gravebound_MantleBack',v,f,hoodmat,False)
mod=o.modifiers.new('MantleThickness','SOLIDIFY');mod.thickness=.008
bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
# The single clasp is already represented by the fitted mantle's baked art.

# Export only the character. Metadata explicitly documents authored coordinates.
parent=bpy.data.objects.new('GraveboundPlayer',None);scene.collection.objects.link(parent)
parent['height_m']=1.78;parent['front_axis']='-Z in Godot';parent['source']='OpenAI generated gravebound concept; volumetric mesh reconstruction'
for o in parts:o.parent=parent
bpy.ops.object.select_all(action='DESELECT');parent.select_set(True)
for o in parts:o.select_set(True)
# Bake continuous projection blending onto one game atlas. Side appearance uses
# only actual garment patches; a smooth normal blend removes rectangular seams.
blended={}
for o in parts:
 side=bpy.data.materials[o['side_material']]
 patch=eval(side.get('projection_patch','False'))
 front_uv=o.data.uv_layers.new(name='FrontProjection')
 back_uv=o.data.uv_layers.new(name='BackProjection')
 side_uv=o.data.uv_layers.new(name='SideProjection')
 for loop in o.data.loops:
  v=o.data.vertices[loop.vertex_index].co
  front_uv.data[loop.index].uv=proj(v)
  u_front,v_front=proj(v);back_uv.data[loop.index].uv=(1-u_front,v_front)
  if patch:
   x0,y0,x1,y1=patch
   u=max(0,min(1,(v.x+v.y+.5)));q=max(0,min(1,v.z/1.78))
   side_uv.data[loop.index].uv=((x0+(x1-x0)*u)/1024,1-(y0+(y1-y0)*q)/1536)
 key=side.name+str(o['project_front'])+str(o['project_back'])
 if key not in blended:
  m=bpy.data.materials.new('Bake_'+key);m.use_nodes=True;nt=m.node_tree;nt.nodes.clear()
  output=nt.nodes.new('ShaderNodeOutputMaterial');em=nt.nodes.new('ShaderNodeEmission');nt.links.new(em.outputs[0],output.inputs['Surface'])
  if patch:
   # Calm, fine woven grain replaces the warped periodic UVs in revision 2.
   # Derive its colour from a safe garment-only patch of the concept, and use
   # spatially continuous noise instead of stretching rings across the body.
   coord=nt.nodes.new('ShaderNodeTexCoord')
   noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=420;noise.inputs['Detail'].default_value=2;noise.inputs['Roughness'].default_value=.65
   nt.links.new(coord.outputs['Object'],noise.inputs['Vector'])
   ramp=nt.nodes.new('ShaderNodeValToRGB');base_color=patch_color(patch)
   ramp.color_ramp.elements[0].position=.12;ramp.color_ramp.elements[0].color=tuple(v*.80 for v in base_color[:3])+(1,)
   ramp.color_ramp.elements[1].position=.88;ramp.color_ramp.elements[1].color=tuple(v*1.16 for v in base_color[:3])+(1,)
   nt.links.new(noise.outputs['Fac'],ramp.inputs[0]);side_color=ramp.outputs['Color']
  else:
   rgb=nt.nodes.new('ShaderNodeRGB');rgb.outputs[0].default_value=side.diffuse_color;side_color=rgb.outputs[0]
  geo=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(geo.outputs['Normal'],sep.inputs[0])
  current_color=side_color
  if o['project_back']:
   uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='BackProjection'
   tex=nt.nodes.new('ShaderNodeTexImage');tex.image=back_img;nt.links.new(uv.outputs[0],tex.inputs['Vector'])
   ramp=nt.nodes.new('ShaderNodeMapRange');ramp.clamp=True;ramp.interpolation_type='SMOOTHSTEP';ramp.inputs['From Min'].default_value=.12;ramp.inputs['From Max'].default_value=.58
   nt.links.new(sep.outputs['Y'],ramp.inputs['Value'])
   mix=nt.nodes.new('ShaderNodeMixRGB');nt.links.new(ramp.outputs[0],mix.inputs[0]);nt.links.new(current_color,mix.inputs[1]);nt.links.new(tex.outputs['Color'],mix.inputs[2]);current_color=mix.outputs[0]
  if o['project_front']:
   uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='FrontProjection'
   tex=nt.nodes.new('ShaderNodeTexImage');tex.image=img;nt.links.new(uv.outputs[0],tex.inputs['Vector'])
   ramp=nt.nodes.new('ShaderNodeMapRange');ramp.clamp=True;ramp.interpolation_type='SMOOTHSTEP';ramp.inputs['From Min'].default_value=-.12;ramp.inputs['From Max'].default_value=-.58
   nt.links.new(sep.outputs['Y'],ramp.inputs['Value'])
   mix=nt.nodes.new('ShaderNodeMixRGB');nt.links.new(ramp.outputs[0],mix.inputs[0]);nt.links.new(current_color,mix.inputs[1]);nt.links.new(tex.outputs['Color'],mix.inputs[2]);current_color=mix.outputs[0]
  nt.links.new(current_color,em.inputs['Color'])
  blended[key]=m
 o.data.materials.clear();o.data.materials.append(blended[key])
 for p in o.data.polygons:p.material_index=0
 atlas_uv=o.data.uv_layers.new(name='Atlas');o.data.uv_layers.active=atlas_uv;atlas_uv.active_render=True
parent.select_set(False)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.003,area_weight=.45);bpy.ops.object.mode_set(mode='OBJECT')
atlas=bpy.data.images.new('Gravebound_4K_Baked_Atlas',width=4096,height=4096,alpha=False)
for m in blended.values():
 node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=atlas;m.node_tree.nodes.active=node;node.select=True
scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.use_clear=False;scene.render.bake.margin=12
bpy.ops.object.bake(type='EMIT')
atlas.filepath_raw=str(WORK/'gravebound_atlas.png');atlas.file_format='PNG';atlas.save();atlas.pack()
runtime_mat=bpy.data.materials.new('Gravebound_Baked_Garments_PBR');runtime_mat.use_nodes=True
p=runtime_mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.16
tex=runtime_mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas;uv=runtime_mat.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='Atlas';runtime_mat.node_tree.links.new(uv.outputs[0],tex.inputs[0]);runtime_mat.node_tree.links.new(tex.outputs[0],p.inputs['Base Color'])
for o in parts:
 o.data.materials.clear();o.data.materials.append(runtime_mat)
 for uv_layer in list(o.data.uv_layers):
  if uv_layer.name!='Atlas':o.data.uv_layers.remove(uv_layer)
 o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True
# Source Blender retains editable meshes and packed concept.
scene.unit_settings.system='METRIC'
scene.world=bpy.data.worlds.new('GraveboundPreviewWorld');scene.world.color=(.07,.07,.07)
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=1024;scene.render.resolution_y=1536;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'gravebound_player.blend'))
props=set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
kwargs=dict(filepath=str(OUT/'gravebound_player.glb'),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_animations=False,export_skins=False,export_extras=True,export_image_format='JPEG',export_jpeg_quality=95)
parent.rotation_euler.z=math.pi
parent.select_set(True)
bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(**{k:v for k,v in kwargs.items() if k in props})
parent.rotation_euler.z=0
bpy.context.view_layer.update()
allv=[o.matrix_world@v.co for o in parts for v in o.data.vertices]
report={'revision':4,'height_m':max(v.z for v in allv)-min(v.z for v in allv),'bounds_blender':[[min(v[i] for v in allv) for i in range(3)],[max(v[i] for v in allv) for i in range(3)]],'mesh_count':len(parts),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in parts),'mesh_names':[o.name for o in parts],'glb_bytes':(OUT/'gravebound_player.glb').stat().st_size,'uv_channels':['Atlas'],'atlas_size':[4096,4096],'front_axis_godot':'-Z','source_concept':str(SOURCE),'source_concept_back':str(SOURCE_BACK)}
(WORK/'build_report.json').write_text(json.dumps(report,indent=2))
print('GRAVEBOUND EXPORT COMPLETE',json.dumps(report),flush=True)
if '--skip-previews' in sys.argv:sys.exit(0)

# Quiet offline Blender QA. The game renderer is checked separately by the task.
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(0,-5,.89));cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=1.964;aim(cam,(0,0,.89));scene.camera=cam
world=scene.world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.25,.25,.25,1);world.node_tree.nodes['Background'].inputs[1].default_value=.65
for name,loc,energy,size in [('Key',(-3,-4,5),240,5),('Fill',(3,-2,3),90,5),('Rim',(0,3,4),250,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,1))
scene.render.film_transparent=False
for name,loc in [('front',(0,-5,.89)),('three_quarter',(3,-5,1.5)),('back',(0,5,.95))]:
 cam.location=loc;aim(cam,(0,0,.89));scene.render.filepath=str(WORK/(name+'.png'));bpy.ops.render.render(write_still=True)
print('GRAVEBOUND BUILD',json.dumps(report))
