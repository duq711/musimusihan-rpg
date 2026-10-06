#!/usr/bin/env node
// Rasterize only authored SVG pose-control guides. Final generated dog images are never edited.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require('sharp');
const root = path.resolve(process.argv[2] || 'asset-staging/border-collie-run-imagegen-v2-20261006/guides');
const files = (await fs.readdir(root)).filter(f => f.endsWith('.svg')).sort();
for (const file of files) {
  await sharp(await fs.readFile(path.join(root,file))).png().toFile(path.join(root,file.replace(/\.svg$/,'.png')));
}
console.log(JSON.stringify({guide_pngs:files.length,root,final_dog_images_edited:0}));

