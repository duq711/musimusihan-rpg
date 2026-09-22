import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import * as THREE from './vendor/build/three.module.js';
import {createPoseController,posePoint} from './pose.js';
const source=new URL('../../godot-game/assets/3d/player/gravebound_player.glb',import.meta.url);
const glb=readFileSync(source),digest=createHash('sha256').update(glb).digest('hex');
const jsonSize=glb.readUInt32LE(12),doc=JSON.parse(glb.subarray(20,20+jsonSize));
const bin=glb.subarray(28+jsonSize);const view=new DataView(bin.buffer,bin.byteOffset,bin.byteLength);
function attribute(index){
 const a=doc.accessors[index],v=doc.bufferViews[a.bufferView],size={SCALAR:1,VEC2:2,VEC3:3,VEC4:4}[a.type];
 const [bytes,method,Ctor]={5126:[4,'getFloat32',Float32Array],5125:[4,'getUint32',Uint32Array],5123:[2,'getUint16',Uint16Array],5121:[1,'getUint8',Uint8Array]}[a.componentType];
 const result=new Ctor(a.count*size),stride=v.byteStride||size*bytes,start=(v.byteOffset||0)+(a.byteOffset||0);
 for(let i=0;i<a.count;i++)for(let j=0;j<size;j++)result[i*size+j]=view[method](start+i*stride+j*bytes,true);
 return new THREE.BufferAttribute(result,size);
}
const nodes=doc.nodes.map(n=>{
 const node=new THREE.Group();node.name=n.name||'';
 if(n.matrix){node.matrix.fromArray(n.matrix);node.matrix.decompose(node.position,node.quaternion,node.scale);}
 else {if(n.translation)node.position.fromArray(n.translation);if(n.rotation)node.quaternion.fromArray(n.rotation);if(n.scale)node.scale.fromArray(n.scale);}
 if(n.mesh!==undefined)for(const primitive of doc.meshes[n.mesh].primitives){
  const geometry=new THREE.BufferGeometry();
  for(const [gltf,three] of [['POSITION','position'],['NORMAL','normal'],['TEXCOORD_0','uv'],['TANGENT','tangent']])if(primitive.attributes[gltf]!==undefined)geometry.setAttribute(three,attribute(primitive.attributes[gltf]));
  if(primitive.indices!==undefined)geometry.setIndex(attribute(primitive.indices));node.add(new THREE.Mesh(geometry));
 }
 return node;
});
doc.nodes.forEach((n,i)=>(n.children||[]).forEach(c=>nodes[i].add(nodes[c])));
const model=new THREE.Group();doc.scenes[doc.scene||0].nodes.forEach(i=>model.add(nodes[i]));model.updateMatrixWorld(true);
const originals=new Map();model.traverse(n=>{if(n.isMesh)originals.set(n,n.geometry);});
for(const side of [-1,1]){
 const s=new THREE.Vector3(side*.205,1.37368,-.0046),e=new THREE.Vector3(side*.278,1.15793,-.014),w=new THREE.Vector3(side*.369494,.930478,-.07538);
 const ps=posePoint(s),pe=posePoint(e),pw=posePoint(w);
 assert.ok(Math.abs(pe.y-ps.y)<.003&&Math.abs(pw.y-ps.y)<.003,'elbow/wrist lie on the shoulder-height T axis');
 assert.ok(Math.abs(ps.distanceTo(pe)-s.distanceTo(e))<.001&&Math.abs(pe.distanceTo(pw)-e.distanceTo(w))<.001,'limb lengths preserved');
}
const controller=createPoseController(model);controller.setEnabled(true);
const box=new THREE.Box3().setFromObject(model);assert.ok(box.getSize(new THREE.Vector3()).x>1.6,'both arms spread across the T-pose span');
let changed=0;
for(const [mesh,original] of originals){
 if(mesh.geometry!==original){changed++;for(const x of mesh.geometry.getAttribute('position').array)assert.ok(Number.isFinite(x));}
}
assert.equal(changed,9,'only torso, six sleeve surfaces and two hands change');
// Compare coincident imported vertices across independently exported surfaces.
const cells=new Map();let joins=0,maxGap=0;
for(const [mesh,original] of originals){
 if(mesh.geometry===original)continue;
 const p=original.getAttribute('position'),q=mesh.geometry.getAttribute('position');
 for(let i=0;i<p.count;i++){
  const before=new THREE.Vector3().fromBufferAttribute(p,i).applyMatrix4(mesh.matrixWorld);
  const after=new THREE.Vector3().fromBufferAttribute(q,i).applyMatrix4(mesh.matrixWorld);
  const key=before.toArray().map(v=>Math.round(v*100000)).join(',');
  const previous=cells.get(key)||[];
  for(const entry of previous)if(entry.mesh!==mesh&&entry.before.distanceTo(before)<.000001){joins++;maxGap=Math.max(maxGap,entry.after.distanceTo(after));}
  previous.push({mesh,before,after});cells.set(key,previous);
 }
}
assert.ok(joins>400&&maxGap<.00002,'shared shoulder, sleeve-material and wrist boundaries stay joined');
controller.setEnabled(false);for(const [mesh,original] of originals)assert.equal(mesh.geometry,original,'default pose returns exact original buffers');
controller.setEnabled(true);controller.setEnabled(false);for(const [mesh,original] of originals)assert.equal(mesh.geometry,original,'repeated toggles do not drift');
assert.equal(createHash('sha256').update(readFileSync(source)).digest('hex'),digest,'production GLB is unchanged');
console.log('T POSE PASS: actual GLB; horizontal arm guides, limb lengths, 9 posed surfaces, finite geometry, exact reset, production hash preserved; span',box.getSize(new THREE.Vector3()).x.toFixed(3),'m; shared boundary pairs',joins,'max gap mm',(maxGap*1000).toFixed(4));
