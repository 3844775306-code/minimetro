extends Node
## 排行榜 / 云端成绩 / 地图大厅。
##
## 双后端：
## 1. Supabase（cloud/supabase_config.json 配置 URL + publishable key）
##    读写实时同步；拉取失败时保留本地缓存/示例数据，离线可玩。
## 2. 本地缓存 user://cloud_sim.json（离线 fallback + 首屏数据）。
##
## UI 只调用同步接口；联网请求在后台通过 HTTPRequest 完成，完成后发 updated 信号。

const PATH := "user://cloud_sim.json"
const CONFIG_PATH := "res://cloud/supabase_config.json"
const USER_CONFIG_PATH := "user://cloud_config.json"
## 兜底配置（即使导出包没有带上 JSON 也能联网；publishable key 可公开）
const DEFAULT_REMOTE_URL := "https://josalpkewgzritmwbocs.supabase.co"
const DEFAULT_REMOTE_KEY := "sb_publishable_4PuG8kZBuBFx-xo36sL0xA_dwBugbMu"
const REMOTE_DAILY_PATH := "/rest/v1/metro_daily_scores"
const REMOTE_BEST_PATH := "/rest/v1/metro_best_scores"
const REMOTE_MAPS_PATH := "/rest/v1/metro_maps"

signal updated

var _data := {}
var _remote_url := ""
var _remote_key := ""
var _remote_enabled := false
## 是否实际发请求：headless 测试默认只走本地缓存，避免测试写真实云端。
var _remote_live := false
var _remote_pending := 0
var _remote_loaded := false
var _remote_failed := false


func _ready() -> void:
	load_data()
	_load_config()
	_remote_live = _remote_enabled and DisplayServer.get_name() != "headless"
	print("CLOUD_CONFIG enabled=", _remote_enabled, " live=", _remote_live,
		" url=", _remote_url)
	# 测试/headless 不自动联网，避免测试受网络影响；游戏窗口/移动端自动刷新。
	if _remote_live:
		refresh_remote()


func _load_config() -> void:
	_remote_url = DEFAULT_REMOTE_URL
	_remote_key = DEFAULT_REMOTE_KEY
	for path in [USER_CONFIG_PATH, CONFIG_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_remote_url = String(parsed.get("url", _remote_url)).strip_edges()
			_remote_key = String(parsed.get("key", _remote_key)).strip_edges()
		if _remote_url != "" and _remote_key != "":
			break
	_remote_enabled = _remote_url.begins_with("http") and _remote_key != ""


func is_remote() -> bool:
	return _remote_live


## 给 UI 显示的云端状态，避免把本地示例数据误认为真实排行。
func remote_status() -> String:
	if not _remote_live:
		return "本地数据"
	if _remote_pending > 0:
		return "云端连接中…"
	if _remote_failed:
		return "本地数据 · 云端连接失败"
	return "云端已连接" if _remote_loaded else "本地数据"


func load_data() -> void:
	_data = {}
	if FileAccess.file_exists(PATH):
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_data = parsed
	if _data.is_empty():
		_seed()
		save_data()


func save_data() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_data))
	file.close()


func player_name() -> String:
	if is_inside_tree():
		var save_node := get_node_or_null("/root/Save")
		if save_node != null:
			return save_node.player_name()
	return "玩家"


func player_id() -> String:
	if is_inside_tree():
		var save_node := get_node_or_null("/root/Save")
		if save_node != null:
			return save_node.player_id()
	return "00000000-0000-0000-0000-000000000000"


## 最近 days 天（含今天）的日期，最新在前。
func recent_dates(days: int = 7) -> Array[String]:
	var out: Array[String] = []
	var now := Time.get_unix_time_from_system()
	for i in days:
		out.append(Time.get_date_string_from_unix_time(int(now - float(i) * 86400.0)))
	return out


# ---------------------------------------------------------------------------
# 读取（先返回缓存；Supabase 拉取完成后刷新）
# ---------------------------------------------------------------------------

func daily_leaderboard(date: String, limit: int = 8) -> Array[Dictionary]:
	if _data.is_empty():
		load_data()
	var all: Array = _data.get("daily", {}).get(date, [])
	var entries: Array[Dictionary] = []
	for raw in all:
		if raw is Dictionary:
			entries.append((raw as Dictionary).duplicate())
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0)))
	if entries.size() > limit:
		entries.resize(limit)
	return entries


