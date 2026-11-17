extends SceneTree
## headless 测试入口：
##   godot --headless --path . --script res://tests/run_tests.gd
## 退出码 0 = 全部通过，1 = 有失败。

const TEST_SCRIPTS := [
	"res://tests/test_geometry.gd",
	"res://tests/test_network.gd",
	"res://tests/test_editor.gd",
	"res://tests/test_routing.gd",
	"res://tests/test_simulation.gd",
	"res://tests/test_upgrades.gd",
	"res://tests/test_water.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_profile.gd",
	"res://tests/test_modes.gd",
	"res://tests/test_cities.gd",
	"res://tests/test_map_editor.gd",
	"res://tests/test_cloud.gd",
	"res://tests/test_fleet.gd",
	"res://tests/test_stock.gd",
	"res://tests/test_loops.gd",
	"res://tests/test_motion.gd",
	"res://tests/test_legacy.gd",
	"res://tests/test_story.gd",
]


func _initialize() -> void:
	var harness := TestHarness.new()
	for path in TEST_SCRIPTS:
		var script: GDScript = load(path)
		if script == null:
			harness.section(path)
			harness.check(false, "无法加载测试脚本")
			continue
		var module: RefCounted = script.new()
		module.run(harness)
	print("")
	if harness.failures.is_empty():
		print("TESTS PASSED (%d checks)" % harness.checks)
		quit(0)
	else:
		for failure in harness.failures:
			print("FAIL ", failure)
		print("TESTS FAILED (%d failures / %d checks)" % [harness.failures.size(), harness.checks])
		quit(1)
