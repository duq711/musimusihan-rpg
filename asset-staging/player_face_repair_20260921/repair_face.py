"""Repair misclassified nose triangles with the exact authored facial UV map."""
import bpy,json,numpy as np
from pathlib import Path
W=Path(__file__).resolve().parent

def _remove_projected_eyes(material):
 # The source front photograph places its eyes below the mesh sockets.
 # Use a local two-dimensional lower-cheek sample for just those ghost eyes.
 node=next(n for n in material.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
 source=node.image;width,height=source.size
 pixels=np.empty(len(source.pixels),dtype=np.float32);source.pixels.foreach_get(pixels);pixels=pixels.reshape(height,width,4)
 ux=sorted([(-.439725589*x+.499223546)*(width-1) for x in [-.055,.055]])
 vy=[(.496373541*z+.0849177227)*(height-1) for z in [1.599,1.622]]
 xx,yy=np.meshgrid(np.arange(int(ux[0])-1,int(ux[1])+2),np.arange(int(vy[0])-1,int(vy[1])+2))
 u=xx/(width-1);v=yy/(height-1)
 x=(u-.499223546)/-.439725589;z=(v-.0849177227)/.496373541
 distance=np.minimum(np.sqrt(((x-.0305)/.020)**2+((z-1.6105)/.008)**2),np.sqrt(((x+.0305)/.020)**2+((z-1.6105)/.008)**2))
 t=np.clip((distance-.35)/.75,0,1);alpha=1-t*t*(3-2*t)
 active=alpha>0;iy,ix=yy[active],xx[active]
 sy=np.clip(iy-.018*.496373541*(height-1),0,height-1);lo=np.floor(sy).astype(int);hi=np.minimum(lo+1,height-1);f=(sy-lo)[:,None]
 sample=pixels[lo,ix,:3]*(1-f)+pixels[hi,ix,:3]*f
 result=pixels.copy();a=alpha[active,None];result[iy,ix,:3]=result[iy,ix,:3]*(1-a)+sample*a
 image=bpy.data.images.new('Gravebound_Facial_Skin_Clean_2048',width=width,height=height,alpha=True);image.colorspace_settings.name=source.colorspace_settings.name;image.pixels.foreach_set(result.reshape(-1));image.update();image.pack();node.image=image
 return {'source_image':source.name,'image':image.name,'size':[width,height],'affected_pixels':len(ix),'mask_eye_centers_x_m':[-.0305,.0305],'mask_center_z_m':1.6105,'mask_radii_m':[.020,.008],'sample_z_offset_m':-.018,'two_dimensional_sampling':True,'source_preserved':True}

def repair_face():
 head=bpy.data.objects['Gravebound_AnatomicalHead'];mesh=head.data
 front=next(i for i,m in enumerate(mesh.materials) if 'ReferenceProjection_Front' in m.name)
 points=[];uvs=[]
 for face in mesh.polygons:
  if face.material_index==front:
   for li in face.loop_indices:points.append([*mesh.vertices[mesh.loops[li].vertex_index].co,1]);uvs.append(list(mesh.uv_layers.active.data[li].uv))
 a=np.array(points);t=np.array(uvs);mapping=np.linalg.lstsq(a,t,rcond=None)[0]
 error=float(abs(a@mapping-t).max());assert error<1e-6
 repaired=[]
 for face in mesh.polygons:
  co=face.center
  if 'Hair_ScalpNeutralBrown' in mesh.materials[face.material_index].name and abs(co.x)<.015 and co.y<-.10 and co.z<1.63:
   face.material_index=front
   for li in face.loop_indices:mesh.uv_layers.active.data[li].uv=np.array([*mesh.vertices[mesh.loops[li].vertex_index].co,1])@mapping
   repaired.append(face.index)
 assert len(repaired)==72,len(repaired)
 skin=_remove_projected_eyes(mesh.materials[front])
 report={'projected_eye_cleanup':skin,'nose_faces_repaired':len(repaired),'faces':repaired,'uv_mapping':mapping.tolist(),'maximum_facial_uv_fit_error':error,'geometry_unchanged':True,'pass':True}
 (W/'face_report.json').write_text(json.dumps(report,indent=2));print('FACE REPAIR PASS',len(repaired));return report
