import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
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
const center=new THREE.Vector3(0,.89,0);let outfit=null,outfitInfo=null,height=1.78,width=.72,ready=false;
function distanceForFit(){const vertical=THREE.MathUtils.degToRad(camera.fov)/2;const horizontal=Math.atan(Math.tan(vertical)*camera.aspect);return Math.max(height*.65/Math.tan(vertical),width*.70/Math.tan(horizontal));}
function setView(direction){if(!ready)return;controls.target.copy(center);camera.position.copy(center).add(new THREE.Vector3(...direction).normalize().multiplyScalar(distanceForFit()));controls.update();}
function reset(){setView([-.22,.05,-1]);}
document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>setView({front:[0,0,-1],back:[0,0,1],side:[-1,0,0]}[b.dataset.view])));
document.querySelector('#reset').addEventListener('click',reset);
function updateBounds(){
 const box=new THREE.Box3();
 for(const root of [outfit])if(root)root.traverseVisible(n=>{
  if(!n.isMesh)return;
  if(!n.geometry.boundingBox)n.geometry.computeBoundingBox();
  box.union(n.geometry.boundingBox.clone().applyMatrix4(n.matrixWorld));
 });
 if(box.isEmpty())return;
 box.getCenter(center);const size=box.getSize(new THREE.Vector3());height=size.y;width=Math.max(size.x,size.z);
}
document.querySelector('#spin').addEventListener('click',e=>{controls.autoRotate=!controls.autoRotate;e.currentTarget.setAttribute('aria-pressed',String(controls.autoRotate));});
document.querySelectorAll('[data-garment]').forEach(b=>b.addEventListener('click',()=>{if(!ready)return;const mesh=outfit.getObjectByName(b.dataset.garment);if(!mesh)return;const box=new THREE.Box3().setFromObject(mesh);box.getCenter(controls.target);const distance=Math.max(box.getSize(new THREE.Vector3()).length()*1.35,.6);camera.position.copy(controls.target).add(new THREE.Vector3(-.22,.12,-1).normalize().multiplyScalar(distance));controls.update();}));
const originalMaterials=new Map(),clay=new THREE.MeshStandardMaterial({color:0x9da4a5,roughness:.88,metalness:0});let shapeMode=false;
document.querySelector('#shape').addEventListener('click',e=>{if(!ready)return;shapeMode=!shapeMode;outfit.traverse(n=>{if(!n.isMesh)return;if(!originalMaterials.has(n))originalMaterials.set(n,n.material);n.material=shapeMode?clay:originalMaterials.get(n);});e.currentTarget.setAttribute('aria-pressed',String(shapeMode));});
addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
renderer.setAnimationLoop(()=>{controls.update();renderer.render(scene,camera);});
try{
 const response=await fetch('/outfit-info.json');if(!response.ok)throw Error('의상 정보를 읽지 못했습니다.');outfitInfo=await response.json();if(!outfitInfo.available)throw Error('의상 GLB 파일이 없습니다.');
 outfit=(await new GLTFLoader().loadAsync('/outfit.glb?v='+outfitInfo.modified,p=>{loading.textContent=p.total?`의상 불러오는 중… ${Math.round(p.loaded/p.total*100)}%`:'의상 불러오는 중…';})).scene;
 scene.add(outfit);outfit.updateMatrixWorld(true);updateBounds();
 const meshNames=[];outfit.traverse(n=>{if(n.isMesh)meshNames.push(n.name);});if(!meshNames.length)throw Error('표시할 의상 메시가 없습니다.');ready=true;reset();loading.hidden=true;status.textContent=`원본 의상 ${meshNames.length}개 메시 · 정적 원본 자세`;
 // Read-only diagnostics: only the production outfit GLB is loaded.
 window.playerViewer={outfit,camera,controls,renderer,outfitInfo,meshNames};
}catch(error){loading.textContent='의상을 불러오지 못했습니다. 새로고침해 주세요. '+error.message;status.textContent='불러오기 실패';console.error(error);}