func recent_daily_lines(days: int = 7, per_day: int = 3) -> Array[String]:
	var lines: Array[String] = []
	for date in recent_dates(days):
		var board := daily_leaderboard(date, per_day)
		var parts: Array[String] = []
		for entry in board:
			parts.append("%s %d" % [String(entry.get("name", "?")), int(entry.get("score", 0))])
		lines.append("%s   %s" % [date, "   ".join(parts) if not parts.is_empty() else "暂无成绩"])
	return lines


func best_leaderboard(mode_key: String, city_id: String, limit: int = 8) -> Array[Dictionary]:
	if _data.is_empty():
		load_data()
	var key := "%s|%s" % [mode_key, city_id]
	var all: Array = _data.get("best", {}).get(key, [])
	var entries: Array[Dictionary] = []
	for raw in all:
		if raw is Dictionary:
			entries.append((raw as Dictionary).duplicate())
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0)))
	if entries.size() > limit:
		entries.resize(limit)
	return entries


func maps(limit: int = 20) -> Array[Dictionary]:
	if _data.is_empty():
		load_data()
	var all: Array = _data.get("maps", [])
	var result: Array[Dictionary] = []
	for raw in all:
		if raw is Dictionary:
			result.append((raw as Dictionary).duplicate())
	if result.size() > limit:
		result.resize(limit)
	return result


# ---------------------------------------------------------------------------
# 写入（本地立刻生效 + Supabase RPC 异步上传）
# ---------------------------------------------------------------------------

func submit_daily(date: String, score: int) -> void:
	if date == "":
		return
	if _data.is_empty():
		load_data()
	var daily: Dictionary = _data.get("daily", {})
	var entries: Array = daily.get(date, [])
	var pid := player_id()
	var replaced := false
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if String(entry.get("player_id", "")) == pid \
				or (String(entry.get("player_id", "")) == "" and String(entry.get("name", "")) == player_name()):
			entries.remove_at(i)
	var my_entry := {"name": player_name(), "score": score, "player_id": pid}
	entries.append(my_entry)
	daily[date] = entries
	_data["daily"] = daily
	save_data()
	emit_signal("updated")
	if _remote_live:
		_rpc("submit_daily_score", {
			"p_date": date,
			"p_player_id": pid,
			"p_display_name": player_name(),
			"p_score": score,
		})


func submit_best(mode_key: String, city_id: String, score: int) -> void:
	if _data.is_empty():
		load_data()
	var best: Dictionary = _data.get("best", {})
	var key := "%s|%s" % [mode_key, city_id]
	var entries: Array = best.get(key, [])
	var pid := player_id()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if String(entry.get("player_id", "")) == pid \
				or (String(entry.get("player_id", "")) == "" and String(entry.get("name", "")) == player_name()):
			entries.remove_at(i)
	entries.append({"name": player_name(), "score": score, "player_id": pid})
	best[key] = entries
	_data["best"] = best
	save_data()
	emit_signal("updated")
	if _remote_live:
		_rpc("submit_best_score", {
			"p_mode": mode_key,
			"p_city_id": city_id,
			"p_player_id": pid,
			"p_display_name": player_name(),
			"p_score": score,
		})


func upload_map(map: Dictionary) -> bool:
	if _data.is_empty():
		load_data()
	if not map.has("rivers") or not (map["rivers"] is Array) or map["rivers"].is_empty():
		return false
	var maps_list: Array = _data.get("maps", [])
	var copy := map.duplicate(true)
	copy["author"] = player_name()
	copy["downloads"] = int(copy.get("downloads", 0))
	copy["uploaded_at"] = Time.get_datetime_string_from_system()
	var replaced := false
	for i in maps_list.size():
		if String(maps_list[i].get("id", "")) == String(copy.get("id", "")):
			maps_list[i] = copy
			replaced = true
			break
	if not replaced:
		maps_list.append(copy)
	_data["maps"] = maps_list
	save_data()
	emit_signal("updated")
	if _remote_live:
		_rpc("upload_metro_map", {
			"p_id": String(copy.get("id", "")),
			"p_name_zh": String(copy.get("name_zh", "自定义地图")),
			"p_name_en": String(copy.get("name_en", "Custom Map")),
			"p_author": player_name(),
			"p_width": float(copy.get("width", 100.0)),
			"p_rivers": copy.get("rivers", []),
			"p_start_lines": int(copy.get("start_lines", 3)),
			"p_start_trains": int(copy.get("start_trains", 3)),
			"p_start_carriages": int(copy.get("start_carriages", 0)),
			"p_start_interchanges": int(copy.get("start_interchanges", 0)),
			"p_start_bridges": int(copy.get("start_bridges", 2)),
			"p_uploader_id": player_id(),
		})
	return true


