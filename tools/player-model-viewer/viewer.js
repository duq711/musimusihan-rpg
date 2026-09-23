import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { createPoseController } from './pose.js';
import { showOutfit } from './outfit-composition.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
const stage=document.querySelector('#stage'), loading=document.querySelector('#loading'), status=document.querySelector('#status');
const renderer=new THREE.WebGLRenderer({antialias:true,alpha:false});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setSize(innerWidth,innerHeight);
renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.05;
stage.append(renderer.domElement);
const scene=new THREE.Scene();scene.background=new THREE.Color('#181c1d');
const camera=new THREE.PerspectiveCamera(32,innerWidth/innerHeight,.01,100);
const controls=new OrbitControls(camera,renderer.domElement);controls.enableDamping=true;controls.dampingFactor=.09;controls.screenSpacePanning=true;controls.minDistance=.12;controls.maxDistance=9;controls.minPolarAngle=.005;controls.maxPolarAngle=Math.PI-.005;controls.autoRotateSpeed=.65;
scene.add(new THREE.HemisphereLight(0xc5d5df,0x696052,1.35));
function light(color,power,xyz){const l=new THREE.DirectionalLight(color,power);l.position.set(...xyz);scene.add(l);}
light(0xfff5e8,2.3,[-2,4,-4]);light(0xd3dbeb,.85,[3,2,-2]);light(0xe1e8df,1.25,[0,3,3]);
const center=new THREE.Vector3(0,.89,0);let model=null,outfit=null,outfitInfo=null,height=1.78,width=.72,ready=false,pose=null;
function distanceForFit(){const vertical=THREE.MathUtils.degToRad(camera.fov)/2;const horizontal=Math.atan(Math.tan(vertical)*camera.aspect);return Math.max(height*.65/Math.tan(vertical),width*.70/Math.tan(horizontal));}
function setView(direction){if(!ready)return;controls.target.copy(center);camera.position.copy(center).add(new THREE.Vector3(...direction).normalize().multiplyScalar(distanceForFit()));controls.update();}
function reset(){setView([-.22,.05,-1]);}
document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>setView({front:[0,0,-1],back:[0,0,1],side:[-1,0,0]}[b.dataset.view])));
document.querySelector('#reset').addEventListener('click',reset);
function updateBounds(){
 const box=new THREE.Box3();
 for(const root of [model,outfit])if(root)root.traverseVisible(n=>{
  if(!n.isMesh)return;
  if(!n.geometry.boundingBox)n.geometry.computeBoundingBox();
  box.union(n.geometry.boundingBox.clone().applyMatrix4(n.matrixWorld));
 });
 if(box.isEmpty())return;
 box.getCenter(center);const size=box.getSize(new THREE.Vector3());height=size.y;width=Math.max(size.x,size.z);
}
function setPose(enabled){
 if(!ready)return;
 pose.setEnabled(enabled);showOutfit(model,outfit,!enabled);
 document.querySelector('#tpose').setAttribute('aria-pressed',String(enabled));
 status.textContent=enabled?'원본 인체 T자 참고 자세 · 새 의상 미적용':outfit?'새 의상 정적 형태 · 이동 물리효과는 게임 F2 테스트룸에서 확인':'기존 모델 · 새 의상 파일 대기 중';
 updateBounds();setView([0,0,-1]);
}
document.querySelector('#tpose').addEventListener('click',()=>setPose(!pose.enabled));

document.querySelector('#spin').addEventListener('click',e=>{controls.autoRotate=!controls.autoRotate;e.currentTarget.setAttribute('aria-pressed',String(controls.autoRotate));});
document.querySelector('#hand').addEventListener('click',()=>{if(!ready)return;const hand=model.getObjectByName('Gravebound_FP_L_Hand');if(!hand)return;const b=new THREE.Box3().setFromObject(hand);b.getCenter(controls.target);camera.position.copy(controls.target).add(new THREE.Vector3(-.34,.08,-.43));controls.update();});
document.querySelector('#head').addEventListener('click',()=>{if(!ready)return;const head=model.getObjectByName('Gravebound_AnatomicalHead');if(!head)return;new THREE.Box3().setFromObject(head).getCenter(controls.target);camera.position.copy(controls.target).add(new THREE.Vector3(-.20,.10,-.60));controls.update();});
document.querySelector('#shoulder').addEventListener('click',()=>{if(!ready)return;controls.target.set(0,1.44,0);camera.position.set(-.65,2.08,.35);controls.update();});
function focusAxilla(){if(!ready)return;controls.target.set(-.185,1.345,0);camera.position.set(-.40,1.39,-.65);controls.update();}
document.querySelector('#axilla').addEventListener('click',focusAxilla);
document.querySelector('#upper').addEventListener('click',()=>{if(!ready)return;controls.target.set(0,1.43,0);camera.position.set(-.42,1.64,-1.38);controls.update();});
const originalMaterials=new Map(),clay=new THREE.MeshStandardMaterial({color:0x9da4a5,roughness:.88,metalness:0});let shapeMode=false;
document.querySelector('#shape').addEventListener('click',e=>{if(!ready)return;shapeMode=!shapeMode;for(const root of [model,outfit])if(root)root.traverse(n=>{if(!n.isMesh)return;if(!originalMaterials.has(n))originalMaterials.set(n,n.material);n.material=shapeMode?clay:originalMaterials.get(n);});e.currentTarget.setAttribute('aria-pressed',String(shapeMode));});
addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
renderer.setAnimationLoop(()=>{controls.update();renderer.render(scene,camera);});
try{
 const response=await fetch('/model-info.json');if(!response.ok)throw Error('모델 정보를 읽지 못했습니다.');const info=await response.json();
 const gltf=await new GLTFLoader().loadAsync('/model.glb?v='+info.modified,p=>{loading.textContent=p.total?`모델 불러오는 중… ${Math.round(p.loaded/p.total*100)}%`:'모델 불러오는 중…';});
 model=gltf.scene;scene.add(model);model.updateMatrixWorld(true);
 let outfitError='';
 try{
  const outfitResponse=await fetch('/outfit-info.json');if(!outfitResponse.ok)throw Error('의상 정보를 읽지 못했습니다.');
  outfitInfo=await outfitResponse.json();
  if(outfitInfo.available){
   loading.textContent='새 의상 불러오는 중…';
   outfit=(await new GLTFLoader().loadAsync('/outfit.glb?v='+outfitInfo.modified)).scene;
   scene.add(outfit);outfit.updateMatrixWorld(true);showOutfit(model,outfit,true);
  }
 }catch(error){outfitError=error.message;console.error('Outfit preview:',error);}
 pose=createPoseController(model);updateBounds();
 let meshes=0;for(const root of [model,outfit])if(root)root.traverse(n=>{if(n.isMesh)meshes++;});ready=true;reset();if(new URLSearchParams(location.search).get("pose")==="t")setPose(true);if(new URLSearchParams(location.search).get("view")==="axilla")focusAxilla();loading.hidden=true;if(!pose.enabled)status.textContent=outfit?'새 의상 정적 형태 · 이동 물리효과는 게임 F2 테스트룸에서 확인':outfitError?'새 의상 로드 실패: '+outfitError:'기존 모델 · 새 의상 파일 대기 중';
 // Read-only diagnostics for checking that the viewer loaded the production model.
 window.playerViewer={model,outfit,camera,controls,renderer,info,outfitInfo,pose,meshCount:meshes};
}catch(error){loading.textContent='모델을 불러오지 못했습니다. 새로고침해 주세요. '+error.message;status.textContent='불러오기 실패';console.error(error);}
