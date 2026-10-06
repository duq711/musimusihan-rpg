"""Read-only actual glTF LINEAR/STEP skin evaluator for fixed Blender regions.

Uses the project's existing pure GLB accessor reader and quaternion evaluator.
No engine is launched and no model or binary is modified. UV-seam duplicates
are mapped to original vertices by baked rest position and named skin weights;
all original triangle IDs/region masks remain unchanged for the surface probe.
"""
import sys
import bisect
from collections import Counter
from pathlib import Path

import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_creep_dismemberment import GLB
from verify_creep_dismemberment import interpolated, local_matrix


class CachedGLB(GLB):
    def __init__(self, path):
        super().__init__(path)
        self._cache = {}

    def read(self, index):
        if index not in self._cache:
            self._cache[index] = super().read(index)
        return self._cache[index]


class ExportSkin:
    def __init__(self, path, mesh, original_weights, original_names):
        self.glb = CachedGLB(path)
        document = self.glb.doc
        node = next(n for n in document['nodes'] if n.get('name') == 'LabradorPet_Mesh')
        skin = document['skins'][node['skin']]
        assert node['skin'] == 0, 'Shared evaluator currently supports inspected first skin only'
        primitives = document['meshes'][node['mesh']]['primitives']
        assert len(primitives) == 1, 'Unexpected Labrador primitive layout'
        assert primitives[0].get('mode', 4) == 4, 'Surface review requires delivered TRIANGLES mode'
        indices = np.asarray(self.glb.read(primitives[0]['indices']), dtype=np.int32).reshape(-1)
        assert len(indices) % 3 == 0, 'Invalid delivered triangle index count'
        exported_triangles = indices.reshape((-1, 3))
        attributes = primitives[0]['attributes']
        assert 'JOINTS_1' not in attributes, 'Review evaluator must explicitly support extra influence set'
        positions = np.asarray(self.glb.read(attributes['POSITION']), dtype=np.float64)
        self.joints = np.asarray(self.glb.read(attributes['JOINTS_0']), dtype=np.int32)
        self.weights = np.asarray(self.glb.read(attributes['WEIGHTS_0']), dtype=np.float64)
        self.weights /= self.weights.sum(axis=1, keepdims=True)
        self.positions = np.column_stack((positions, np.ones(len(positions))))
        self.names = [document['nodes'][n]['name'] for n in skin['joints']]
        self.binds = np.asarray(self.glb.read(skin['inverseBindMatrices']), dtype=np.float64).reshape((-1, 4, 4)).transpose(0, 2, 1)
        self.inverse_binds_inverse = np.linalg.inv(self.binds)
        self.animations = {a['name']: a for a in document['animations']}
        for animation in self.animations.values():
            assert all(s.get('interpolation', 'LINEAR') in ('LINEAR', 'STEP') for s in animation['samplers'])
        # glTF has baked source mesh world coordinates and Y-up; restore Z-up.
        rest = np.asarray([list(mesh.matrix_world @ v.co) for v in mesh.data.vertices], dtype=np.float64)
        exported_rest = positions[:, [0, 2, 1]].copy()
        exported_rest[:, 1] *= -1
        tree = KDTree(len(rest))
        for index, point in enumerate(rest):
            tree.insert(Vector(point), index)
        tree.balance()
        export_weights_named = np.zeros((len(positions), len(original_names)), dtype=np.float64)
        for slot in range(4):
            for joint in range(len(self.names)):
                if self.names[joint] not in original_names:
                    assert not np.any(self.weights[self.joints[:, slot] == joint, slot] > 1e-8), 'Unexpected deforming helper joint'
                    continue
                ids = np.flatnonzero(self.joints[:, slot] == joint)
                export_weights_named[ids, original_names.index(self.names[joint])] += self.weights[ids, slot]
        source_weights = np.asarray(original_weights, dtype=np.float64)
        source_weights /= source_weights.sum(axis=1, keepdims=True)
        assert np.max(np.count_nonzero(source_weights > 1e-8, axis=1)) <= 4, 'Source influence truncation requires separate skin-fidelity analysis'
        mapped = [[] for _ in range(len(rest))]
        original_alias_parent = list(range(len(rest)))
        def alias_root(index):
            while original_alias_parent[index] != index:
                original_alias_parent[index] = original_alias_parent[original_alias_parent[index]]
                index = original_alias_parent[index]
            return index
        def unite(first, second):
            a, b = alias_root(first), alias_root(second)
            if a != b:
                original_alias_parent[max(a, b)] = min(a, b)
        export_original_alias = []
        max_position_error = max_weight_error = 0.
        for exported, point in enumerate(exported_rest):
            nearby = tree.find_range(Vector(point), 1e-6)
            accepted = []
            for _, original, distance in nearby:
                error = np.max(np.abs(source_weights[original] - export_weights_named[exported]))
                if error <= 2e-6:
                    accepted.append(original)
                    max_position_error = max(max_position_error, distance)
                    max_weight_error = max(max_weight_error, float(error))
            assert accepted, f'Export vertex{exported} cannot map to fixed original region'
            for original in accepted[1:]:
                unite(accepted[0], original)
            export_original_alias.append(accepted[0])
            for original in accepted:
                mapped[original].append(exported)
        assert all(mapped), 'Some fixed original vertices are absent in export'
        self.index = np.asarray([ids[0] for ids in mapped], dtype=np.int32)
        self.duplicates = [ids for ids in mapped if len(ids) > 1]
        original_classes = [alias_root(i) for i in range(len(rest))]
        export_classes = [alias_root(i) for i in export_original_alias]
        mesh.data.calc_loop_triangles()
        original_triangles = [list(t.vertices) for t in mesh.data.loop_triangles]
        def oriented_face(vertices, classes):
            a, b, c = [classes[int(i)] for i in vertices]
            return min((a, b, c), (b, c, a), (c, a, b))
        original_faces = Counter(oriented_face(t, original_classes) for t in original_triangles)
        export_faces = Counter(oriented_face(t, export_classes) for t in exported_triangles)
        assert original_faces == export_faces, 'Delivered triangle surface or winding differs; original masks cannot stand in for changed export topology'
        self.sampler_histograms = {name: dict(Counter(s.get('interpolation', 'LINEAR') for s in animation['samplers']))
                                   for name, animation in self.animations.items()}
        self.mapping_receipt = {'original_vertices': len(rest), 'export_vertices': len(positions),
                                'all_original_vertices_mapped': True,
                                'max_baked_rest_position_mapping_error_m': max_position_error,
                                'max_normalized_named_weight_mapping_error': max_weight_error,
                                'original_vertex_duplicate_groups': len(self.duplicates),
                                'original_triangles': len(original_triangles),
                                'export_triangles': len(exported_triangles),
                                'directed_canonical_triangle_multiset_matches': True,
                                'topology_mapping': 'Many-to-many rest-position/named-weight aliases canonicalized jointly; triangle multiplicity and cyclic orientation preserved.',
                                'original_ids_and_triangle_masks_retained': True,
                                'sampler_histograms': self.sampler_histograms,
                                'interpolation': 'Actual glTF LINEAR translation/scale and quaternion shortest-path slerp; STEP retained'}

    def skin_matrices(self, clip, seconds):
        document = self.glb.doc
        nodes = [dict(n) for n in document['nodes']]
        for channel in self.animations[clip]['channels']:
            sampler = self.animations[clip]['samplers'][channel['sampler']]
            times = [row[0] for row in self.glb.read(sampler['input'])]
            values = self.glb.read(sampler['output'])
            path = channel['target']['path']
            assert path in ('translation', 'rotation', 'scale')
            key = max(0, min(len(times) - 1, bisect.bisect_right(times, seconds) - 1))
            if len(times) == 1 or sampler.get('interpolation', 'LINEAR') == 'STEP' or key == len(times) - 1:
                value = values[key]
            else:
                t = max(0, min(1, (seconds - times[key]) / (times[key + 1] - times[key])))
                value = interpolated(values[key], values[key + 1], t, path == 'rotation')
            nodes[channel['target']['node']][path] = value
        parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
        global_matrices = {}
        def global_node(index):
            if index not in global_matrices:
                local = np.asarray(local_matrix(nodes[index]), dtype=np.float64)
                global_matrices[index] = global_node(parents[index]) @ local if index in parents else local
            return global_matrices[index]
        skin = document['skins'][0]
        return np.asarray([global_node(node) @ inverse_bind
                           for node, inverse_bind in zip(skin['joints'], self.binds)], dtype=np.float64)

    def sample(self, clip, seconds):
        matrices = self.skin_matrices(clip, seconds)
        transformed = np.einsum('nvij,nvj->nvi', matrices[self.joints], self.positions[:, None, :])
        world = (transformed * self.weights[:, :, None]).sum(axis=1)[:, :3]
        world = world[:, [0, 2, 1]].copy()
        world[:, 1] *= -1
        duplicate_error = max((float(np.max(np.linalg.norm(world[ids] - world[ids[0]], axis=1)))
                               for ids in self.duplicates), default=0.)
        assert duplicate_error <= 2e-6, 'UV/rest duplicates diverge in delivered skin'
        convert = np.asarray([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], dtype=np.float64)
        global_bones = matrices @ self.inverse_binds_inverse
        bones = {name: Matrix(convert @ matrix) for name, matrix in zip(self.names, global_bones)}
        return world[self.index], bones, duplicate_error
