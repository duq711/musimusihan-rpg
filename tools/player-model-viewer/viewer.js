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
const center=new THREE.Vector3(0,.89,0);let model=null,height=1.78,width=.72,ready=false;
function distanceForFit(){const vertical=THREE.MathUtils.degToRad(camera.fov)/2;const horizontal=Math.atan(Math.tan(vertical)*camera.aspect);return Math.max(height*.65/Math.tan(vertical),width*.70/Math.tan(horizontal));}
function setView(direction){if(!ready)return;controls.target.copy(center);camera.position.copy(center).add(new THREE.Vector3(...direction).normalize().multiplyScalar(distanceForFit()));controls.update();}
function reset(){setView([-.22,.05,-1]);}
document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>setView({front:[0,0,-1],back:[0,0,1],side:[-1,0,0]}[b.dataset.view])));
document.querySelector('#reset').addEventListener('click',reset);
document.querySelector('#spin').addEventListener('click',e=>{controls.autoRotate=!controls.autoRotate;e.currentTarget.setAttribute('aria-pressed',String(controls.autoRotate));});
document.querySelector('#hand').addEventListener('click',()=>{if(!ready)return;const hand=model.getObjectByName('Gravebound_FP_L_Hand');if(!hand)return;const b=new THREE.Box3().setFromObject(hand);b.getCenter(controls.target);camera.position.copy(controls.target).add(new THREE.Vector3(-.34,.08,-.43));controls.update();});
function focusHood(offset){if(!ready)return;const hood=model.getObjectByName('Gravebound_PointHood');if(!hood)return;new THREE.Box3().setFromObject(hood).getCenter(controls.target);camera.position.copy(controls.target).add(new THREE.Vector3(...offset));controls.update();}
document.querySelector('#hood').addEventListener('click',()=>focusHood([-.28,.16,-.55]));
document.querySelector('#hood-top').addEventListener('click',()=>focusHood([0,.60,-.015]));
addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
renderer.setAnimationLoop(()=>{controls.update();renderer.render(scene,camera);});
try{
 const response=await fetch('/model-info.json');if(!response.ok)throw Error('모델 정보를 읽지 못했습니다.');const info=await response.json();
 const gltf=await new GLTFLoader().loadAsync('/model.glb?v='+info.modified,p=>{loading.textContent=p.total?`모델 불러오는 중… ${Math.round(p.loaded/p.total*100)}%`:'모델 불러오는 중…';});
 model=gltf.scene;scene.add(model);model.updateMatrixWorld(true);
 const box=new THREE.Box3().setFromObject(model);box.getCenter(center);const size=box.getSize(new THREE.Vector3());height=size.y;width=Math.max(size.x,size.z);
 let meshes=0;model.traverse(n=>{if(n.isMesh)meshes++;});ready=true;reset();loading.hidden=true;status.textContent='자유 회전 · 확대 · 이동';
 // Read-only diagnostics for checking that the viewer loaded the production model.
 window.playerViewer={model,camera,controls,renderer,info,meshCount:meshes};
}catch(error){loading.textContent='모델을 불러오지 못했습니다. 새로고침해 주세요. '+error.message;status.textContent='불러오기 실패';console.error(error);}
