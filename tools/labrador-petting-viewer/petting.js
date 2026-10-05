import * as T from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const renderer = new T.WebGLRenderer({antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,2)); renderer.setSize(innerWidth,innerHeight);
renderer.outputColorSpace=T.SRGBColorSpace; renderer.toneMapping=T.ACESFilmicToneMapping; renderer.toneMappingExposure=1.1;
renderer.shadowMap.enabled=true; document.body.prepend(renderer.domElement);
const scene=new T.Scene(); scene.background=new T.Color('#ddd6cc');
const camera=new T.PerspectiveCamera(31,innerWidth/innerHeight,.01,30);
scene.add(new T.HemisphereLight(0xf3f7ff,0x7e6c53,2.0));
function light(color,power,position){const l=new T.DirectionalLight(color,power);l.position.set(...position);scene.add(l);return l;}
const key=light(0xfff1df,3.0,[2,4,3]);key.castShadow=true;key.shadow.mapSize.set(2048,2048);key.shadow.camera.left=-2;key.shadow.camera.right=2;key.shadow.camera.top=2;key.shadow.camera.bottom=-2;key.shadow.bias=-.0002;
light(0xdbedff,1.2,[-3,2,1]);light(0xffffff,1.7,[-1,3,-3]);
const floor=new T.Mesh(new T.PlaneGeometry(50,50),new T.MeshStandardMaterial({color:0xcac0b1,roughness:.92}));floor.rotation.x=-Math.PI/2;floor.receiveShadow=true;scene.add(floor);
const ray=new T.Raycaster(),mouse=new T.Vector2(),clock=new T.Clock(),q=new T.Quaternion(),axis=new T.Vector3();
const status=document.querySelector('#status'),fill=document.querySelector('#fill'),dot=document.querySelector('#dot');
let dog,head,mixer,actions={},bones=[],meshes=[],happy=0,strength=0,pressed=false,previous=null,hit=null,lean=new T.Vector2(),goal=new T.Vector2(),elapsed=0,close=true,needsFit=2;
const uniforms={origin:{value:new T.Vector3()},direction:{value:new T.Vector3()},strength:{value:0}};
function worldRotation(node,worldAxis,degrees){axis.copy(worldAxis).applyQuaternion(node.parent.getWorldQuaternion(q).invert());node.quaternion.premultiply(new T.Quaternion().setFromAxisAngle(axis,T.MathUtils.degToRad(degrees)));}
function fit(){if(!head)return;dog.updateMatrixWorld(true);let center=head.getWorldPosition(new T.Vector3());if(close){center.y-=.025;camera.position.copy(center).add(new T.Vector3(.26,.18,.70));}else{center=new T.Box3().setFromObject(dog).getCenter(center);camera.position.copy(center).add(new T.Vector3(1.1,.55,2.0));}camera.lookAt(center);camera.updateMatrixWorld();}
function coat(material){material.onBeforeCompile=s=>{s.uniforms.petOrigin=uniforms.origin;s.uniforms.petDirection=uniforms.direction;s.uniforms.petStrength=uniforms.strength;s.fragmentShader=s.fragmentShader.replace('#include <color_fragment>','');s.vertexShader=s.vertexShader.replace('#include <common>','#include <common>\nuniform vec3 petOrigin; uniform vec3 petDirection; uniform float petStrength;');s.vertexShader=s.vertexShader.replace('#include <skinning_vertex>',`#include <skinning_vertex>
vec3 pw=(modelMatrix*vec4(transformed,1.0)).xyz;
float pd=clamp(distance(pw,petOrigin)/0.065,0.0,1.0);
float pm=0.0;
#ifdef USE_COLOR
pm=color.r;
#endif
float pf=(1.0-pd*pd)*(1.0-pd*pd)*petStrength*pm;
transformed += mat3(inverse(modelMatrix))*petDirection*pf*0.0009;
`);};material.customProgramCacheKey=()=> 'labrador-petting-coat-v1';}
new GLTFLoader().load('/model.glb',g=>{dog=g.scene;scene.add(dog);mixer=new T.AnimationMixer(dog);dog.traverse(n=>{if(n.isBone)bones.push({node:n,rest:n.quaternion.clone()});if(n.isMesh){meshes.push(n);n.castShadow=true;n.frustumCulled=false;for(const m of [n.material].flat()){m.vertexColors=true;coat(m);}}});head=dog.getObjectByName('Head_1');if(!head)throw Error('실제 머리 리그가 없습니다.');for(const c of g.animations)actions[c.name]=mixer.clipAction(c);if(actions.PetEnjoy)actions.PetEnjoy.play();else if(actions.IdleFriendly)actions.IdleFriendly.play();else throw Error('쓰다듬기 모션을 찾지 못했습니다.');mixer.update(0);dog.updateMatrixWorld(true);fit();document.querySelector('#loading').hidden=true;},undefined,e=>{document.querySelector('#loading').textContent='모델을 불러오지 못했습니다. '+(e.message||e);});
function pick(x,y){if(!head)return null;mouse.set(x/innerWidth*2-1,-y/innerHeight*2+1);ray.setFromCamera(mouse,camera);const contact=ray.intersectObjects(meshes,false)[0];if(!contact)return null;if(contact.point.distanceTo(head.getWorldPosition(new T.Vector3()))>.16)return null;return contact.point;}
renderer.domElement.addEventListener('pointerdown',e=>{if(e.button!==0)return;pressed=true;previous=pick(e.clientX,e.clientY);renderer.domElement.setPointerCapture(e.pointerId);});
renderer.domElement.addEventListener('pointermove',e=>{hit=pick(e.clientX,e.clientY);dot.style.display=hit?'block':'none';dot.style.left=e.clientX+'px';dot.style.top=e.clientY+'px';if(pressed&&hit&&previous){const delta=hit.clone().sub(previous);const speed=Math.min(delta.length()/.018,1);strength=Math.max(strength,speed);happy=Math.min(1,happy+delta.length()*4.5);uniforms.origin.value.copy(hit);uniforms.direction.value.copy(delta).normalize();const local=dog.worldToLocal(hit.clone()),center=dog.worldToLocal(head.getWorldPosition(new T.Vector3()));goal.set(T.MathUtils.clamp((local.x-center.x)/.15,-1,1),T.MathUtils.clamp((local.z-center.z)/.15,-1,1));}previous=hit?.clone()||null;});
function release(){pressed=false;previous=null;goal.set(0,0);}for(const event of ['pointerup','pointercancel','lostpointercapture'])renderer.domElement.addEventListener(event,release);window.addEventListener('blur',release);
document.querySelector('#close').onclick=()=>{close=true;fit();};document.querySelector('#whole').onclick=()=>{close=false;fit();};document.querySelector('#reset').onclick=()=>{happy=strength=0;release();fit();};
addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
function frame(){requestAnimationFrame(frame);const dt=Math.min(clock.getDelta(),.04);elapsed+=dt;if(dog){for(const b of bones)b.node.quaternion.copy(b.rest);mixer.update(dt);strength=Math.max(0,strength-dt*2);if(!pressed)happy=Math.max(0,happy-dt*.045);lean.lerp(goal,1-Math.exp(-dt*9));const response=happy*.35+strength*.65;
worldRotation(dog.getObjectByName("Neck3_12")||head,new T.Vector3(0,1,0),lean.x*8*response);worldRotation(dog.getObjectByName("Neck3_12")||head,new T.Vector3(0,0,1),-lean.x*5*response);worldRotation(dog.getObjectByName("Neck3_12")||head,new T.Vector3(1,0,0),-lean.y*5*response);
for(const [side,sign] of [['L',1],['R',-1]]){const bias=1+sign*lean.x*.28;for(const [name,factor] of [['Ear1',1],['Ear2',.5],['Ear3',.18]]){const ear=bones.find(b=>b.node.name.replaceAll('.','').startsWith(name+side+'_'))?.node;if(ear){worldRotation(ear,new T.Vector3(1,0,0),Math.min(8,response*bias*8)*factor);worldRotation(ear,new T.Vector3(0,0,1),-sign*response*bias*3*factor);}}}
const tail=bones.find(b=>b.node.name.startsWith('Tail1_'))?.node;if(tail)worldRotation(tail,new T.Vector3(0,1,0),Math.sin(elapsed*(4+happy*6))*happy*12);
for(const mesh of meshes)if(mesh.morphTargetInfluences){const names=mesh.morphTargetDictionary||{};const blink=Math.pow(Math.max(0,Math.cos(elapsed*1.35)),28);for(const [name,index] of Object.entries(names))if(/target_1/.test(name))mesh.morphTargetInfluences[index]=Math.min(1,blink*(1-happy*.45)+happy*.45);}
uniforms.strength.value=strength;dog.updateMatrixWorld(true);if(needsFit>0){needsFit--;fit();}fill.style.width=Math.round(happy*100)+'%';status.textContent=pressed&&strength>.05?(happy>.5?'아, 기분 좋아요…':'좋아요, 계속 쓰다듬어 주세요'):happy>.3?'꼬리가 살랑살랑':'머리를 천천히 쓰다듬어 주세요';}renderer.render(scene,camera);}frame();
