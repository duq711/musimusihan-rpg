extends "res://tests/reference_sword_overhead_delivery_test.gd"
## Actual received overhead applied to the production player. Existing arm
## geometry is permitted; the missing native sleeve is reported explicitly.
## This is neither the final sleeve delivery gate nor all-eight completion.


func _report_name() -> String:
	return "REFERENCE SWORD OVERHEAD RUNTIME"


func _requires_native_sleeve() -> bool:
	return false
