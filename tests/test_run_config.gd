extends RefCounted
## 主菜单三轴配置：8 种组合、评价指标、每日/教程默认经典。

static func run(h: TestHarness) -> void:
	_test_combinations(h)
	_test_special_defaults(h)
	_test_axis_metrics(h)


static func _test_combinations(h: TestHarness) -> void:
	h.section("config/combinations")
	var configs := RunConfig.leaderboard_configs()
	h.eq(configs.size(), 8, "2×2×2 = 8 种排行榜配置")
	var keys := {}
	for config in configs:
		keys[config.key()] = true
	h.eq(keys.size(), 8, "8 种配置 key 不重复")
	h.eq(RunConfig.from_key("endless").key(), "endless", "旧无尽 key 兼容")
	h.eq(RunConfig.from_key("manager").key(), "manager", "旧管理 key 兼容")
	h.eq(RunConfig.from_key("development_endless").key(),
		"development_endless", "发展+无尽 key")
	h.check(RunConfig.from_key("classic_endless_manager").title().contains("管理"),
		"组合标题包含管理")


static func _test_special_defaults(h: TestHarness) -> void:
	h.section("config/special")
	var daily := RunConfig.daily()
	h.check(not daily.is_development() and not daily.endless and not daily.manager,
		"每日挑战默认经典/非无尽/非管理")
	var tutorial := RunConfig.tutorial()
	h.check(not tutorial.is_development() and not tutorial.endless
		and not tutorial.manager, "教程默认经典/非无尽/非管理")
	h.eq(daily.key(), "daily", "每日 key")
	h.eq(tutorial.key(), "tutorial", "教程 key")


static func _test_axis_metrics(h: TestHarness) -> void:
	h.section("config/metrics")
	var classic_endless := RunConfig.new("classic", true, false, "")
	var dev := RunConfig.new("development", false, false, "")
	var dev_endless := RunConfig.new("development", true, true, "")
	h.eq(classic_endless.metric_key(), "passengers30", "经典+无尽看客运量")
	h.eq(dev.metric_key(), "coins", "发展非无尽看累计金币")
	h.eq(dev_endless.metric_key(), "coins30", "发展+无尽看每30秒金币")
	h.check(dev_endless.metric_label().contains("30"), "发展+无尽指标文案包含 30 秒")
