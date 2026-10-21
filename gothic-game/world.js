import * as T from 'three';

// Authored geometry and a shared ink/pigment material. No photographic maps,
// inherited PBR materials, postprocess conversion, or imported old scene meshes.
export const PALETTE = {
  stone: 0x657576,
  edge: 0x929e91,
  dark: 0x23333e,
  ink: 0x141d27,
  floor: 0x566468,
  wood: 0x77594a,
  woodLight: 0xa3835c,
  iron: 0x394750,
  gold: 0xbc9655,
  red: 0x763d40,
  paper: 0xc1b18a,
  bone: 0xb2b6a0,
  moss: 0x405b53
};
export const CELL = 1.08;
const v = new T.Vector3(),
  q = new T.Quaternion(),
  s = new T.Vector3(),
  matrix = new T.Matrix4(),
  normalMatrix = new T.Matrix3();
const boxes = new T.BoxGeometry(1, 1, 1).toNonIndexed();
const cylinders = new Map();
export const noise = (x, z = 0) => {
  const a = Math.sin(x * 127.1 + z * 311.7) * 43758.5453;
  return a - Math.floor(a);
};
const color = new T.Color();
export function material() {
  return new T.ShaderMaterial({
    vertexColors: true,
    uniforms: {
      eye: {
        value: new T.Vector3()
      },
      torch: {
        value: new T.Vector3()
      },
      lamps: {
        value: Array.from({
          length: 4
        }, () => new T.Vector3())
      },
      clock: {
        value: 0
      },
      warmth: {
        value: .65
      }
    },
    vertexShader: `
    varying vec3 p; varying vec3 n; varying vec3 pigment;
    void main(){vec4 wp=modelMatrix*vec4(position,1.);p=wp.xyz;n=normalize(mat3(modelMatrix)*normal);pigment=color;gl_Position=projectionMatrix*viewMatrix*wp;}
  `,
    fragmentShader: `
    uniform vec3 eye; uniform vec3 torch; uniform vec3 lamps[4]; uniform float clock; uniform float warmth;
    varying vec3 p; varying vec3 n; varying vec3 pigment;
    void main(){
      vec3 normal=normalize(n); float d=distance(p,eye); float td=distance(p,torch);
      float key=max(0.,dot(normal,normalize(vec3(-.55,1.,.35))));
      float bands=key<.13?.11:(key<.59?.43:.85);
      float low=1.-smoothstep(.0,1.9,p.y); bands*=1.-low*.23;
      float warm=exp(-td*.37)*max(.0,dot(normal,normalize(torch-p)))*warmth;
      for(int i=0;i<4;i++){float ld=distance(p,lamps[i]);warm+=exp(-ld*.46)*max(.1,dot(normal,normalize(lamps[i]-p)))*1.4;}
      float brush=sin(p.x*2.7+p.y*3.4+p.z*.6)*sin(p.z*4.1-p.y*.5);
      float hatch=step(.92,sin((p.x+p.z*.7+p.y*1.5)*28.))*step(key,.13);
      float gouge=step(.89,sin(p.x*3.7+p.z*1.8+p.y*3.))*step(.4,sin(p.y*5.3+p.z*3.2));
      vec3 c=pigment*(bands+brush*.06)*(1.-hatch*.31-gouge*.12);
      c+=vec3(.28,.12,.025)*warm;
      float fog=1.-exp(-max(0.,d-5.)*.035);c=mix(c,vec3(.038,.067,.085),fog);
      gl_FragColor=vec4(c,1.);
      #include <colorspace_fragment>
    }`
  });
}
export class Batch {
  constructor(root, mat) {
    this.root = root;
    this.mat = mat;
    this.bins = new Map();
    this.parts = 0;
  }
  add(geo, pos, scale, c, rotation = [0, 0, 0], outline = false) {
    const key = `${Math.floor(pos[0]/18)},${Math.floor(pos[2]/18)}`;
    if (!this.bins.has(key)) this.bins.set(key, {
      p: [],
      n: [],
      c: [],
      lines: []
    });
    const b = this.bins.get(key),
      g = geo.index ? geo.toNonIndexed() : geo;
    q.setFromEuler(new T.Euler(...rotation));
    matrix.compose(v.fromArray(pos), q, s.fromArray(scale));
    normalMatrix.getNormalMatrix(matrix);
    color.setHex(c);
    const p = g.attributes.position,
      n = g.attributes.normal;
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i).applyMatrix4(matrix);
      b.p.push(v.x, v.y, v.z);
      v.fromBufferAttribute(n, i).applyMatrix3(normalMatrix).normalize();
      b.n.push(v.x, v.y, v.z);
      b.c.push(color.r, color.g, color.b);
    }
    if (outline) {
      const edges = new T.EdgesGeometry(geo, 35),
        a = edges.attributes.position;
      for (let i = 0; i < a.count; i++) {
        v.fromBufferAttribute(a, i).applyMatrix4(matrix);
        b.lines.push(v.x, v.y, v.z);
      }
      edges.dispose();
    }
    if (g !== geo) g.dispose();
    this.parts++;
  }
  box(p, size, c, rot = [0, 0, 0], ink = false) {
    this.add(boxes, p, size, c, rot, ink);
  }
  cylinder(p, r, h, c, segments = 8, rot = [0, 0, 0], rTop = r, ink = false) {
    const key = `${segments}/${rTop/r}`;
    if (!cylinders.has(key)) cylinders.set(key, new T.CylinderGeometry(rTop / r, 1, 1, segments, 1));
    this.add(cylinders.get(key), p, [r, h, r], c, rot, ink);
  }
  rod(a, b, width, c, ink = false) {
    const mid = new T.Vector3().fromArray(a).add(new T.Vector3().fromArray(b)).multiplyScalar(.5);
    const direction = new T.Vector3().fromArray(b).sub(new T.Vector3().fromArray(a));
    const rot = new T.Euler().setFromQuaternion(new T.Quaternion().setFromUnitVectors(new T.Vector3(0, 1, 0), direction.clone().normalize()));
    this.cylinder(mid.toArray(), width, direction.length(), c, 6, [rot.x, rot.y, rot.z], width, ink);
  }
  finish() {
    const lineMat = new T.LineBasicMaterial({
      color: PALETTE.ink
    });
    for (const [key, b] of this.bins) {
      const g = new T.BufferGeometry();
      for (const [k, a] of [
          ['position', b.p],
          ['normal', b.n],
          ['color', b.c]
        ]) g.setAttribute(k, new T.Float32BufferAttribute(a, 3));
      g.computeBoundingSphere();
      const mesh = new T.Mesh(g, this.mat);
      mesh.name = `Ink masonry ${key}`;
      mesh.matrixAutoUpdate = false;
      this.root.add(mesh);
      if (b.lines.length) {
        const lg = new T.BufferGeometry();
        lg.setAttribute('position', new T.Float32BufferAttribute(b.lines, 3));
        const lines = new T.LineSegments(lg, lineMat);
        lines.matrixAutoUpdate = false;
        this.root.add(lines);
      }
    }
    this.bins.clear();
  }
}
export function arch(batch, x, z, width = 2.7, height = 4.4, angle = 0) {
  function point(a, y, depth = 0) {
    return [x + Math.cos(angle) * a + Math.sin(angle) * depth, y, z - Math.sin(angle) * a + Math.cos(angle) * depth];
  }
  const spring = height - width * .7;
  for (const side of [-1, 1]) {
    for (let j = 0; j < 4; j++) batch.box(point(side * (width / 2 + .15), (j + .5) * spring / 4), [.35, spring / 4 - .035, .65], j % 2 ? PALETTE.stone : PALETTE.edge, [0, angle, 0], true);
    batch.box(point(side * (width / 2 + .15), .15), [.65, .3, .9], PALETTE.dark, [0, angle, 0], true);
    batch.box(point(side * (width / 2 + .15), spring - .05), [.56, .2, .85], PALETTE.edge, [0, angle, 0], true);
    let old = point(side * width / 2, spring);
    for (let i = 1; i <= 6; i++) {
      const t = i / 6;
      const next = point(side * width / 2 * (1 - t), spring + width * .7 * Math.sin(t * Math.PI / 2));
      batch.rod(old, next, .22, noise(x + i, z) > .4 ? PALETTE.edge : PALETTE.stone, true);
      old = next;
    }
  }
  batch.box(point(0, height + .07), [.33, .45, .7], PALETTE.gold, [0, angle, Math.PI / 4], true);
}
// Sculpted low-frequency profiles give cloth, shoulders and hood their shape.
// Rings are deliberately asymmetric; hard normals retain graphic light planes.
function loft(rings, sides = 12) {
  const p = [];

  function point(r, i) {
    const a = i / sides * Math.PI * 2,
      fold = 1 + (i % 2 === 0 ? .055 : -.04);
    return [Math.sin(a) * r[1] * fold + (r[3] || 0), r[0], Math.cos(a) * r[2] * fold + (r[4] || 0)];
  }
  for (let j = 1; j < rings.length; j++)
    for (let i = 0; i < sides; i++) {
      const a = point(rings[j - 1], i),
        b = point(rings[j - 1], i + 1),
        c = point(rings[j], i + 1),
        d = point(rings[j], i);
      p.push(...a, ...b, ...c, ...a, ...c, ...d);
    }
  const g = new T.BufferGeometry();
  g.setAttribute('position', new T.Float32BufferAttribute(p, 3));
  g.computeVertexNormals();
  return g;
}
export function chest(root, mat, x, z) {
  const group = new T.Group();
  group.position.set(x, 0, z);
  root.add(group);
  const b = new Batch(group, mat);
  b.box([0, .35, 0], [1.25, .65, .75], PALETTE.wood, [0, 0, 0], true);
  for (const xx of [-.43, .43]) b.box([xx, .37, -.389], [.085, .67, .045], PALETTE.iron);
  b.box([0, .39, -.406], [.16, .22, .045], PALETTE.gold);
  b.finish();
  const lid = new T.Group();
  lid.position.set(0, .68, .38);
  group.add(lid);
  const l = new Batch(lid, mat);
  l.cylinder([0, 0, -.38], .42, 1.3, PALETTE.woodLight, 8, [0, 0, Math.PI / 2]);
  for (const xx of [-.43, .43]) l.cylinder([xx, 0, -.38], .435, .08, PALETTE.iron, 8, [0, 0, Math.PI / 2]);
  l.finish();
  return {
    group,
    lid,
    opened: false,
    kind: 'chest',
    x,
    z,
    name: '封じられた補給箱'
  };
}
export function buildWorld(layout, mat) {
  const root = new T.Group(),
    batch = new Batch(root, mat),
    tiles = new Set(),
    rooms = [],
    objects = [],
    flames = [],
    enemies = [],
    obstacles = [];
  const scale = layout.scale,
    key = (x, z) => `${x},${z}`;
  const mark = (xmin, zmin, xmax, zmax) => {
    for (let x = Math.ceil(xmin / CELL); x <= Math.floor(xmax / CELL); x++)
      for (let z = Math.ceil(zmin / CELL); z <= Math.floor(zmax / CELL); z++) tiles.add(key(x, z));
  };
  for (const r of layout.rooms) {
    const room = {
      ...r,
      x: r.center[0] * scale,
      z: r.center[1] * scale,
      w: r.size[0] * scale,
      h: r.size[1] * scale,
      visited: false
    };
    rooms.push(room);
    mark(room.x - room.w / 2, room.z - room.h / 2, room.x + room.w / 2, room.z + room.h / 2);
  }
  for (const route of layout.routes) {
    const p = route.points.map(([x, z]) => [x * scale, z * scale]);
    for (let i = 1; i < p.length; i++) mark(Math.min(p[i - 1][0], p[i][0]) - 1.18, Math.min(p[i - 1][1], p[i][1]) - 1.18, Math.max(p[i - 1][0], p[i][0]) + 1.18, Math.max(p[i - 1][1], p[i][1]) + 1.18);
  }
  // Close the old outdoor connector with underground masonry; no exterior view.
  const minX = Math.min(...rooms.map(r => r.x - r.w / 2)) - 3,
    maxX = Math.max(...rooms.map(r => r.x + r.w / 2)) + 3,
    minZ = Math.min(...rooms.map(r => r.z - r.h / 2)) - 3,
    maxZ = Math.max(...rooms.map(r => r.z + r.h / 2)) + 3;
  const dirs = [
    [1, 0],
    [0, 1],
    [-1, 0],
    [0, -1]
  ];
  for (const tile of tiles) {
    const [ix, iz] = tile.split(',').map(Number), x = ix * CELL, z = iz * CELL, rnd = noise(ix, iz);
    color.setHex(PALETTE.floor).multiplyScalar(.78 + rnd * .31);
    batch.box([x, -.13, z], [CELL - .023, .22, CELL - .023], color.getHex());
    // Deliberately broad chips, not noisy scan displacement.
    if (rnd > .94) batch.box([x + .2, .002, z - .22], [.32, .008, .025], PALETTE.ink, [0, .5, 0]);
    const room = rooms.find(r => Math.abs(x - r.x) <= r.w / 2 + .5 && Math.abs(z - r.z) <= r.h / 2 + .5),
      height = room && [1, 6, 16, 23].includes(room.id) ? 7 : 5;
    batch.box([x, height + .15, z], [CELL + .01, .3, CELL + .01], PALETTE.dark);
    for (let d = 0; d < 4; d++)
      if (!tiles.has(key(ix + dirs[d][0], iz + dirs[d][1]))) {
        const [dx, dz] = dirs[d], wx = x + dx * CELL / 2, wz = z + dz * CELL / 2, angle = d % 2 === 0 ? Math.PI / 2 : 0;
        batch.box([wx, height / 2, wz], d % 2 === 0 ? [.27, height, CELL + .04] : [CELL + .04, height, .27], PALETTE.ink);
        for (let row = 0; row < Math.ceil(height / .65); row++) {
          const n = noise(ix * 7 + row, iz * 3 + d);
          color.setHex(n > .75 ? PALETTE.moss : PALETTE.stone).multiplyScalar(.78 + n * .3);
          batch.box([wx - dx * .035, row * .65 + .31, wz - dz * .035], d % 2 === 0 ? [.31, .59, CELL - .055] : [CELL - .055, .59, .31], color.getHex());
          if (row % 2 === 0) batch.box([wx - dx * .2, row * .65 + .045, wz - dz * .2], d % 2 === 0 ? [.012, .04, CELL - .08] : [CELL - .08, .04, .012], PALETTE.dark);
        }
        batch.box([wx - dx * .08, .16, wz - dz * .08], d % 2 === 0 ? [.48, .32, CELL] : [CELL, .32, .48], PALETTE.dark);
        if ((ix + iz * 3) % 5 === 0) {
          batch.box([wx - dx * .19, 2.4, wz - dz * .19], d % 2 === 0 ? [.47, 4.8, .43] : [.43, 4.8, .47], PALETTE.dark, [0, angle, 0], true);
        }
      }
  }

  function torch(x, z, y = 2.6) {
    batch.box([x, y - .4, z], [.14, .85, .18], PALETTE.wood, [0, 0, -.13], true);
    batch.cylinder([x, y, z], .2, .28, PALETTE.iron, 6, [0, 0, 0], .3, true);
    batch.cylinder([x, y + .27, z], .24, .65, 0xd68e43, 5, [0, 0, .13], 0);
    batch.cylinder([x - .03, y + .2, z - .02], .14, .46, 0xffce7c, 5, [0, 0, -.18], 0);
    flames.push({
      x,
      y: y + .27,
      z
    });
  }

  function table(x, z, w = 2, d = 1) {
    obstacles.push({
      x,
      z,
      w,
      d
    });
    batch.box([x, .95, z], [w, .14, d], PALETTE.woodLight, [0, 0, 0], true);
    for (const xx of [-1, 1])
      for (const zz of [-1, 1]) batch.box([x + xx * (w / 2 - .15), .45, z + zz * (d / 2 - .14)], [.16, .9, .16], PALETTE.wood);
  }

  function barrel(x, z) {
    obstacles.push({
      x,
      z,
      w: .85,
      d: .85
    });
    batch.cylinder([x, .55, z], .45, 1.05, PALETTE.wood, 8, [0, 0, 0], .38, true);
    for (const y of [.18, .83]) batch.cylinder([x, y, z], .463, .09, PALETTE.iron, 8);
    batch.cylinder([x, 1.09, z], .36, .05, PALETTE.woodLight, 8);
  }

  function shelf(x, z, w = 2) {
    obstacles.push({
      x,
      z: z - .08,
      w: w + .1,
      d: .6
    });
    batch.box([x, 1.35, z], [w, 2.7, .42], PALETTE.dark, [0, 0, 0], true);
    for (const y of [.08, .9, 1.75, 2.65]) batch.box([x, y, z - .08], [w + .1, .1, .6], PALETTE.woodLight);
    for (let k = 0; k < 3; k++)
      for (let i = 0; i < 10; i++) {
        const rnd = noise(i + k * 10, x + z);
        batch.box([x - w * .43 + i * w * .087, .13 + k * .86 + .3, z - .16], [w * .075, .42 + rnd * .3, .38], [PALETTE.red, PALETTE.moss, PALETTE.woodLight, PALETTE.paper][Math.floor(rnd * 4)], [0, 0, (rnd - .5) * .1]);
      }
  }

  function pew(x, z, w = 3) {
    obstacles.push({
      x,
      z,
      w,
      d: .7
    });
    batch.box([x, .5, z], [w, .14, .65], PALETTE.woodLight, [0, 0, 0], true);
    batch.box([x, .96, z + .26], [w, .85, .13], PALETTE.wood);
    for (const xx of [-w * .4, w * .4]) batch.box([x + xx, .25, z], [.2, .5, .55], PALETTE.wood);
  }

  function banner(x, z, y = 3) {
    batch.box([x, y, z], [1.1, 2.15, .04], PALETTE.red, [0, 0, -.025], true);
    batch.rod([x - .7, y + 1.1, z], [x + .7, y + 1.1, z], .035, PALETTE.gold);
    batch.box([x, y, z - .03], [.045, 1.1, .01], PALETTE.gold);
    batch.box([x, y + .12, z - .03], [.5, .04, .01], PALETTE.gold);
  }

  function altar(x, z) {
    obstacles.push({
      x,
      z,
      w: 3.1,
      d: 1.8
    });
    batch.box([x, .18, z], [3.1, .36, 1.8], PALETTE.dark, [0, 0, 0], true);
    batch.box([x, .8, z], [2.3, 1.15, 1.15], PALETTE.stone, [0, 0, 0], true);
    batch.box([x, 1.45, z], [2.9, .22, 1.6], PALETTE.edge, [0, 0, 0], true);
    for (const dx of [-1, 1]) {
      batch.cylinder([x + dx, 1.68, z], .08, .4, PALETTE.paper, 6);
      batch.cylinder([x + dx, 1.96, z], .045, .18, 0xffc97f, 5, [0, 0, 0], 0);
    }
  }

  function statue(x, z) {
    obstacles.push({
      x,
      z,
      w: 1.3,
      d: 1.3
    });
    batch.box([x, .3, z], [1.3, .6, 1.3], PALETTE.dark, [0, 0, 0], true);
    batch.cylinder([x, 1.45, z], .48, 1.8, PALETTE.stone, 7, [0, 0, 0], .29, true);
    batch.cylinder([x, 2.55, z], .27, .55, PALETTE.bone, 7, [0, 0, .1], .17, true);
    batch.box([x, 2.55, z - .23], [.31, .09, .06], PALETTE.ink);
    batch.rod([x - .2, 2.1, z - .15], [x + .2, 1.6, z - .45], .12, PALETTE.stone);
  }
  for (const r of rooms) {
    const {
      x,
      z,
      w,
      h,
      id
    } = r;
    for (const d of r.doors) {
      const px = d.point[0] * scale,
        pz = d.point[1] * scale;
      arch(batch, px, pz, 2.25, 4.1, ['east', 'west'].includes(d.side) ? Math.PI / 2 : 0);
    }
    torch(x - w / 2 + .65, z - h / 2 + 1);
    torch(x + w / 2 - .65, z + h / 2 - 1);
    // Every room receives its own authored use; keep a clear central route.
    const backSign = r.doors[0]?.side === 'top' ? -1 : 1;
    const back = z - backSign * (h / 2 - .8);
    if ([1, 7, 15, 16, 22, 23].includes(id)) {
      altar(x, back + backSign * 1.1);
      banner(x, back - backSign * .06, 3.8);
      for (const side of [-1, 1]) statue(x + side * (w / 2 - 1.4), back + backSign * 1.2);
      if ([1, 16].includes(id)) {
        for (let j = -1; j <= 1; j++)
          for (const side of [-1, 1]) pew(x + side * w * .28, z + j * 2.3, Math.max(2, w * .28));
        for (const zz of [z - h * .3, z, z + h * .3]) arch(batch, x, zz, w * .76, 6.7);
        const ring = new T.TorusGeometry(2.2, .045, 3, 32);
        batch.add(ring, [x, .018, z], [1, 1, 1], PALETTE.gold, [Math.PI / 2, 0, 0]);
        ring.dispose();
      }
    } else if ([6, 9, 10, 11, 30].includes(id)) {
      for (let j = -1; j <= 1; j++) shelf(x + j * (w / 3 - .2), back, w / 3 - .5);
      table(x, z - .4, 2, 1.1);
      batch.box([x, .95, z - .4], [.8, .04, .6], PALETTE.paper, [0, .2, 0], true);
      banner(x + w / 2 - .9, back + .05, 3.6);
    } else if ([13, 25, 32].includes(id)) {
      table(x, back + .8, w * .7, 1.1);
      batch.box([x - 1.2, 1.1, back + .8], [.8, .3, .4], PALETTE.iron, [0, 0, 0], true);
      for (let i = 0; i < 4; i++) batch.rod([x - .3 + i * .35, 1.1, back + .7], [x - .2 + i * .35, 1.1, back + 1.25], .04, PALETTE.gold);
      barrel(x + w / 2 - 1.1, z + 1.5);
      shelf(x - w / 2 + 1.1, back + 1, 1.7);
    } else if ([8, 14, 24].includes(id)) {
      batch.box([x, -.006, z], [w * .6, .06, h * .6], 0x315e67);
      for (let i = 0; i < 5; i++) batch.box([x + (noise(i, id) - .5) * w * .55, .04, z + (noise(id, i) - .5) * h * .55], [1, .16, .65], PALETTE.edge, [0, noise(i) * 2, 0], true);
      statue(x, back + 1.2);
    } else if (id === 33) {
      // Plain continuous masonry, without window frames or blind niches.
      for (const side of [-1, 1]) {
        obstacles.push({
          x: x + side * (w / 2 - 1.1),
          z,
          w: 1.3,
          d: 2.5
        });
        batch.box([x + side * (w / 2 - 1.1), .4, z], [1.3, .55, 2.5], PALETTE.wood, [0, 0, 0], true);
        batch.box([x + side * (w / 2 - 1.1), .72, z], [1.2, .14, 2.3], PALETTE.red);
        batch.box([x + side * (w / 2 - 1.1), .84, z - .8], [1, .15, .4], PALETTE.paper);
      }
      table(x, back + .7, 1.5, .8);
    } else if ([17, 19, 34].includes(id)) {
      table(x, back + .7, 2, 1);
      banner(x, back, 3.1);
      for (let i = 0; i < 6; i++) batch.cylinder([x - w * .36 + i * .3, 1.5, z + h * .27], .035, 3, PALETTE.iron, 6);
      barrel(x + w / 2 - 1, z - .5);
    } else if (id === 20) {
      for (let j = -1; j <= 1; j++) {
        table(x, z + j * 2.1, w * .6, 1);
        pew(x, z + j * 2.1 + .8, w * .6);
      }
      banner(x, back, 3.5);
    } else {
      for (let i = 0; i < (id === 31 ? 7 : 3); i++) {
        const px = x - w / 2 + .9 + (i % 3) * 1.05,
          pz = back + .8 + Math.floor(i / 3) * 1.1;
        barrel(px, pz);
      }
      table(x + w / 2 - 1.5, back + .6, 1.7, .9);
    }
    if (![1, 6, 16].includes(id)) {
      const loot = chest(root, mat, x + w * .26, z + h * .23);
      loot.id = `chest-${id}`;
      loot.room = id;
      loot.name = '봉인된 보급 상자';
      objects.push(loot);
      obstacles.push({
        x: loot.x,
        z: loot.z,
        w: 1.3,
        d: .8
      });
    }
    // Broad mortar scars and a few silhouette rubble pieces, kept by walls.
    for (let i = 0; i < 4; i++) {
      const n = noise(i, id);
      batch.box([x - w / 2 + .7 + i * .38, .12, z + h / 2 - .55], [.35 + n * .25, .2, .3], PALETTE.dark, [0, n, 0], true);
    }
  }
  // Three narrative landmarks; original monster assets stay preserved separately.
  for (const [room, name, en] of [
      [30, '잊힌 이름의 서책', 'The Book of Forgotten Names'],
      [23, '종지기의 검은 뼈', 'The Bellkeeper’s Black Bone'],
      [1, '꺼지지 않는 성화', 'The Unfading Ember']
    ]) {
    const r = rooms[room - 1],
      group = new T.Group();
    group.position.set(r.x, 1.75, r.z - r.h * .29);
    root.add(group);
    const b = new Batch(group, mat);
    b.cylinder([0, 0, 0], .26, .66, PALETTE.gold, 5, [0, 0, .2], 0, true);
    b.cylinder([0, -.17, 0], .21, .3, 0xd4c39a, 5, [0, 0, .2], .26, true);
    b.finish();
    objects.push({
      kind: 'relic',
      id: `relic-${room}`,
      room,
      name,
      en,
      x: group.position.x,
      z: group.position.z,
      group,
      collected: false
    });
    enemies.push({
      id: `guardian-${room}`,
      room,
      x: r.x,
      z: r.z - .2,
      hp: room === 1 ? 110 : 70,
      maxHp: room === 1 ? 110 : 70,
      kind: room === 1 ? 'warden' : 'penitent',
      name: room === 1 ? '검은 종의 수호자' : '이름을 잃은 순례자',
      dead: false,
      state: 'idle',
      timer: 0,
      home: [r.x, r.z - .2]
    });
  }
  for (const id of [10, 14, 17, 22, 27]) {
    const r = rooms[id - 1];
    enemies.push({
      id: `shade-${id}`,
      room: id,
      x: r.x,
      z: r.z,
      hp: 45,
      maxHp: 45,
      kind: 'shade',
      name: '잉크에 잠긴 망령',
      dead: false,
      state: 'idle',
      timer: 0,
      home: [r.x, r.z]
    });
  }
  const start = rooms[34];
  objects.push({
    kind: 'exit',
    id: 'return-seal',
    room: 35,
    x: start.x,
    z: start.z + 1.4,
    name: '귀환 인장'
  });
  const ring = new T.TorusGeometry(.85, .07, 4, 24);
  batch.add(ring, [start.x, .03, start.z + 1.4], [1, 1, 1], PALETTE.gold, [Math.PI / 2, 0, 0]);
  ring.dispose();
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4;
    batch.box([start.x + Math.sin(a) * .64, .04, start.z + 1.4 + Math.cos(a) * .64], [.08, .04, .2], PALETTE.gold, [0, a, 0]);
  }
  batch.finish();
  root.updateMatrixWorld(true);
  root.traverse(o => {
    if (o.isMesh && !o.parent?.name?.startsWith('animated')) o.updateMatrix();
  });

  function walkable(x, z, radius = .25) {
    const minx = Math.round((x - radius) / CELL),
      maxx = Math.round((x + radius) / CELL),
      minz = Math.round((z - radius) / CELL),
      maxz = Math.round((z + radius) / CELL);
    for (let ix = minx; ix <= maxx; ix++)
      for (let iz = minz; iz <= maxz; iz++) {
        const nx = Math.max(ix * CELL - CELL / 2, Math.min(x, ix * CELL + CELL / 2)),
          nz = Math.max(iz * CELL - CELL / 2, Math.min(z, iz * CELL + CELL / 2));
        if ((x - nx) ** 2 + (z - nz) ** 2 <= radius * radius && !tiles.has(key(ix, iz))) return false;
      }
    return true;
  }
  // Exact narrow-phase AABBs, indexed once for per-frame actor queries.
  const obstacleGrid = new Map();
  for (const o of obstacles)
    for (let ix = Math.floor((o.x - o.w / 2 - .35) / 3); ix <= Math.floor((o.x + o.w / 2 + .35) / 3); ix++)
      for (let iz = Math.floor((o.z - o.d / 2 - .35) / 3); iz <= Math.floor((o.z + o.d / 2 + .35) / 3); iz++) {
        const k = key(ix, iz);
        if (!obstacleGrid.has(k)) obstacleGrid.set(k, []);
        obstacleGrid.get(k).push(o);
      }
  const propsAt = (x, z) => obstacleGrid.get(key(Math.floor(x / 3), Math.floor(z / 3))) || [];
  return {
    root,
    rooms,
    tiles,
    objects,
    flames,
    enemies,
    obstacles,
    propsAt,
    walkable,
    start: [start.x, 1.7, start.z + .2],
    extent: [minX, minZ, maxX, maxZ],
    parts: batch.parts
  };
}

