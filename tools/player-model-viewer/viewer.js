import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const stage = document.querySelector('#stage');
const loading = document.querySelector('#loading');
const status = document.querySelector('#status');
const outfitButton = document.querySelector('#outfit-only');
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
stage.append(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color('#181c1d');
const camera = new THREE.PerspectiveCamera(32, innerWidth / innerHeight, .01, 100);
const controls = new OrbitControls(camera, renderer.domElement);
Object.assign(controls, {
  enableDamping: true, dampingFactor: .09, screenSpacePanning: true,
  minDistance: .12, maxDistance: 9, minPolarAngle: .005,
  maxPolarAngle: Math.PI - .005, autoRotateSpeed: .65,
});
scene.add(new THREE.HemisphereLight(0xc5d5df, 0x696052, 1.35));
function light(color, power, xyz) {
  const source = new THREE.DirectionalLight(color, power);
  source.position.set(...xyz);
  scene.add(source);
}
light(0xfff5e8, 2.3, [-2, 4, -4]);
light(0xd3dbeb, .85, [3, 2, -2]);
light(0xe1e8df, 1.25, [0, 3, 3]);

let model = null, modelInfo = null, ready = false, shapeMode = false, outfitOnly = false;
const bodyMeshes = [], garmentMeshes = [], originalMaterials = new Map();
const bodyParts = new Map(), garmentParts = new Map();
let focusedPartNames = [];
const garmentNames = new Set([
  'Medival_ShirtUpper', 'Medival_Pants', 'Medival_Belt', 'Medival_Shoe_L', 'Medival_Shoe_R',
]);
const clay = new THREE.MeshStandardMaterial({ color: 0x9da4a5, roughness: .88, metalness: 0 });
const bounds = new THREE.Box3();

function namedPart(mesh, matches) {
  // GLTFLoader makes a named Group for a node with multiple materials; its
  // actual meshes retain source names such as CC_Base_Body002_0.
  for (let node = mesh; node && node !== model; node = node.parent) {
    if (matches(node.name)) return node.name;
  }
  return null;
}
function meshBounds(meshes) {
  const box = new THREE.Box3();
  for (const mesh of meshes) box.union(new THREE.Box3().setFromObject(mesh));
  return box;
}
function visibleBounds() {
  const meshes = [];
  model.traverseVisible(node => { if (node.isMesh) meshes.push(node); });
  return meshBounds(meshes);
}
function fit(box, direction = [-.22, .05, -1], padding = 1.35) {
  if (box.isEmpty()) return;
  const size = box.getSize(new THREE.Vector3());
  box.getCenter(controls.target);
  const vertical = THREE.MathUtils.degToRad(camera.fov) / 2;
  const horizontal = Math.atan(Math.tan(vertical) * camera.aspect);
  const distance = Math.max(size.y / 2 / Math.tan(vertical),
    Math.max(size.x, size.z) / 2 / Math.tan(horizontal)) * padding + size.z / 2;
  camera.position.copy(controls.target).add(new THREE.Vector3(...direction).normalize()
    .multiplyScalar(Math.max(distance, .25)));
  controls.update();
}
function setView(direction) {
  if (!ready) return;
  focusedPartNames = [];
  fit(visibleBounds(), direction);
}
function reset() { setView([-.22, .05, -1]); }
document.querySelectorAll('[data-view]').forEach(button => {
  button.addEventListener('click', () => setView({
    front: [0, 0, -1], back: [0, 0, 1], side: [-1, 0, 0],
  }[button.dataset.view]));
});
document.querySelector('#reset').addEventListener('click', reset);

function focusBody(part) {
  if (!ready || outfitOnly || !bodyMeshes.length) return;
  const expression = part === 'head'
    ? /head|face|hair|eye|teeth|tongue|chin|mustache|soul_path|stubble/i : /hand/i;
  let matches = bodyMeshes.filter(mesh => expression.test(bodyParts.get(mesh)));
  let box = meshBounds(matches);
  if (part === 'hands' && !box.isEmpty()) {
    const size = box.getSize(new THREE.Vector3());
    const rightHand = matches.filter(mesh => bodyParts.get(mesh) === 'Roger_Hand_R');
    if (size.x > size.y * 2.5 && rightHand.length) {
      matches = rightHand;
      box = meshBounds(matches);
    }
  }
  focusedPartNames = [...new Set(matches.map(mesh => bodyParts.get(mesh)))];
  if (box.isEmpty()) {
    // Some exports keep Roger as one mesh. Y-up bounds provide useful focus
    // regions without changing the supplied model.
    box = meshBounds(bodyMeshes);
    const size = box.getSize(new THREE.Vector3());
    const midpoint = box.getCenter(new THREE.Vector3());
    if (part === 'head') {
      box.min.y = box.max.y - size.y * .24;
      box.min.x = midpoint.x - size.y * .15;
      box.max.x = midpoint.x + size.y * .15;
    } else {
      box.min.y += size.y * .33;
      box.max.y = box.min.y + size.y * .3;
    }
  }
  fit(box, part === 'head' ? [-.14, .02, -1] : [-.12, .12, -1], 1.3);
}
document.querySelectorAll('[data-focus]').forEach(button => {
  button.addEventListener('click', () => focusBody(button.dataset.focus));
});
function updateBodyButtons() {
  document.querySelectorAll('[data-focus]').forEach(button => {
    button.disabled = !bodyMeshes.length || outfitOnly;
    button.title = !bodyMeshes.length ? 'Roger 모델이 있을 때 사용할 수 있습니다.'
      : outfitOnly ? '의상만 보기를 끄면 사용할 수 있습니다.' : '';
  });
}
function updateStatus() {
  status.textContent = modelInfo.kind === 'roger-medival'
    ? `Roger · 원본 Medival 의상 · 피팅된 정적 미리보기${outfitOnly ? ' · 의상만 표시' : ''}`
    : '원본 Medival 의상 5개 · 정적 원본 자세 · Roger 로컬 파일 없음';
  status.title = `${modelInfo.name}\n${modelInfo.origin}\nSHA-256: ${modelInfo.sha256}`;
}
outfitButton.addEventListener('click', () => {
  if (!ready || !bodyMeshes.length) return;
  outfitOnly = !outfitOnly;
  for (const mesh of bodyMeshes) mesh.visible = !outfitOnly;
  outfitButton.setAttribute('aria-pressed', String(outfitOnly));
  updateBodyButtons();
  updateStatus();
  reset();
});
document.querySelector('#shape').addEventListener('click', event => {
  if (!ready) return;
  shapeMode = !shapeMode;
  model.traverse(node => {
    if (!node.isMesh) return;
    node.material = shapeMode ? clay : originalMaterials.get(node);
  });
  event.currentTarget.setAttribute('aria-pressed', String(shapeMode));
});
document.querySelector('#spin').addEventListener('click', event => {
  controls.autoRotate = !controls.autoRotate;
  event.currentTarget.setAttribute('aria-pressed', String(controls.autoRotate));
});
addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});
renderer.setAnimationLoop(() => { controls.update(); renderer.render(scene, camera); });