func download_map(map_id: String) -> Dictionary:
	if _data.is_empty():
		load_data()
	var maps_list: Array = _data.get("maps", [])
	for i in maps_list.size():
		if String(maps_list[i].get("id", "")) == map_id:
			var map: Dictionary = (maps_list[i] as Dictionary).duplicate(true)
			map["downloads"] = int(map.get("downloads", 0)) + 1
			maps_list[i] = map
			_data["maps"] = maps_list
			save_data()
			if _remote_live:
				_rpc("increment_map_downloads", {"p_id": map_id})
			return map
	return {}


# ---------------------------------------------------------------------------
# Supabase 后台同步
# ---------------------------------------------------------------------------

## 手动刷新（启动时自动调用；测试/调试也可以直接调用）。
func refresh_remote() -> void:
	if not _remote_live:
		return
	_remote_pending = 3
	_remote_failed = false
	_remote_loaded = false
	var oldest := recent_dates(7)[6]
	_request(REMOTE_DAILY_PATH
		+ "?select=date,player_id,display_name,score&date=gte." + oldest
		+ "&order=date.desc,score.desc&limit=500", HTTPClient.METHOD_GET, "", _on_daily_loaded)
	_request(REMOTE_BEST_PATH
		+ "?select=mode,city_id,player_id,display_name,score&order=score.desc&limit=1000",
		HTTPClient.METHOD_GET, "", _on_best_loaded)
	_request(REMOTE_MAPS_PATH
		+ "?select=id,name_zh,name_en,author,width,rivers,start_lines,start_trains,"
		+ "start_carriages,start_interchanges,start_bridges,downloads&order=created_at.desc&limit=30",
		HTTPClient.METHOD_GET, "", _on_maps_loaded)


func _remote_done() -> void:
	_remote_pending = maxi(0, _remote_pending - 1)
	if _remote_pending == 0:
		if not _remote_failed:
			_remote_loaded = true
		emit_signal("updated")


func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["apikey: " + _remote_key, "Content-Type: application/json"])
	# Legacy anon JWT 需要 Authorization；新版 sb_publishable_* 只需 apikey。
	if _remote_key.begins_with("eyJ"):
		headers.append("Authorization: Bearer " + _remote_key)
	return headers


func _rpc(function_name: String, body: Dictionary) -> void:
	_request("/rest/v1/rpc/" + function_name, HTTPClient.METHOD_POST,
		JSON.stringify(body), _on_write_done)


func _on_write_done(code: int, response: PackedByteArray) -> void:
	if code < 200 or code >= 300:
		push_warning("Supabase 写入失败 (%d): %s" % [code, response.get_string_from_utf8()])
		return
	refresh_remote()


func _request(path: String, method: int, body: String, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers_r: PackedStringArray,
			response: PackedByteArray) -> void:
		callback.call(code, response)
		http.queue_free()
	)
	var err := http.request(_remote_url + path, _headers(), method, body)
	if err != OK:
		http.queue_free()
		callback.call(0, PackedByteArray())


func _json_array(response: PackedByteArray) -> Array:
	var parsed: Variant = JSON.parse_string(response.get_string_from_utf8())
	return parsed if parsed is Array else []


