"""Reference-map cave volume -> a sculptable Blender source mesh, in metres.

Requires numpy/scipy/scikit-image/shapely. The final scene is authored, dressed,
UV mapped, optimized and exported by build_mine.py inside Blender itself.
"""
import json
import hashlib
import struct
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get("MINE_BUILD_DEPS", "/tmp/mine-build-deps"))
import numpy as np
from scipy import ndimage as ndi
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union
from shapely import contains_xy
from skimage.measure import marching_cubes

ROOT = Path(__file__).resolve().parent
LAYOUT = json.loads((ROOT / "layout.json").read_text())
STEP = float(os.environ.get("MINE_VOXEL_SIZE", "0.34"))
SEED = 913139
rng = np.random.default_rng(SEED)
xs = np.linspace(-65.5, 65.5, round(131 / STEP) + 1, dtype=np.float32)
zs = np.linspace(-69.5, 69.5, round(139 / STEP) + 1, dtype=np.float32)
ys = np.linspace(-1.0, 19.0, round(20 / STEP) + 1, dtype=np.float32)
dz, dx, dy = float(zs[1]-zs[0]), float(xs[1]-xs[0]), float(ys[1]-ys[0])
X, Z = np.meshgrid(xs, zs)


def polygon(entry):
    return Polygon(entry["polygon"]).buffer(0)


def random_field(shape, physical_scale, amplitude=1.0, seed=0):
    """Aperiodic solid noise; independent seeds and spatial scales, no sine bands."""
    local_rng = np.random.default_rng(SEED + seed)
    sizes = [139, 131, 20][:len(shape)]
    coarse = tuple(max(3, round(size / physical_scale) + 2) for size in sizes)
    raw = local_rng.normal(0, 0.6, coarse).astype(np.float32)
    result = ndi.zoom(raw, [s/c for s,c in zip(shape,coarse)], order=3, prefilter=True)
    return (result * amplitude).astype(np.float32)


room_polys = [polygon(room) for room in LAYOUT["rooms"]]
routes = [LineString(link["points"]).buffer(link["width"] / 2, cap_style=1, join_style=1) for link in LAYOUT["corridors"]]
route_lines = unary_union([LineString(link["points"]) for link in LAYOUT["corridors"]])
outer_playable = unary_union(room_polys + routes)
playable = outer_playable
for island in LAYOUT.get("islands", []):
    playable = playable.difference(polygon(island))
mask = contains_xy(playable, X, Z)
inside = ndi.distance_transform_edt(mask, sampling=(dz,dx)).astype(np.float32)
outside = ndi.distance_transform_edt(~mask, sampling=(dz,dx)).astype(np.float32)
wall_distance = ndi.gaussian_filter(inside-outside, 0.65)

ceiling = np.full(X.shape, 4.15, dtype=np.float32)
geology = np.zeros(X.shape, dtype=np.int16)
geology_types = {"fractured_limestone": 0, "flowstone": 1, "lava": 2, "mined": 3}
for i, room in enumerate(LAYOUT["rooms"]):
    rm = contains_xy(room_polys[i].buffer(2), X, Z)
    local = ndi.distance_transform_edt(contains_xy(room_polys[i], X,Z), sampling=(dz,dx))
    t = np.clip(local / max(4, float(room["height"]) * 0.62), 0, 1)
    t = np.sin(t * np.pi * 0.5)  # Vault cross section, never a surface pattern.
    ceiling = np.maximum(ceiling, 4.15 + (room["height"]-4.15) * t)
    geology[rm] = geology_types.get(room.get("geology"), 0)
ceiling += random_field(X.shape, 5.7, 0.9, 4)
ceiling = np.maximum(ceiling, 3.7)
floor = random_field(X.shape, 3.2, 0.055, 6)
poolmask = np.zeros(X.shape, dtype=bool)
for pool in LAYOUT.get("pools", []):
    pm = contains_xy(polygon(pool), X,Z)
    poolmask |= pm
    pd = ndi.distance_transform_edt(pm, sampling=(dz,dx))
    floor -= np.clip(pd / 2.2, 0, 1) * 0.30

shape = X.shape + (len(ys),)
print("SCULPT VOLUME", shape, "air area", round(float(mask.sum()*dx*dz)), "m2", flush=True)
wall_noise = random_field(shape, 7.0, 1.20, 11)
wall_noise += random_field(shape, 2.2, 0.47, 12)
wall_noise += random_field(shape, 0.75, 0.13, 13)

# Non-periodic joints along sedimentary layers are confined to dark galleries.
# Individual layer thickness, erosion and warping differ, instead of etched waves.
profile_rng = np.random.default_rng(429)
levels = np.cumsum(profile_rng.uniform(0.32, 1.1, 55)) - 2
offsets = profile_rng.uniform(-0.21, 0.20, 55)
profile = np.interp(ys, levels, offsets).astype(np.float32)
dark_weight = ndi.gaussian_filter((geology == 2).astype(np.float32), 4)
wall_noise += dark_weight[...,None] * profile[None,None,:]
outer_mask = contains_xy(outer_playable, X, Z)
outer_distance = ndi.gaussian_filter(ndi.distance_transform_edt(outer_mask, sampling=(dz,dx)) - ndi.distance_transform_edt(~outer_mask, sampling=(dz,dx)), 0.65).astype(np.float32)
wall = outer_distance[...,None] + wall_noise
del wall_noise

