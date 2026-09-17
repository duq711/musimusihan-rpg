extends RefCounted
## Authored against the actual 74%-scale torch shaft and supplied left hand.
## Signed additions account for the source hand already being curled.
const ARM_TRANSFORM := Transform3D(Basis(Vector3(2.12609467809e-08, 0.959528923035, 0.281609773636), Vector3(-1, -1.23095560411e-08, 1.17440244196e-07), Vector3(1.16153813678e-07, -0.281609803438, 0.959528982639)), Vector3(0.0059380014427, 0.0998533144593, 0.0686457753181))
# Raised left hand beside the shoulder; the burning head is outside first-person view.
const CARRY_POSITION := Vector3(-0.64, -0.39, -0.15)
const CARRY_ROTATION := Vector3(20, 30, 0)
const DRAW_DURATION := 1.05
const DRAW_REVEAL_TIME := 0.38
const DRAW_POSITION := Vector3(-0.43, -0.46, -0.62)
const DRAW_ROTATION := Vector3(-25, 8, 13)
const STOW_POSITION := Vector3(-0.60, -1.30, -0.26)
const STOW_ROTATION := Vector3(-8, 10, -4)
const CONTACT_CENTER := Vector3(0, -0.00406199985037, -0.0715411166255)
const THUMB_OPPOSITION := 0.09431794285774231
const JOINT_ANGLES := {
	"thumb": Vector3(0.268142163754, -0.331312477589, 0.20472663641),
	"index": Vector3(-1.09131526947, 0.345772504807, -0.218567371368),
	"middle": Vector3(-0.985728502274, 0.33566570282, -0.588808298111),
	"ring": Vector3(-0.72086751461, 0.237053409219, -0.108129024506),
	"little": Vector3(-0.174964681268, -0.343162983656, 0.509017586708),
}
const THUMB_ROOT_ADDUCTION := 0.8246737607846465
const SHAFT_RADIUS_RATIO := 0.85
const ROOT_ADDUCTION := {"index": 0.14879982193847818, "middle": -0.26901910294611453, "ring": -0.4124475949292844, "little": -0.21071623579729457}

# Exact local bone rotations from the user-edited Blender file (wxyz -> xyzw).
const MANUAL_ROTATIONS := {
	"wrist": Quaternion(0, 0, 0, 1),
	"thumb0": Quaternion(0.137310266495, 0.0340059772134, -0.099000826478, 0.984981358051),
	"thumb1": Quaternion(-0.164899632335, 0, 0, 0.986310362816),
	"thumb2": Quaternion(0.102184645832, 0, 0, 0.994765460491),
	"index0": Quaternion(-0.517544567585, -0.0385764949024, 0.06353738904, 0.852421522141),
	"index1": Quaternion(0.17202629149, 0, 0, 0.985092401505),
	"index2": Quaternion(-0.109066292644, 0, 0, 0.994034469128),
	"middle0": Quaternion(-0.468877315521, 0.0634516254067, -0.118143409491, 0.873023509979),
	"middle1": Quaternion(0.167046040297, 0, 0, 0.985949099064),
	"middle2": Quaternion(-0.290169686079, 0, 0, 0.956975221634),
	"ring0": Quaternion(-0.34520727396, 0.0722166523337, -0.191607862711, 0.91591656208),
	"ring1": Quaternion(0.118249394, 0, 0, 0.992983937263),
	"ring2": Quaternion(-0.0540381781757, 0, 0, 0.998538851738),
	"little0": Quaternion(-0.0868863239884, 0.00918820314109, -0.10476116091, 0.990652024746),
	"little1": Quaternion(-0.170740827918, 0, 0, 0.985315978527),
	"little2": Quaternion(0.251770079136, 0, 0, 0.967787086964),
}
