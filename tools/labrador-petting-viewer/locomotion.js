import * as T from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';

const renderer=new T.WebGLRenderer({antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setSize(innerWidth,innerHeight);
renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.1;
renderer.shadowMap.enabled=true;document.body.prepend(renderer.domElement);
const scene=new T.Scene();scene.background=new T.Color('#ddd6cc');
const camera=new T.PerspectiveCamera(32,innerWidth/innerHeight,.01,50);
scene.add(new T.HemisphereLight(0xf3f7ff,0x7e6c53,2));
function light(color,power,position){const l=new T.DirectionalLight(color,power);l.position.set(...position);scene.add(l);return l;}
const key=light(0xfff1df,3,[2,4,3]);key.castShadow=true;key.shadow.mapSize.set(2048,2048);Object.assign(key.shadow.camera,{left:-2,right:2,top:2,bottom:-2});key.shadow.bias=-.0002;
light(0xdbedff,1.2,[-3,2,1]);light(0xffffff,1.7,[-1,3,-3]);
const floor=new T.Mesh(new T.PlaneGeometry(40,40),new T.MeshStandardMaterial({color:0xcac0b1,roughness:.92}));floor.rotation.x=-Math.PI/2;floor.receiveShadow=true;scene.add(floor);
const grid=new T.GridHelper(40,160,0xb9ad9c,0xb9ad9c);grid.position.y=.0005;grid.material.transparent=true;grid.material.opacity=.28;scene.add(grid);
const clock=new T.Clock(),seek=document.querySelector('#seek'),status=document.querySelector('#status'),description=document.querySelector('#description');
let dog,mixer,clips={},metadata={},active,mode='Run',view='side',paused=false,movingGround=true,time=0,travel=0,playbackRate=1;
function fit(){if(!dog)return;const center=new T.Box3().setFromObject(dog).getCenter(new T.Vector3());center.y=.43;const widthFactor=Math.max(1,1.4/camera.aspect);camera.position.copy(center).add(view==='side'?new T.Vector3(2.35*widthFactor,.40,.06):new T.Vector3(1.7*widthFactor,.58,2.1*widthFactor));camera.lookAt(center);camera.updateMatrixWorld(true);}
function selected(id,yes){document.querySelector('#'+id).setAttribute('aria-pressed',String(yes));}
function speed(){return metadata[mode]?.speed_m_s??metadata[mode]?.nominal_speed_m_s??0;}
function describe(){description.textContent=(mode==='Walk'?'걷기':'달리기')+' · '+speed().toFixed(2)+' m/s · '+(playbackRate===1?'보통 속도':'0.5배속')+' · '+(movingGround?'발을 따라 움직이는 바닥':'제자리에서 모션 확인');}
function showTime(){if(!active)return;seek.value=Math.round(time/active.getClip().duration*1000);status.textContent=time.toFixed(2)+' / '+active.getClip().duration.toFixed(2)+'초';}
function setMode(name){if(!clips[name])return;mixer.stopAllAction();mode=name;active=clips[name];active.reset().setLoop(T.LoopRepeat,Infinity).play();time=travel=0;mixer.update(0);dog.updateMatrixWorld(true);selected('walk',name==='Walk');selected('run',name==='Run');describe();showTime();}
async function load(){try{const manifest=await fetch('/locomotion-manifest.json').then(r=>{if(!r.ok)throw Error('모션 정보가 없습니다.');return r.json();});metadata=Object.fromEntries(manifest.clips.map(c=>[c.name,c]));const g=await new GLTFLoader().loadAsync('/locomotion.glb');dog=g.scene;scene.add(dog);dog.traverse(n=>{if(n.isMesh){n.castShadow=true;n.frustumCulled=false;for(const m of [n.material].flat())m.vertexColors=false;}});mixer=new T.AnimationMixer(dog);mixer.timeScale=playbackRate;for(const c of g.animations)clips[c.name]=mixer.clipAction(c);if(!clips.Walk||!clips.Run)throw Error('걷기와 달리기 모션을 찾지 못했습니다.');setMode('Run');fit();document.querySelector('#loading').hidden=true;}catch(e){document.querySelector('#loading').textContent='모션을 불러오지 못했습니다. '+e.message;}}
document.querySelector('#walk').onclick=()=>setMode('Walk');document.querySelector('#run').onclick=()=>setMode('Run');
function setRate(rate){playbackRate=rate;if(mixer)mixer.timeScale=rate;selected('normal',rate===1);selected('slow',rate===.5);describe();}
document.querySelector('#normal').onclick=()=>setRate(1);document.querySelector('#slow').onclick=()=>setRate(.5);
document.querySelector('#pause').onclick=()=>{paused=!paused;document.querySelector('#pause').textContent=paused?'이어보기':'일시정지';};
document.querySelector('#side').onclick=()=>{view='side';selected('side',true);selected('quarter',false);fit();};document.querySelector('#quarter').onclick=()=>{view='quarter';selected('side',false);selected('quarter',true);fit();};
document.querySelector('#ground').onclick=()=>{movingGround=!movingGround;selected('ground',movingGround);grid.position.z=movingGround?-travel%.25:0;describe();};
seek.oninput=()=>{if(!active)return;time=Number(seek.value)/1000*active.getClip().duration;active.time=time;mixer.update(0);travel=speed()*time;grid.position.z=movingGround?-travel%.25:0;showTime();};
addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);fit();});
function frame(){requestAnimationFrame(frame);const dt=Math.min(clock.getDelta(),.04);if(active&&!paused){mixer.update(dt);time=active.time;travel+=speed()*dt*playbackRate;grid.position.z=movingGround?-travel%.25:0;showTime();}renderer.render(scene,camera);}load();frame();