try {
  const response = await fetch('/model-info.json');
  if (!response.ok) throw Error('모델 정보를 읽지 못했습니다.');
  modelInfo = await response.json();
  if (!modelInfo.available) throw Error('Roger 결합 모델과 Medival 의상 GLB 파일이 없습니다.');
  model = (await new GLTFLoader().loadAsync(`${modelInfo.url}?v=${modelInfo.modified}`, progress => {
    loading.textContent = progress.total
      ? `모델 불러오는 중… ${Math.round(progress.loaded / progress.total * 100)}%`
      : '모델 불러오는 중…';
  })).scene;
  scene.add(model);
  model.updateMatrixWorld(true);
  const meshNames = [];
  model.traverse(node => {
    if (!node.isMesh) return;
    meshNames.push(node.name);
    originalMaterials.set(node, node.material);
    const bodyPart = namedPart(node, name => name.startsWith('Roger_'));
    const garmentPart = namedPart(node, name => garmentNames.has(name));
    if (bodyPart) { bodyMeshes.push(node); bodyParts.set(node, bodyPart); }
    if (garmentPart) { garmentMeshes.push(node); garmentParts.set(node, garmentPart); }
  });
  if (!meshNames.length) throw Error('표시할 메시가 없습니다.');
  bounds.copy(visibleBounds());
  ready = true;
  outfitOnly = !bodyMeshes.length;
  outfitButton.disabled = !bodyMeshes.length;
  outfitButton.setAttribute('aria-pressed', String(outfitOnly));
  updateBodyButtons();
  document.querySelector('h1').textContent = modelInfo.kind === 'roger-medival'
    ? 'Roger + Medival · 360°' : '원본 Medival 의상 · 360°';
  document.title = document.querySelector('h1').textContent;
  stage.setAttribute('aria-label', `${modelInfo.name}, 드래그로 회전하는 3D 모델`);
  reset();
  loading.hidden = true;
  updateStatus();
  // Read-only review diagnostics expose the loaded source and expected names.
  window.playerViewer = {
    model, outfit: model, camera, controls, renderer, modelInfo, meshNames, bounds,
    bodyMeshNames: bodyMeshes.map(mesh => mesh.name),
    garmentMeshNames: garmentMeshes.map(mesh => mesh.name),
    bodyPartNames: [...new Set(bodyParts.values())],
    garmentPartNames: [...new Set(garmentParts.values())],
    meshParts: [...bodyMeshes, ...garmentMeshes].map(mesh => ({
      meshName: mesh.name, bodyPart: bodyParts.get(mesh) ?? null,
      garmentPart: garmentParts.get(mesh) ?? null,
    })),
    missingGarmentNames: [...garmentNames].filter(name => ![...garmentParts.values()].includes(name)),
    previewMode: modelInfo.preview,
    get focusedPartNames() { return focusedPartNames; },
    get outfitOnly() { return outfitOnly; },
    get shapeMode() { return shapeMode; },
  };
} catch (error) {
  loading.textContent = '모델을 불러오지 못했습니다. 새로고침해 주세요. ' + error.message;
  status.textContent = '불러오기 실패';
  console.error(error);
}
