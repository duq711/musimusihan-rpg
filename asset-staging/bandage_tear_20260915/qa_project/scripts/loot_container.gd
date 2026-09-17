extends RefCounted
class_name LootContainer

signal changed
signal stack_identified(index: int, item_id: String)

const DEFAULT_IDENTIFY_INTERVAL := 0.8

var title := "보물 상자"
var subtitle := "검은 성물실"
var max_slots := 20
var items: Array[Dictionary] = []
var ever_opened := false
var search_started := false
var search_elapsed := 0.0
var identify_interval := DEFAULT_IDENTIFY_INTERVAL


func configure(title_text: String, item_stacks: Array, subtitle_text := "검은 성물실", capacity := 20) -> LootContainer:
	title = title_text
	subtitle = subtitle_text
	max_slots = maxi(1, capacity)
	items.clear()
	ever_opened = false
	search_started = false
	search_elapsed = 0.0
	for value in item_stacks:
		if not value is Dictionary:
			continue
		var stack := value as Dictionary
		# Authored loot begins concealed. Items deliberately placed into the
		# container later use store_item's identified=true default.
		store_item(str(stack.get("id", "")), int(stack.get("quantity", 1)), false, false, stack.get("instance", {}))
	return self


func store_item(item_id: String, quantity := 1, notify := true, identified := true, instance_data: Dictionary = {}) -> int:
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if definition.is_empty() or quantity <= 0:
		return quantity
	var remaining := quantity
	var stack_max := maxi(1, int(definition.get("stack_max", 1)))
	if stack_max > 1:
		for stack in items:
			# Never merge a known item into a concealed stack. Besides preserving
			# search progress, this prevents a player-deposited item from exposing
			# the identity of authored loot with the same id.
			if str(stack.get("id", "")) != item_id or bool(stack.get("identified", true)) != identified or stack.get("instance", {}) != instance_data:
				continue
			var room := stack_max - int(stack.get("quantity", 0))
			var moved := mini(maxi(0, room), remaining)
			stack["quantity"] = int(stack.get("quantity", 0)) + moved
			remaining -= moved
			if remaining <= 0:
				break
	while remaining > 0 and items.size() < max_slots:
		var moved := mini(stack_max, remaining)
		var new_stack := {"id": item_id, "quantity": moved, "identified": identified}
		if not instance_data.is_empty():
			new_stack["instance"] = instance_data.duplicate(true)
		items.append(new_stack)
		remaining -= moved
	if notify and remaining != quantity:
		changed.emit()
	return remaining


func take_from_slot(index: int, quantity := 999999, notify := true) -> Dictionary:
	if index < 0 or index >= items.size() or quantity <= 0:
		return {}
	var stack := items[index]
	if not bool(stack.get("identified", true)):
		return {}
	var moved := mini(quantity, int(stack.get("quantity", 0)))
	var result := {
		"id": str(stack.get("id", "")),
		"quantity": moved,
		"identified": bool(stack.get("identified", true))
	}
	if stack.has("instance"):
		result["instance"] = (stack["instance"] as Dictionary).duplicate(true)
	items[index]["quantity"] = int(stack.get("quantity", 0)) - moved
	if int(items[index].get("quantity", 0)) <= 0:
		items.remove_at(index)
	if notify:
		changed.emit()
	return result


func begin_search() -> bool:
	if search_started:
		return false
	search_started = true
	return true


func advance_search(delta: float) -> Dictionary:
	if not search_started or delta <= 0.0 or not has_unidentified_items():
		return {}
	search_elapsed += delta
	var interval := maxf(0.01, identify_interval)
	if search_elapsed < interval:
		return {}
	# Reveal at most one stack per call. A long frame therefore cannot collapse
	# the intended one-by-one discovery sequence into a single visual update.
	search_elapsed = maxf(0.0, search_elapsed - interval)
	for index in range(items.size()):
		if bool(items[index].get("identified", true)):
			continue
		items[index]["identified"] = true
		var item_id := str(items[index].get("id", ""))
		var result := {
			"index": index,
			"id": item_id,
			"quantity": int(items[index].get("quantity", 0))
		}
		stack_identified.emit(index, item_id)
		changed.emit()
		if not has_unidentified_items():
			search_elapsed = 0.0
		return result
	return {}


func identify_all(notify := true) -> void:
	var identified_any := false
	search_started = true
	for index in range(items.size()):
		if bool(items[index].get("identified", true)):
			continue
		items[index]["identified"] = true
		identified_any = true
		if notify:
			stack_identified.emit(index, str(items[index].get("id", "")))
	search_elapsed = 0.0
	if notify and identified_any:
		changed.emit()


func reveal_all(notify := true) -> void:
	identify_all(notify)


func is_stack_identified(index: int) -> bool:
	return index >= 0 and index < items.size() and bool(items[index].get("identified", true))


func has_unidentified_items() -> bool:
	for stack in items:
		if not bool(stack.get("identified", true)):
			return true
	return false


func identified_stack_count() -> int:
	var total := 0
	for stack in items:
		if bool(stack.get("identified", true)):
			total += 1
	return total


func unidentified_stack_count() -> int:
	return items.size() - identified_stack_count()


func is_empty() -> bool:
	return items.is_empty()


func item_count() -> int:
	var total := 0
	for stack in items:
		total += int(stack.get("quantity", 0))
	return total
