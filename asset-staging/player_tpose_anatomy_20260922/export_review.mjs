// Bake the exact viewer correction into a separate, textured review asset.
import {readFileSync} from 'node:fs';
import * as THREE from '../../tools/player-model-viewer/vendor/build/three.module.js';
import {createPoseController} from '../../tools/player-model-viewer/pose.js';
const source=new URL('../../godot-game/assets/3d/player/gravebound_player.glb',import.meta.url);
const glb=readFileSync(source);
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

const controller=createPoseController(model);controller.setEnabled(true);
for(let ni=0;ni<doc.nodes.length;ni++){let n=doc.nodes[ni];if(n.mesh===undefined)continue;const meshes=nodes[ni].children.filter(c=>c.isMesh);doc.meshes[n.mesh].primitives.forEach((primitive,pi)=>{
 const geo=meshes[pi].geometry;for(const [gltf,three] of [['POSITION','position'],['NORMAL','normal'],['TANGENT','tangent']]){
  if(primitive.attributes[gltf]===undefined||!geo.getAttribute(three))continue;
  const a=doc.accessors[primitive.attributes[gltf]],v=doc.bufferViews[a.bufferView],attr=geo.getAttribute(three),stride=v.byteStride||attr.itemSize*4,start=(v.byteOffset||0)+(a.byteOffset||0);
  for(let i=0;i<a.count;i++)for(let j=0;j<attr.itemSize;j++)view.setFloat32(start+i*stride+j*4,attr.array[i*attr.itemSize+j],true);
  if(gltf==='POSITION'){geo.computeBoundingBox();a.min=geo.boundingBox.min.toArray();a.max=geo.boundingBox.max.toArray();}
 }
});}
const raw=Buffer.from(JSON.stringify(doc));const jsonLength=Math.ceil(raw.length/4)*4;const jsonBytes=Buffer.alloc(jsonLength,32);raw.copy(jsonBytes);const result=Buffer.alloc(28+jsonLength+bin.length);result.writeUInt32LE(0x46546c67,0);result.writeUInt32LE(2,4);result.writeUInt32LE(result.length,8);result.writeUInt32LE(jsonLength,12);result.writeUInt32LE(0x4e4f534a,16);jsonBytes.copy(result,20);result.writeUInt32LE(bin.length,20+jsonLength);result.writeUInt32LE(0x004e4942,24+jsonLength);bin.copy(result,28+jsonLength);
const {writeFileSync}=await import('node:fs');writeFileSync(process.argv[2],result);console.log('Exported review T-pose:',process.argv[2],result.length);
