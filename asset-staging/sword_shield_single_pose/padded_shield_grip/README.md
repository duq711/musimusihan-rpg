# Padded rear hand grip staging

`round_shield.glb` changes only the existing rear hand loop and the stitches
attached to its changed surface. `source_round_shield.glb` is the preserved
production source. The forearm loop, mounting tabs, rivets, shield boards, boss,
rim, all marker transforms, materials, UVs, AO colors and triangle indices are
unchanged. No production copying, Godot importing or gameplay capture is done
by this script.

The merged mesh's real rear hand loop is identified by welded triangle
connectivity: 1170 geometric vertices, 2048 `FP_ShieldEnarmes` triangles and 288
`FP_ShieldLeatherEdge` triangles. This component is separate from the arm loop
and four mounting tabs. The new padded section reuses its original closed
18-vertex cross section and 65 longitudinal rows, without collapsed faces.

In GLB Y-up coordinates **before** the player's additional Y=PI rotation:

```text
theta = -4 degrees
A = (cos(theta), -sin(theta), 0)
C(v) = (-.18 + v*sin(theta), .015 + v*cos(theta), -d(v))
d(v) = .004 - dish(C.x,C.y) + .145*sin(pi*(v/.235+.5))^.62
dish(x,y) = .025*max(0,1-(x*x+y*y)/.415^2)
N(v) = normalize((-d'(v)*sin(theta),-d'(v)*cos(theta),-1))
E(v,phi) = C(v) + A*.015*cos(phi) + N(v)*.011*sin(phi)
w(v) = 1 - smoothstep(.0525,.080,abs(v))
Pnew = lerp(Poriginal,E,w)
```

`v` is the authored centerline row parameter, rather than the projection of a
solidify-offset vertex. For |v|≤52.5mm the cross section is a nominal 30×22mm
ellipse. Its eighteen 20-degree samples start at 10 degrees, giving an actual
polygon width of 29.544mm and height of 22mm. The transition ends at 80mm;
original vertices and their shading frames outside that interval are preserved.
Each source vertex is matched to its actual 2mm solidify offset from the
authored grid before deformation. The original flat mounting section therefore
remains 44mm wide and 4mm thick.

`actual_surface.json` records all actual GLB-local vertex coordinates and the
unchanged triangle mapping as `(row,phi_index)` triples. This captures the
exporter's alternating triangle diagonals, so contact solving can sample the
rendered polygon surface rather than assuming a perfect analytic cylinder.

The original hand-loop stitches at u=±18mm would float outside the narrower
padding. Forty-six independent stitch tubes in the changed interval are
therefore seated on the **same actual triangle surface**, with 0.5mm center
clearance for their retained 0.45mm tube radius. Their endpoint frames rotate
with that surface, preserving tube radii. The other fourteen hand-loop stitches,
all sixty forearm-loop stitches and any endpoints outside the interval remain
unchanged. The loop and relocated stitches receive normals/tangents calculated
from their actual transformed triangles and preserved UVs.

Reproduce from the project root:

```sh
python3 asset-staging/sword_shield_single_pose/padded_shield_grip/pad_shield_grip.py
```

The script uses the neighboring `corrected_sword/correct_longsword.py` stdlib
GLB reader/writer. `preservation_report.json` records source/output hashes,
component identities, unchanged attribute hashes and each relocated stitch.
Saved geometry was checked for finite normals/tangents and nondegenerate loop
triangles. Final skin contact, gameplay and renderer validation remain pending.
