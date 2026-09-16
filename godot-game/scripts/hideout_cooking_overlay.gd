extends "res://scripts/camp_overlay.gd"
class_name HideoutCookingOverlay


func _refresh() -> void:
	selected_category = "cooking"
	super._refresh()
	var cooking := bool(_snapshot.get("is_cooking", false))
	title_label.text = "화롯불 부엌 · 조리 중" if cooking else "화롯불 부엌 · 요리와 식사"
	category_tabs.hide()
	var counts: Dictionary = _snapshot.get("inventory_counts", {})
	var ingredients: Array[String] = []
	for item_id: String in counts:
		ingredients.append("%s %d" % [ExpeditionInventory.get_item_name(item_id), int(counts[item_id])])
	resources_label.text = "보유 재료 · " + " · ".join(ingredients)
	cooking_hint_label.text = "가마솥과 꼬치로 음식을 만들어 완성 즉시 먹습니다. 은신처 화롯불은 야영 도구나 온기를 소비하지 않습니다."
	risk_label.text = "조리하는 동안 게임 시간과 상태이상 시간이 흐릅니다. 중단하면 사용한 재료는 반환되지 않습니다." if cooking else "재료는 조리를 시작할 때 사용합니다. 회복량과 보유 / 필요 수량을 확인하세요."
	leave_button.text = "조리 중단 · 재료 반환 없음" if cooking else "부엌 닫기 · Esc"
	if str(_snapshot.get("status", "")).is_empty():
		status_label.text = "요리가 완성되면 바로 먹습니다." if cooking else "만들어 먹을 요리를 선택하세요."

	# Completion feedback stays above the recipes, where it is visible without
	# scrolling through all cards after each meal.
	var body := status_label.get_parent()
	body.move_child(status_label, 3 if not cooking else body.get_child_count() - 1)
	status_label.visible = cooking or "조리·식사 완료" in status_label.text
	if not cooking and status_label.visible:
		status_label.add_theme_color_override("font_color", Color(0.87, 0.79, 0.55))
