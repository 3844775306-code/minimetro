class_name Profile
extends RefCounted
## 玩家档案：设置 + 各模式最高分 + 每日成绩。
## 纯数据对象，文件读写交给 Save 自动加载；测试只测序列化与记录逻辑。

const DEFAULT_SETTINGS := {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"fullscreen": false,
	"language": "zh",
	"city": "paper",
	"player_name": "玩家",
	"has_player_name": false,
	"tutorial_done": false,
	"onboarding_version": 0,
	"station_remove_time": 0.8,
}

var settings := {}
## 模式 key -> 最高分
var best := {}
## 日期 "YYYY-MM-DD" -> 当日最高分
var daily := {}
## 每日挑战已用机会：日期 -> true
var daily_attempts := {}
## "mode|city_id" -> 该地图最高分
var map_best := {}


func _init() -> void:
	settings = DEFAULT_SETTINGS.duplicate()
	best = {}
	daily = {}
	daily_attempts = {}
	map_best = {}


func get_setting(setting_key: String, fallback: Variant = null) -> Variant:
	return settings.get(setting_key, fallback)


func set_setting(setting_key: String, value: Variant) -> void:
	settings[setting_key] = value


## 记录一局成绩；返回是否刷新了该模式最高分。
func record_score(mode_key: String, score: int) -> bool:
	var previous := int(best.get(mode_key, 0))
	if score > previous:
		best[mode_key] = score
		return true
	return false


func best_score(mode_key: String) -> int:
	return int(best.get(mode_key, 0))


## 记录每日成绩；返回是否刷新当日最高分。
func record_daily(date_string: String, score: int) -> bool:
	if date_string == "":
		return false
	var previous := int(daily.get(date_string, 0))
	if score > previous:
		daily[date_string] = score
		return true
	return false


func daily_best(date_string: String) -> int:
	return int(daily.get(date_string, 0))


func daily_attempt_used(date_string: String) -> bool:
	return bool(daily_attempts.get(date_string, false))


func mark_daily_attempt(date_string: String) -> void:
	if date_string != "":
		daily_attempts[date_string] = true


func map_best_score(mode_key: String, city_id: String) -> int:
	return int(map_best.get("%s|%s" % [mode_key, city_id], 0))


func record_map_score(mode_key: String, city_id: String, score: int) -> bool:
	var key := "%s|%s" % [mode_key, city_id]
	var previous := int(map_best.get(key, 0))
	if score > previous:
		map_best[key] = score
		return true
	return false


func to_json() -> String:
	return JSON.stringify({
		"settings": settings,
		"best": best,
		"daily": daily,
		"daily_attempts": daily_attempts,
		"map_best": map_best,
	})


## 解析失败时返回 null，调用方保留旧档案。
static func from_json(text: String) -> Profile:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return null
	var data: Dictionary = parsed
	var profile := Profile.new()
	var loaded_settings: Variant = data.get("settings", {})
	if loaded_settings is Dictionary:
		var source: Dictionary = loaded_settings
		for setting_key in DEFAULT_SETTINGS.keys():
			if source.has(setting_key):
				profile.settings[setting_key] = source[setting_key]
	var loaded_best: Variant = data.get("best", {})
	if loaded_best is Dictionary:
		profile.best = loaded_best.duplicate()
	var loaded_daily: Variant = data.get("daily", {})
	if loaded_daily is Dictionary:
		profile.daily = loaded_daily.duplicate()
	var loaded_attempts: Variant = data.get("daily_attempts", {})
	if loaded_attempts is Dictionary:
		profile.daily_attempts = loaded_attempts.duplicate()
	var loaded_map_best: Variant = data.get("map_best", {})
	if loaded_map_best is Dictionary:
		profile.map_best = loaded_map_best.duplicate()
	return profile
