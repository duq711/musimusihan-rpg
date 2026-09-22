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
 assert.ok(Math.abs(pe.z)<.02&&Math.abs(pw.z)<.02,'elbow/wrist guides remain near the coronal T plane');
 assert.ok(Math.abs(Math.abs(pe.x-ps.x)-s.distanceTo(e))<.001&&Math.abs(Math.abs(pw.x-pe.x)-e.distanceTo(w))<.001,'limb lengths preserved');
}
const controller=createPoseController(model);controller.setEnabled(true);
const box=new THREE.Box3().setFromObject(model);assert.ok(box.getSize(new THREE.Vector3()).x>1.6,'both arms spread across the T-pose span');
let changed=0;
for(const [mesh,original] of originals){
 if(mesh.geometry!==original){changed++;for(const x of mesh.geometry.getAttribute('position').array)assert.ok(Number.isFinite(x));}
}
assert.equal(changed,9,'only torso, six sleeve surfaces and two hands change');

// Measure the rendered triangles, rather than sampling vertex rings or the
// corrective cage. Different vertex densities must not hide a swollen elbow,
// a second forearm bulge, or the rejected low shoulder/underarm silhouette.
const triangles=[];
for(const [mesh,original] of originals){
 if(mesh.geometry===original)continue;
 const geometry=mesh.geometry,p=geometry.getAttribute('position'),index=geometry.index;
 const world=Array.from({length:p.count},(_,i)=>new THREE.Vector3().fromBufferAttribute(p,i).applyMatrix4(mesh.matrixWorld));
 const count=index?index.count:p.count;
 for(let i=0;i<count;i+=3){
  const points=[0,1,2].map(j=>world[index?index.getX(i+j):i+j]);
  triangles.push({points,owner:mesh.parent.name,minX:Math.min(...points.map(p=>p.x)),maxX:Math.max(...points.map(p=>p.x))});
 }
}
function sectionAt(x,accept=()=>true){
 const cuts=[];
 for(const triangle of triangles){
  if(!accept(triangle))continue;
  const {points,minX,maxX}=triangle;
  if(x<minX||x>maxX)continue;
  for(let i=0;i<3;i++){
   const a=points[i],b=points[(i+1)%3],dx=b.x-a.x;
   if(Math.abs(dx)<1e-12){if(Math.abs(a.x-x)<1e-9)cuts.push(a,b);continue;}
   const t=(x-a.x)/dx;
   if(t>=0&&t<=1)cuts.push(a.clone().lerp(b,t));
  }
 }
 assert.ok(cuts.length>=6,`triangle section exists at x=${x.toFixed(3)}`);
 const lo=Math.min(...cuts.map(p=>p.y)),hi=Math.max(...cuts.map(p=>p.y));
 const front=Math.min(...cuts.map(p=>p.z)),back=Math.max(...cuts.map(p=>p.z));
 return {x,lo,hi,height:hi-lo,depth:back-front,cy:(hi+lo)/2};
}
const silhouetteFailures=[],silhouetteSummary=[];
const expect=(condition,message)=>{if(!condition)silhouetteFailures.push(message);};
const axisY=1.41868; // Approved raised arm axis, in metres.
for(const side of [-1,1]){
 const at=x=>sectionAt(side*x),label=side<0?'left':'right';
 const upper=at(.300),elbow=at(.435),proximal=at(.490),distal=at(.610);
 expect(elbow.height>=.055&&elbow.height<=.080,`${label}: elbow diameter must be 55–80 mm; actual ${(elbow.height*1000).toFixed(1)}`);
 expect(elbow.height<=upper.height*.88,`${label}: elbow must be visibly narrower than upper arm`);
 expect(upper.height>=.080&&upper.height<=.125,`${label}: upper arm must retain a rounded 80–125 mm sleeve volume`);
 expect(distal.height<=proximal.height*.85,`${label}: forearm must taper toward the wrist in front view`);
 expect(distal.depth<=proximal.depth*.90,`${label}: forearm must also taper in depth`);
 const forearm=Array.from({length:17},(_,i)=>at(.460+i*.010));
 const peak=forearm.reduce((best,s)=>s.height>best.height?s:best);
 expect(Math.abs(peak.x)<=.535,`${label}: forearm bulk must remain near the elbow`);
 let thinnest=Infinity;
 for(const s of forearm.filter(s=>Math.abs(s.x)>=Math.abs(peak.x))){
  thinnest=Math.min(thinnest,s.height);
  expect(s.height-thinnest<=.006,`${label}: forearm must not develop another bulge at x=${Math.abs(s.x).toFixed(3)}`);
 }
 for(const x of [.300,.350,.400,.450,.500,.550,.600]){
  const s=at(x);
  expect(Math.abs(s.cy-axisY)<=.018,`${label}: section centre deviates from the arm axis at x=${x.toFixed(3)}`);
 }
 for(const x of [.235,.250,.275]){
  const s=at(x);
  expect(s.lo>=axisY-.085,`${label}: a low axillary wing remains at x=${x.toFixed(3)}`);
  expect(s.hi>=axisY+.040&&s.hi<=axisY+.085,`${label}: shoulder cap is too low or inflated at x=${x.toFixed(3)}`);
 }
 // A deep groove between collar and deltoid is not a normal shoulder slope.
 // Use only the upper silhouette here: lower cuts legitimately cross the chest.
 const inner=at(.085),outer=at(.225);
 for(let x=.100;x<=.2101;x+=.010){
  const chord=THREE.MathUtils.lerp(inner.hi,outer.hi,(x-.085)/(.225-.085));
  expect(at(x).hi>=chord-.008,`${label}: collar-to-deltoid roof contains a groove at x=${x.toFixed(3)}`);
 }
 silhouetteSummary.push(`${label} upper/elbow/proximal/distal ${(upper.height*1000).toFixed(1)}/${(elbow.height*1000).toFixed(1)}/${(proximal.height*1000).toFixed(1)}/${(distal.height*1000).toFixed(1)} mm`);
}
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
// The sleeve can fold down and back up beside a perfectly coincident seam.
// Compare its inner underside to the actual shared torso attachment, excluding
// the legitimate chest surface that extends lower in these same X planes.
for(const side of [-1,1]){
 const armName=side<0?'Gravebound_FP_L_Arm':'Gravebound_FP_R_Arm',attachment=[];
 for(const entries of cells.values())for(const arm of entries){
  if(arm.mesh.parent.name!==armName)continue;
  const {after:p}=arm;
  if(Math.abs(p.x)<.16||Math.abs(p.x)>.21||p.y<1.25||p.y>1.43)continue;
  if(entries.some(torso=>torso.mesh.parent.name==='Gravebound_QuiltedTorso'&&torso.before.distanceTo(arm.before)<.000001))attachment.push(p);
 }
 assert.ok(attachment.length>=30,`${armName}: actual shared lower attachment is measured`);
 const seamFloor=Math.min(...attachment.map(p=>p.y));
 const pocketFloor=Math.min(...[.190,.200,.210].map(x=>sectionAt(side*x,t=>t.owner===armName).lo));
 const drop=seamFloor-pocketFloor;
 expect(drop<=.010,`${armName}: sleeve folds ${(drop*1000).toFixed(1)} mm below its shared attachment; limit 10 mm`);
 silhouetteSummary.push(`${side<0?'left':'right'} inner-root drop ${(drop*1000).toFixed(1)} mm`);
}
console.log('Triangle-section silhouette:',silhouetteSummary.join('; '));
assert.equal(silhouetteFailures.length,0,'Anatomy silhouette regressions:\n'+silhouetteFailures.join('\n'));
controller.setEnabled(false);for(const [mesh,original] of originals)assert.equal(mesh.geometry,original,'default pose returns exact original buffers');
controller.setEnabled(true);controller.setEnabled(false);for(const [mesh,original] of originals)assert.equal(mesh.geometry,original,'repeated toggles do not drift');
assert.equal(createHash('sha256').update(readFileSync(source)).digest('hex'),digest,'production GLB is unchanged');
console.log('T POSE PASS: actual GLB; horizontal arm guides, limb lengths, 9 posed surfaces, finite geometry, exact reset, production hash preserved; span',box.getSize(new THREE.Vector3()).x.toFixed(3),'m; shared boundary pairs',joins,'max gap mm',(maxGap*1000).toFixed(4));