func _on_daily_loaded(code: int, response: PackedByteArray) -> void:
	if code >= 200 and code < 300:
		var rows := _json_array(response)
		var grouped := {}
		for row in rows:
			if not (row is Dictionary):
				continue
			var data: Dictionary = row
			var date := String(data.get("date", ""))
			if date == "":
				continue
			if not grouped.has(date):
				grouped[date] = []
			grouped[date].append({
				"name": String(data.get("display_name", "?")),
				"score": int(data.get("score", 0)),
				"player_id": String(data.get("player_id", "")),
			})
		_data["daily"] = grouped
		save_data()
		print("CLOUD_REMOTE daily days=", grouped.size())
	else:
		_remote_failed = true
		push_warning("Supabase 每日榜读取失败 (%d)" % code)
	_remote_done()


func _on_best_loaded(code: int, response: PackedByteArray) -> void:
	if code >= 200 and code < 300:
		var rows := _json_array(response)
		var grouped := {}
		for row in rows:
			if not (row is Dictionary):
				continue
			var data: Dictionary = row
			var key := "%s|%s" % [String(data.get("mode", "")), String(data.get("city_id", ""))]
			if not grouped.has(key):
				grouped[key] = []
			if (grouped[key] as Array).size() >= 10:
				continue
			grouped[key].append({
				"name": String(data.get("display_name", "?")),
				"score": int(data.get("score", 0)),
				"player_id": String(data.get("player_id", "")),
			})
		_data["best"] = grouped
		save_data()
		print("CLOUD_REMOTE best boards=", grouped.size())
	else:
		_remote_failed = true
		push_warning("Supabase 地图榜读取失败 (%d)" % code)
	_remote_done()


func _on_maps_loaded(code: int, response: PackedByteArray) -> void:
	if code >= 200 and code < 300:
		var rows := _json_array(response)
		var clean: Array = []
		for row in rows:
			if row is Dictionary:
				clean.append(row)
		_data["maps"] = clean
		save_data()
		print("CLOUD_REMOTE maps=", clean.size())
	else:
		_remote_failed = true
		push_warning("Supabase 地图大厅读取失败 (%d)" % code)
	_remote_done()


# ---------------------------------------------------------------------------
# 本地示例数据（离线 fallback）
# ---------------------------------------------------------------------------

func _seed() -> void:
	var players := ["林间", "Alex", "小周", "Mika", "老王", "Nina", "Kai"]
	var daily := {}
	var dates := recent_dates(7)
	for d in dates:
		var entries: Array = []
		for i in players.size():
			var base := 18 + (absi(hash(d + players[i])) % 70)
			entries.append({"name": players[i], "score": base})
		daily[d] = entries
	var best := {}
	var official: Array[String] = []
	for city in CityMaps.all():
		if not city.is_custom:
			official.append(city.id)
	for mode in ["classic", "endless", "manager"]:
		for city_id in official:
			var entries: Array = []
			for i in players.size():
				var base := 20 + (absi(hash(mode + city_id + players[i])) % 90)
				entries.append({"name": players[i], "score": base})
			best["%s|%s" % [mode, city_id]] = entries
	_data = {"daily": daily, "best": best, "maps": _seed_maps()}


func _seed_maps() -> Array:
	var maps: Array = []
	var samples := [
		{"name": "双河小镇", "author": "林间", "line": PackedVector2Array([
			Vector2(240, 200), Vector2(680, 430), Vector2(1000, 300), Vector2(1500, 600),
			Vector2(2100, 430)])},
		{"name": "环形水湾", "author": "Alex", "line": PackedVector2Array([
			Vector2(400, 1100), Vector2(800, 700), Vector2(1400, 900), Vector2(1900, 500)])},
		{"name": "北方运河", "author": "小周", "line": PackedVector2Array([
			Vector2(300, 150), Vector2(700, 500), Vector2(1300, 420), Vector2(2000, 800)])},
	]
	for i in samples.size():
		var sample: Dictionary = samples[i]
		var river := CityMaps.editor_band(sample["line"], 110.0)
		var encoded: Array = []
		for p in river:
			encoded.append([p.x, p.y])
		maps.append({
			"id": "hall_%d" % (i + 1),
			"name_zh": String(sample["name"]),
			"name_en": String(sample["name"]),
			"author": String(sample["author"]),
			"downloads": 12 + i * 7,
			"rivers": [encoded],
			"start_lines": 3,
			"start_trains": 3,
			"start_bridges": 2,
			"width": 110.0,
		})
	return maps
