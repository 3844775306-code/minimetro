extends RefCounted
## 发展模式：送达金币、按里程票价、商店购买、无周奖励/不判负。

static func run(h: TestHarness) -> void:
	_test_mode_definition(h)
	_test_fare_and_coins(h)
	_test_shop_purchase(h)
	_test_no_weekly_and_no_fail(h)


static func _make_level() -> LevelData:
	var level := LevelData.new()
	level.development_mode = true
	level.start_lines = 2
	level.start_trains = 0
	level.start_coins = 0
	level.station_spawn_interval = 99999.0
	level.passenger_spawn_start = 99999.0
	level.passenger_spawn_end = 99999.0
	level.overload_grace = 0.1
	level.week_seconds = 1.0
	level.max_lines = 5
	level.max_trains = 6
	level.max_carriages = 3
	level.max_bridges = 5
	level.max_interchanges = 3
	return level


static func _make_sim() -> Array:
	var level := _make_level()
	var net := MetroNetwork.new(level)
	var a := net.add_station(Vector2(100, 500), Shape.Kind.CIRCLE)
	var b := net.add_station(Vector2(900, 500), Shape.Kind.SQUARE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var sim := Simulation.new(net, level, rng)
	sim.auto_spawn = false
	return [sim, net, level, a, b]


static func _test_mode_definition(h: TestHarness) -> void:
	h.section("development/mode")
	h.eq(GameMode.key(GameMode.Kind.DEVELOPMENT), "development", "发展模式 key")
	h.check(GameMode.title(GameMode.Kind.DEVELOPMENT).contains("发展"),
		"发展模式有中文标题")


static func _test_fare_and_coins(h: TestHarness) -> void:
	h.section("development/fare")
	var made := _make_sim()
	var sim: Simulation = made[0]
	var station: Station = made[4]
	var passenger := Passenger.new(Shape.Kind.SQUARE, 0.0, Vector2(100, 500))
	# 800px 里程：起步 2 + 1 段 500px = 3
	h.eq(sim.fare_for(passenger, station), 3, "按里程计价：800px = 3 金币")
	var short_trip := Passenger.new(Shape.Kind.SQUARE, 0.0, Vector2(700, 500))
	h.eq(sim.fare_for(short_trip, station), 2, "短途按起步价 2 金币")
	h.eq(sim.coins, 0, "开局金币为 0")
	sim._earn_fare(passenger, station)
	h.eq(sim.coins, 3, "送达入账 3 金币")
	h.eq(sim.coins_earned, 3, "累计收入同步")


static func _test_shop_purchase(h: TestHarness) -> void:
	h.section("development/shop")
	var made := _make_sim()
	var sim: Simulation = made[0]
	h.check(not sim.purchase("train"), "金币不足不能购买")
	sim.coins = 500
	var trains_before := sim.inventory_trains
	h.check(sim.purchase("train"), "金币足够可购买列车")
	h.eq(sim.inventory_trains, trains_before + 1, "列车入库")
	h.eq(sim.coins, 455, "扣除列车价格 45")
	h.check(sim.purchase("line"), "购买新线路")
	h.eq(made[2].start_lines, 3, "线路资源 +1")
	h.eq(sim.coins, 375, "扣除线路价格 80")
	h.check(ShopCatalog.get_item("unknown").is_empty(), "未知商品不存在")


static func _test_no_weekly_and_no_fail(h: TestHarness) -> void:
	h.section("development/weekly")
	var made := _make_sim()
	var sim: Simulation = made[0]
	var station: Station = made[3]
	sim.elapsed = made[2].week_seconds + 2.0
	sim._update_week()
	h.check(not sim.week_pending, "发展模式不会弹出周奖励")
	for i in 10:
		station.waiting.append(Passenger.new(Shape.Kind.STAR))
	for i in 20:
		sim._update_stations(0.2)
	h.check(not sim.is_over, "发展模式不会因拥堵结束")