export function makeEnemy(enemy, mat) {
  const root = new T.Group(),
    b = new Batch(root, mat),
    big = enemy.kind === 'warden';
  root.name = 'animated-enemy';
  const c = enemy.kind === 'shade' ? PALETTE.moss : PALETTE.red;
  const body = loft([
    [.12, .42, .3],
    [.35, .45, .31],
    [.7, .33, .27],
    [1.05, .3, .24],
    [1.3, big ? .62 : .43, .29, 0, .05],
    [1.46, big ? .43 : .29, .23, 0, .06],
    [1.5, .16, .14, 0, .04]
  ], 12);
  b.add(body, [0, 0, 0], [1, 1, 1], c, [0, 0, 0], false);
  body.dispose();
  const hood = loft([
    [1.35, .25, .21, 0, -.04],
    [1.55, big ? .4 : .29, .28, 0, -.05],
    [1.8, big ? .31 : .24, .24, .02, 0],
    [2.02, .08, .1, .1, .12],
    [2.08, .01, .01, .14, .16]
  ], 10);
  b.add(hood, [0, 0, 0], [1, 1, 1], PALETTE.dark, [0, 0, 0], true);
  hood.dispose();
  b.cylinder([0, 1.59, -.21], big ? .26 : .2, .36, PALETTE.bone, 7, [.15, 0, .07], .16, true);
  // Heavy stole, visible seam and individual torn hem panels.
  for (const side of [-1, 1]) {
    b.box([side * .18, 1.08, -.255], [.16, .72, .04], PALETTE.woodLight, [0, 0, side * .12], true);
    b.rod([side * .31, .17, -.21], [side * .2, .62, -.24], .014, PALETTE.gold);
  }
  for (let i = 0; i < 6; i++) {
    const a = i * Math.PI / 3;
    b.rod([Math.sin(a) * .43, .15, Math.cos(a) * .29], [Math.sin(a) * .3, .73, Math.cos(a) * .24], .012, PALETTE.ink);
  }
  for (const side of [-1, 1]) {
    b.box([side * .105, 1.62, -.35], [.1, .055, .04], 0xe5b96b, [0, 0, side * .2]);
    b.rod([side * .35, 1.32, 0], [side * .57, .95, -.18], big ? .16 : .11, c, true);
    b.rod([side * .57, .95, -.18], [side * .39, .69, -.34], .08, PALETTE.bone, true);
    b.rod([side * .13, .45, 0], [side * .21, .11, -.08], .1, PALETTE.dark, true);
    b.box([side * .2, .09, -.12], [.2, .17, .4], PALETTE.ink);
  }
  b.box([0, 1.49, -.405], [.11, .035, .035], PALETTE.ink, [0, 0, -.12]);
  if (big) {
    for (const side of [-1, 1]) {
      b.cylinder([side * .4, 1.93, 0], .07, .7, PALETTE.gold, 5, [0, 0, -side * .55], 0, true);
      b.box([side * .52, 1.36, 0], [.4, .25, .5], PALETTE.iron, [0, 0, side * .3], true);
    }
    b.cylinder([.65, .7, -.3], .12, 1.65, PALETTE.iron, 6, [0, 0, .2], .08, true);
    b.cylinder([.5, 1.38, -.3], .35, .53, PALETTE.gold, 7, [0, 0, .2], .24, true);
  } else {
    b.rod([-.35, .6, -.35], [.5, 1.35, -.35], .045, PALETTE.wood);
    b.box([.45, 1.28, -.35], [.15, .55, .07], PALETTE.iron, [0, 0, -.8], true);
  }
  b.finish();
  root.position.set(enemy.x, 0, enemy.z);
  enemy.group = root;
  return root;
}

