import * as THREE from './vendor/build/three.module.js';

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
export function posePoint(point) {
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
export function poseJacobian(point) {
  const columns=[];
  for(let axis=0;axis<3;axis++){
    const h=new THREE.Vector3();h.setComponent(axis,.00002);
    columns.push(posePoint(point.clone().add(h)).sub(posePoint(point.clone().sub(h))).multiplyScalar(25000));
  }
  return new THREE.Matrix3().set(columns[0].x,columns[1].x,columns[2].x,columns[0].y,columns[1].y,columns[2].y,columns[0].z,columns[1].z,columns[2].z);
}
const targets=new Set(['Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm','Gravebound_FP_L_Hand','Gravebound_FP_R_Hand']);
export function createPoseController(model) {
  const parts=[];model.updateMatrixWorld(true);
  for(const name of targets){const part=model.getObjectByName(name);if(!part)throw Error('T 자세에 필요한 부위가 없습니다: '+name);part.traverse(mesh=>{if(mesh.isMesh)parts.push({mesh,original:mesh.geometry,posed:null});});}
  let enabled=false;
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
      for(const part of parts)part.mesh.geometry=value?part.posed:part.original;
      enabled=value;model.updateMatrixWorld(true);
    }
  };
}
