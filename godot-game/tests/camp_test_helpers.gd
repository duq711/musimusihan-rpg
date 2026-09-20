extends RefCounted

## Use production aiming, physical placement and tent entry in action tests.
## Tests for the inventory/input route live in camp_placement_room_test.gd.
static func deploy_and_open(camp: DungeonCamp) -> Dictionary:
	var player := camp.player
	var previous_pitch := player._pitch
	var previous_head_pitch := player.head.rotation.x
	player._pitch = -deg_to_rad(40.0)
	player.head.rotation.x = player._pitch
	var result := camp.begin_placement()
	if bool(result.get("accepted", false)):
		camp.update_placement()
		result = camp.confirm_placement()
	player._pitch = previous_pitch
	player.head.rotation.x = previous_head_pitch
	if not bool(result.get("accepted", false)):
		if camp.state == "placing":
			camp.cancel_camp("", true)
		return result
	return camp.open_camp()
