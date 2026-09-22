import * as THREE from './vendor/build/three.module.js';
import {sourceSections,targetSections,shoulderRoof} from './pose-profile.js';

// Review pose for the static production mesh. The source geometries are kept
// intact and swapped back on reset, so repeated toggles cannot accumulate drift.
const smooth = v => {const t = Math.max(0,Math.min(1,v));return t*t*(3-2*t);};
const identity = new THREE.Quaternion();
const limbs = [-1,1].map(side => {
  const shoulder = new THREE.Vector3(side*.205,1.37368,-.0046);
  const elbow = new THREE.Vector3(side*.278,1.15793,-.014);
  const wrist = new THREE.Vector3(side*.369494,.930478,-.07538);
  const direction = new THREE.Vector3(side,0,0);
  const upper = new THREE.Quaternion().setFromUnitVectors(elbow.clone().sub(shoulder).normalize(),direction);
  const lower = new THREE.Quaternion().setFromUnitVectors(wrist.clone().sub(elbow).normalize(),direction);
  const targetElbow = shoulder.clone().addScaledVector(direction,shoulder.distanceTo(elbow));
  return {side,shoulder,elbow,wrist,upper,lower,targetElbow};
});
function raisePoint(point) {
  const limb = limbs[point.x<0?0:1];
  // Move the shared torso/sleeve boundary by the same coordinate-based field.
  const shoulderRoof = smooth((point.y-1.305)/.10);
  const inner = THREE.MathUtils.lerp(.188,.080,shoulderRoof);
  const outer = THREE.MathUtils.lerp(.215,.255,shoulderRoof);
  const weight = smooth((Math.abs(point.x)-inner)/(outer-inner));
  if(weight===0)return point.clone();
  const rotation = identity.clone().slerp(limb.upper,weight);
  const posed = point.clone().sub(limb.shoulder).applyQuaternion(rotation).add(limb.shoulder);
  const lowerWeight = smooth((1.225-point.y)/.10)*weight;
  if(lowerWeight>0){
    const upperPoint = point.clone().sub(limb.shoulder).applyQuaternion(limb.upper).add(limb.shoulder);
    const lowerPoint = point.clone().sub(limb.elbow).applyQuaternion(limb.lower).add(limb.targetElbow);
    posed.addScaledVector(lowerPoint.sub(upperPoint),lowerWeight);
  }
  // Correct the static sleeve rest-shape after abduction. Lift the compressed
  // underarm cloth into the horizontal upper-arm envelope, with a monotonic
  // vertical mapping and a smooth falloff before the elbow and chest centre.
  const underarm = smooth((Math.abs(posed.x)-.19)/.065)*smooth((.45-Math.abs(posed.x))/.12);
  posed.y += .075*underarm*smooth((1.425-posed.y)/.19)*smooth((posed.y-1.18)/.08);
  return posed;
}
// Cubic Hermite interpolation keeps the corrective cage tangent-continuous.
// Source sections are closely spaced to measure the actual sleeve silhouette.
function section(rows,x,column) {
 let i=0;while(i<rows.length-2&&rows[i+1][0]<x)i++;
 const a=rows[i],b=rows[i+1],h=b[0]-a[0],t=THREE.MathUtils.clamp((x-a[0])/h,0,1);
 const previous=rows[Math.max(0,i-1)],next=rows[Math.min(rows.length-1,i+2)];
 const m0=(b[column]-previous[column])/(b[0]-previous[0]);
 const m1=(next[column]-a[column])/(next[0]-a[0]);
 return (2*t*t*t-3*t*t+1)*a[column]+(t*t*t-2*t*t+t)*h*m0+(-2*t*t*t+3*t*t)*b[column]+(t*t*t-t*t)*h*m1;
}
function fitSleeve(point) {
 const p=raisePoint(point),x=Math.abs(p.x);
 if(x<.10)return p;
 const blend=smooth((x-.10)/.10)*smooth((.685-x)/.020)*smooth((p.y-1.18)/.12);
 if(blend===0){p.y+=.045*smooth((x-.10)/.115)*smooth((p.y-1.24)/.09);return p;}
 const sampleX=Math.max(.19,x);
 const lo=section(sourceSections,sampleX,1),hi=section(sourceSections,sampleX,2);
 const front=section(sourceSections,sampleX,3),back=section(sourceSections,sampleX,4);
 const y=section(targetSections,sampleX,1)+(p.y-lo)/(hi-lo)*(section(targetSections,sampleX,2)-section(targetSections,sampleX,1));
 const z=section(targetSections,sampleX,3)+(p.z-front)/(back-front)*(section(targetSections,sampleX,4)-section(targetSections,sampleX,3));
 p.y=THREE.MathUtils.lerp(p.y,y,blend);p.z=THREE.MathUtils.lerp(p.z,z,blend);
 // Preserve a small cloth relief over the elliptical anatomical cross-section.
 // A positive radial slope retains orientation instead of flattening vertices.
 const cy=(section(targetSections,sampleX,1)+section(targetSections,sampleX,2))*.5;
 const cz=(section(targetSections,sampleX,3)+section(targetSections,sampleX,4))*.5;
 const ry=(section(targetSections,sampleX,2)-section(targetSections,sampleX,1))*.5;
 const rz=(section(targetSections,sampleX,4)-section(targetSections,sampleX,3))*.5;
 const radial=Math.hypot((p.y-cy)/ry,(p.z-cz)/rz);
 const round=smooth((x-.175)/.06)*smooth((.68-x)/.035)*.85;
 if(radial>.001){const scale=1+round*(1/radial-1);p.y=cy+(p.y-cy)*scale;p.z=cz+(p.z-cz)*scale;}
 p.y+=.045*smooth((x-.10)/.115)*smooth((p.y-1.24)/.09);
 return p;
}
const shoulderSections=[
 [.075,1.10,1.4735,.088],[.12,1.20,1.475,.085],
 [.14,1.245,1.476,.081],[.16,1.287,1.477,.077],
 [.18,1.318,1.478,.073],[.20,1.345,1.479,.070],
 [.23,1.358,1.480,.065],[.27,1.365,1.474,.059],
];
export function posePoint(point) {
 const p=fitSleeve(point),x=Math.abs(p.x);
 if(x>.065&&x<.225){
   const target=1.4735+.006*smooth((x-.065)/.16)-.008*Math.exp(-(((x-.125)/.040)**2));
   const amount=Math.max(0,target-section(shoulderRoof,x,1));
   p.y+=amount*smooth((p.y-1.28)/.115)*smooth((x-.065)/.015)*smooth((.225-x)/.015);
 }
 // Fill the false diagonal furrows across the raised clavicle/sleeve join.
 // An elliptical front/back surface blends into the retained chest below.
 const shoulderBlend=.78*smooth((x-.075)/.035)*smooth((.27-x)/.055)*smooth((p.y-1.28)/.07);
 if(shoulderBlend>0){
   const bottom=section(shoulderSections,x,1),top=section(shoulderSections,x,2);
   const vertical=(p.y-(bottom+top)*.5)/((top-bottom)*.5);
   const depth=section(shoulderSections,x,3)*Math.sqrt(Math.max(.002,1-vertical*vertical));
   const z=-.0046+Math.tanh((p.z+.0046)/.010)*depth;
   p.z=THREE.MathUtils.lerp(p.z,z,shoulderBlend);
 }
 // The imported sleeve underside folds 33 mm below its own attachment seam.
 // Compress only that low pocket toward the axillary fold; pin the seam above.
 const floor=1.350+.016*smooth((x-.185)/.055);
 const fold=smooth((x-.169)/.014)*smooth((.255-x)/.025)*smooth((p.y-1.22)/.045);
 const d=p.y-floor;
 const softplus=Math.max(0,d)+Math.log1p(Math.exp(-Math.abs(d)*600))/600;
 p.y=THREE.MathUtils.lerp(p.y,floor+.08*d+.92*softplus,fold);
 return p;
}
export function poseJacobian(point) {
  const columns=[];
  for(let axis=0;axis<3;axis++){
    const h=new THREE.Vector3();h.setComponent(axis,.00002);
    columns.push(posePoint(point.clone().add(h)).sub(posePoint(point.clone().sub(h))).multiplyScalar(25000));
  }
  return new THREE.Matrix3().set(columns[0].x,columns[1].x,columns[2].x,columns[0].y,columns[1].y,columns[2].y,columns[0].z,columns[1].z,columns[2].z);
}
// Smooth the raised cloth connection on one welded adjacency graph. Separate
// glTF primitives must share both positions and normals at their common border.
function relaxShoulders(parts) {
 const vertices=[],cells=new Map(),maps=[];
 for(const part of parts){
   const map=[],p=part.original.getAttribute('position'),q=part.posed.getAttribute('position');
   for(let i=0;i<p.count;i++){
     const rest=new THREE.Vector3().fromBufferAttribute(p,i).applyMatrix4(part.mesh.matrixWorld);
     const key=rest.toArray().map(v=>Math.round(v*1e5)).join(',');
     const bucket=cells.get(key)||[];let index=bucket.find(j=>vertices[j].rest.distanceToSquared(rest)<1e-12);
     if(index===undefined){index=vertices.length;const position=new THREE.Vector3().fromBufferAttribute(q,i).applyMatrix4(part.mesh.matrixWorld);
       const x=Math.abs(position.x),y=position.y;
       vertices.push({rest,position,neighbors:new Set(),weight:smooth((x-.075)/.035)*smooth((.355-x)/.10)*smooth((y-1.285)/.045),normal:new THREE.Vector3()});
       bucket.push(index);cells.set(key,bucket);
     }
     map.push(index);
   }
   const indices=part.posed.index.array;
   for(let i=0;i<indices.length;i+=3){const tri=[map[indices[i]],map[indices[i+1]],map[indices[i+2]]];for(let j=0;j<3;j++){vertices[tri[j]].neighbors.add(tri[(j+1)%3]);vertices[tri[j]].neighbors.add(tri[(j+2)%3]);}}
   maps.push(map);
 }
 const active=vertices.filter(v=>v.weight>0);for(const v of active)v.neighbors=[...v.neighbors];
 const deltas=active.map(()=>new THREE.Vector3());
 for(let iteration=0;iteration<100;iteration++)for(const factor of [.45,-.47]){
   active.forEach((v,i)=>{const d=deltas[i].set(0,0,0);for(const n of v.neighbors)d.add(vertices[n].position);d.multiplyScalar(1/v.neighbors.length).sub(v.position).multiplyScalar(factor*v.weight);});
   active.forEach((v,i)=>v.position.add(deltas[i]));
 }
 const edgeA=new THREE.Vector3(),edgeB=new THREE.Vector3();
 for(let k=0;k<parts.length;k++){
   const indices=parts[k].posed.index.array,map=maps[k];
   for(let i=0;i<indices.length;i+=3){const a=vertices[map[indices[i]]],b=vertices[map[indices[i+1]]],c=vertices[map[indices[i+2]]];
     const n=edgeA.subVectors(b.position,a.position).cross(edgeB.subVectors(c.position,a.position));a.normal.add(n);b.normal.add(n);c.normal.add(n);
   }
 }
 parts.forEach((part,k)=>{
   const p=part.posed.getAttribute('position'),n=part.posed.getAttribute('normal'),inverse=part.mesh.matrixWorld.clone().invert();
   const localNormal=new THREE.Matrix3().setFromMatrix4(part.mesh.matrixWorld).transpose();
   maps[k].forEach((j,i)=>{const v=vertices[j],point=v.position.clone().applyMatrix4(inverse);p.setXYZ(i,point.x,point.y,point.z);
     // Keep the existing hand/cuff shading; the rebuilt connection uses normals
     // from the final smoothed surface, including neighbors across material joins.
     if(v.weight>0){const normal=v.normal.clone().applyMatrix3(localNormal).normalize();n.setXYZ(i,normal.x,normal.y,normal.z);}
   });
   p.needsUpdate=true;n.needsUpdate=true;if(part.posed.getAttribute('uv'))part.posed.computeTangents();part.posed.computeBoundingBox();part.posed.computeBoundingSphere();
 });
}
const targets=new Set(['Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm','Gravebound_FP_L_Hand','Gravebound_FP_R_Hand']);
export function createPoseController(model) {
  const parts=[];model.updateMatrixWorld(true);
  for(const name of targets){const part=model.getObjectByName(name);if(!part)throw Error('T 자세에 필요한 부위가 없습니다: '+name);part.traverse(mesh=>{if(mesh.isMesh)parts.push({mesh,original:mesh.geometry,posed:null});});}
  let enabled=false,relaxed=false;
  return {
    get enabled(){return enabled;},
    setEnabled(value){
      if(value===enabled)return;
      for(const part of parts){
        if(value&&!part.posed){
          const {mesh,original}=part;const geometry=original.clone();
          const positions=geometry.getAttribute('position'), normals=geometry.getAttribute('normal');
          const world=mesh.matrixWorld.clone(), inverse=world.clone().invert();
          const normalWorld=new THREE.Matrix3().getNormalMatrix(world);
          const normalLocal=new THREE.Matrix3().setFromMatrix4(world).transpose();
          for(let i=0;i<positions.count;i++){
            const point=new THREE.Vector3().fromBufferAttribute(original.getAttribute('position'),i).applyMatrix4(world);
            const posed=posePoint(point).applyMatrix4(inverse);positions.setXYZ(i,posed.x,posed.y,posed.z);
            if(normals){
              const jacobian=poseJacobian(point);
              if(jacobian.determinant()<=.01)throw Error('T 자세 연결부에 잘못된 변형이 감지되었습니다: '+JSON.stringify({point:point.toArray(),det:jacobian.determinant()}));
              const normal=new THREE.Vector3().fromBufferAttribute(original.getAttribute('normal'),i).applyMatrix3(normalWorld).applyMatrix3(jacobian.invert().transpose()).applyMatrix3(normalLocal).normalize();
              normals.setXYZ(i,normal.x,normal.y,normal.z);
            }
          }
          positions.needsUpdate=true;if(normals)normals.needsUpdate=true;
          if(geometry.index&&geometry.getAttribute('uv')&&normals)geometry.computeTangents();
          geometry.computeBoundingBox();geometry.computeBoundingSphere();part.posed=geometry;
        }
      }
      if(value&&!relaxed){relaxShoulders(parts);relaxed=true;}
      for(const part of parts)part.mesh.geometry=value?part.posed:part.original;
      enabled=value;model.updateMatrixWorld(true);
    }
  };
}
