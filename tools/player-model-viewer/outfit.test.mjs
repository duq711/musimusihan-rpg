import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Load the browser module without asking Node to change the project module type.
const source = readFileSync(new URL('./outfit-composition.js', import.meta.url), 'utf8');
const { ORIGINAL_CLOTHING, showOutfit } = await import('data:text/javascript,' + encodeURIComponent(source));
const glb = readFileSync(new URL('../../godot-game/assets/3d/player/gravebound_player.glb', import.meta.url));
const jsonLength = glb.readUInt32LE(12);
const productionNodes = new Set(JSON.parse(glb.subarray(20, 20 + jsonLength)).nodes.map(node => node.name));
for (const name of ORIGINAL_CLOTHING) assert.ok(productionNodes.has(name), `${name} is an actual production node`);
const names = [...ORIGINAL_CLOTHING, 'Gravebound_AnatomicalHead', 'Gravebound_Eyes',
  'Gravebound_FP_L_Hand', 'Gravebound_FP_R_Hand', 'Gravebound_Boot_L', 'Gravebound_Boot_R',
  'Gravebound_BootCuff_L', 'Gravebound_BootCuff_R'];
const parts = new Map(names.map(name => [name, { name, visible: true }]));
const original = { getObjectByName: name => parts.get(name) };
const garment = { name: 'Medival_ShirtUpper', visible: true };
const shoes = { name: 'Medival_Boots', visible: true };
const outfit = { visible: false, traverse: callback => [outfit, garment, shoes].forEach(callback) };

showOutfit(original, outfit, true);
assert.equal(outfit.visible, true);
assert.equal(garment.visible, true);
assert.equal(shoes.visible, false);
for (const name of ORIGINAL_CLOTHING) assert.equal(parts.get(name).visible, false, `${name} is replaced`);
for (const name of names.filter(name => !ORIGINAL_CLOTHING.has(name)))
  assert.equal(parts.get(name).visible, true, `${name} is preserved`);

showOutfit(original, outfit, false);
assert.equal(outfit.visible, false);
for (const name of names) assert.equal(parts.get(name).visible, true, `${name} returns in original T pose`);
console.log('OUTFIT COMPOSITION PASS: garment replaces only old clothing and original T pose restores it.');
