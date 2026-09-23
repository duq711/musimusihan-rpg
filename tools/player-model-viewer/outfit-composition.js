// The supplied outfit replaces only the original clothing. The production
// head, eyes, hands and boots remain visible beside the new garment.
export const ORIGINAL_CLOTHING = new Set([
  'Gravebound_QuiltedTorso',
  'Gravebound_FP_L_Arm',
  'Gravebound_FP_R_Arm',
  'Gravebound_Trousers_L',
  'Gravebound_Trousers_R',
  'Gravebound_LeatherBelt',
  'Gravebound_BeltBuckle',
  'Gravebound_BeltTongue',
  'Gravebound_Pouch_L',
  'Gravebound_Pouch_R',
  'Gravebound_PouchFlap_L',
  'Gravebound_PouchFlap_R',
]);

export function showOutfit(original, outfit, dressed) {
  if (!outfit) return;
  outfit.visible = dressed;
  // The supplied asset also contains low shoes. Keep the existing tall boots
  // and their cuffs used by the game appearance.
  outfit.traverse(part => {
    if (part !== outfit && /boot|shoe/i.test(part.name)) part.visible = false;
  });
  for (const name of ORIGINAL_CLOTHING) {
    const part = original.getObjectByName(name);
    if (part) part.visible = !dressed;
  }
}
