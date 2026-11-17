extends RefCounted
## 地图编辑器：河道描边、自定义地图序列化、分享码往返、CityMap 转换。

static func run(h: TestHarness) -> void:
	_test_editor_band(h)
	_test_map_share(h)


static func _test_editor_band(h: TestHarness) -> void:
	h.section("map_editor/band")
	var points := PackedVector2Array([
		Vector2(300, 500), Vector2(700, 480), Vector2(1100, 620), Vector2(1600, 560),
	])
	var band := CityMaps.editor_band(points, 100.0)
	h.check(band.size() >= 3, "编辑器河道有有效多边形")
	var area := 0.0
	for i in band.size():
		var p := band[i]
		var q := band[(i + 1) % band.size()]
		area += p.x * q.y - q.x * p.y
	h.check(absf(area) > 1000.0, "河道多边形有面积")


static func _test_map_share(h: TestHarness) -> void:
	h.section("map_editor/share")
	var points := PackedVector2Array([
		Vector2(400, 300), Vector2(800, 500), Vector2(1400, 420), Vector2(1900, 700),
	])
	var band := CityMaps.editor_band(points, 120.0)
	var map := CustomMapStore.new_map([band], 120.0, "测试地图")
	h.check(String(map["id"]).begins_with("custom_"), "自定义地图 id 前缀")
	h.eq(CustomMapStore.to_city_map(map).rivers.size(), 1, "转换为 CityMap 后保留 1 条河")

	var code := CustomMapStore.share_code(map)
	h.check(code.length() > 20, "分享码非空")
	var decoded := CustomMapStore.decode_share(code)
	h.eq(String(decoded.get("name_zh", "")), "测试地图", "分享码保留地图名")
	var city := CustomMapStore.to_city_map(decoded)
	h.eq(city.rivers.size(), 1, "分享码导入后保留河道")
	h.check(city.is_custom, "自定义地图标记为 custom（每日挑战只在官方地图里随机）")
	h.eq(CustomMapStore.decode_share("not-a-code").size(), 0, "非法分享码被拒绝")