export function makeHands(mat) {
  const root = new T.Group(),
    right = new T.Group(),
    left = new T.Group();
  root.add(right, left);
  right.position.set(.39, -.4, -.62);
  left.position.set(-.4, -.4, -.64);
  let b = new Batch(right, mat);
  b.cylinder([.08, -.2, .1], .105, .43, PALETTE.dark, 7, [.4, 0, -.15], .13, true);
  b.box([0, 0, 0], [.18, .2, .17], PALETTE.wood, [.1, .1, 0], true);
  for (let i = 0; i < 4; i++) b.box([-.08 + i * .047, .025, -.1], [.041, .09, .05], PALETTE.paper, [0, 0, -.2]);
  b.cylinder([0, .12, -.01], .045, .27, PALETTE.wood, 7, [0, 0, 0], .045, true);
  b.box([0, .26, -.01], [.48, .065, .1], PALETTE.gold, [0, 0, -.07], true);
  const blade = new T.BufferGeometry();
  blade.setAttribute('position', new T.Float32BufferAttribute([-.095, .3, 0, .095, .3, 0, 0, 1.48, 0, -.095, .3, 0, 0, 1.48, 0, -.035, 1.3, .025, .095, .3, 0, .035, 1.3, .025, 0, 1.48, 0], 3));
  blade.computeVertexNormals();
  b.add(blade, [0, 0, -.01], [1, 1, 1], PALETTE.bone, [0, 0, -.1], true);
  blade.dispose();
  b.rod([0, .34, .013], [0, 1.26, .013], .008, PALETTE.edge);
  b.cylinder([0, -.1, 0], .075, .08, PALETTE.gold, 6);
  b.finish();
  b = new Batch(left, mat);
  b.cylinder([-.05, -.18, .12], .11, .4, PALETTE.dark, 7, [-.1, 0, .3], .14, true);
  b.box([0, 0, 0], [.18, .19, .14], PALETTE.wood, [0, 0, 0], true);
  b.cylinder([0, .03, -.15], .32, .065, PALETTE.woodLight, 10, [Math.PI / 2, 0, 0], .32, true);
  b.cylinder([0, .03, -.2], .34, .045, PALETTE.iron, 10, [Math.PI / 2, 0, 0], .34, true);
  b.cylinder([0, .03, -.24], .285, .047, PALETTE.wood, 10, [Math.PI / 2, 0, 0]);
  b.cylinder([0, .03, -.28], .075, .12, PALETTE.gold, 8, [Math.PI / 2, 0, 0], .04, true);
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4;
    b.cylinder([Math.sin(a) * .305, .03 + Math.cos(a) * .305, -.23], .018, .035, PALETTE.gold, 5, [Math.PI / 2, 0, 0]);
  }
  b.finish();
  return {
    root,
    right,
    left
  };
}
