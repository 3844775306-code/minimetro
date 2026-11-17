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
}

var settings := {}
## 模式 key -> 最高分
var best := {}
## 日期 "YYYY-MM-DD" -> 当日最高分
var daily := {}


func _init() -> void:
	settings = DEFAULT_SETTINGS.duplicate()
	best = {}
	daily = {}


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


func to_json() -> String:
	return JSON.stringify({
		"settings": settings,
		"best": best,
		"daily": daily,
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
	return profile