# Keep authored walkways fully usable up to head height; upper walls remain rough.
walk = contains_xy(route_lines.buffer(1.35), X,Z)
for j,y in enumerate(ys):
    if 0.08 < y < 2.7:
        wall[:,:,j] = np.where(walk, np.maximum(wall[:,:,j], 0.9), wall[:,:,j])

below_roof = ceiling[...,None] - ys[None,None,:]
above_floor = ys[None,None,:] - floor[...,None]


def smooth_min(a,b,k):
    h = np.maximum(k - np.abs(a-b), 0) / k
    return np.minimum(a,b) - h*h*k*0.25


# Filleted intersections sculpt sloping shoulders and hollows in the roof.
field = smooth_min(wall, below_roof, 1.15)
field = np.minimum(field, above_floor)
# Islands are finite boulders rising from the lakebed, never roof-height tubes.
# Authored heights preserve the central quarry boulder and low water islets.
for island_index, island in enumerate(LAYOUT.get("islands", [])):
    im = contains_xy(polygon(island), X, Z)
    di = ndi.distance_transform_edt(im, sampling=(dz,dx)).astype(np.float32)
    do = ndi.distance_transform_edt(~im, sampling=(dz,dx)).astype(np.float32)
    island_distance = di - do
    crown = np.sqrt(np.clip(di / max(0.1, float(di.max())), 0, 1))
    top = float(island["height"]) * crown + random_field(X.shape, 1.8, .15, 100+island_index)
    sides = island_distance[...,None] + random_field(shape, 1.1, .10, 200+island_index)
    island_solid = np.minimum(sides, top[...,None] - ys[None,None,:])
    field = np.minimum(field, -island_solid)
# Exact survey boundary remains solid even at noisy outer rock extremities.
boundary = np.minimum(65.1-np.abs(X), 69.1-np.abs(Z))
field = np.minimum(field, boundary[...,None]).astype(np.float32)
del wall, below_roof, above_floor

verts, faces, normals, _ = marching_cubes(field, 0, spacing=(dz,dx,dy), allow_degenerate=False)
verts[:,0] += zs[0]
verts[:,1] += xs[0]
verts[:,2] += ys[0]
# Volume axes (map-Z,X,height) to Blender (X,-map-Z,height), determinant +1.
vertices = np.column_stack((verts[:,1], -verts[:,0], verts[:,2])).astype(np.float32)
normal_blender = np.column_stack((normals[:,1], -normals[:,0], normals[:,2]))
triangles = vertices[faces]
face_normals = np.cross(triangles[:,1]-triangles[:,0], triangles[:,2]-triangles[:,0])
floor_faces = (triangles[:,:,2].mean(axis=1) < 0.15) & (np.abs(face_normals[:,2]) > 0.5*np.linalg.norm(face_normals,axis=1))
if np.median(face_normals[floor_faces,2]) < 0:
    faces = faces[:,[0,2,1]]
    face_normals *= -1
centers = triangles.mean(axis=1)
ix = np.clip(np.round((centers[:,0]-xs[0])/dx).astype(int),0,len(xs)-1)
iz = np.clip(np.round((-centers[:,1]-zs[0])/dz).astype(int),0,len(zs)-1)
material_ids = geology[iz,ix].astype(np.int16)
material_ids[(centers[:,2] < 0.5) & (face_normals[:,2] > 0)] = 4

# Closed air shell includes detailed walls, actual floor, roof and rock islands.
np.savez_compressed(ROOT / "terrain_mesh.npz", vertices=vertices, faces=faces.astype(np.int32), material_ids=material_ids, xs=xs,zs=zs,floor=floor,ceiling=ceiling,signed_distance=wall_distance,geology=geology)
runtime=ROOT.parents[1]/"godot-game/assets/3d/abandoned_mine"
with open(runtime/"terrain_samples.bin","wb") as target:
    target.write(struct.pack("<IIffff",len(xs),len(zs),float(xs[0]),float(zs[0]),dx,dz))
    for sample in [floor,ceiling,wall_distance]:
        target.write(np.asarray(sample,dtype="<f4").tobytes())
report = {"vertex_count":len(vertices),"triangle_count":len(faces),"voxel_step_metres":[dx,dz,dy],"floor_area_m2":round(float(mask.sum()*dx*dz),1),"room_count":len(LAYOUT["rooms"]),"corridor_count":len(LAYOUT["corridors"]),"bounds_m":[131,139],"pipeline":"3D solid sculpt field, meshed for Blender; no runtime Godot primitive cave"}
report["layout_sha256"]=hashlib.sha256((ROOT/"layout.json").read_bytes()).hexdigest()
(ROOT/"terrain_report.json").write_text(json.dumps(report,indent=2))
print(json.dumps(report),flush=True)
