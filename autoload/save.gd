extends Node
## 存档与设置：读写 user://profile.json，并把设置应用到音频 / 窗口 / 语言。
## 注意：在受限沙箱里 user:// 可能不可写，此时只警告、不崩溃（游戏照常运行）。

const PROFILE_PATH := "user://profile.json"

var profile: Profile = null


func _ready() -> void:
	var had_profile := FileAccess.file_exists(PROFILE_PATH)
	profile = Profile.new()
	load_profile()
	ensure_player_id()
	_migrate_onboarding(had_profile)
	apply_settings()


## 第一次启动的新玩家必须取名并完成教程；功能上线前的旧存档视为已完成引导。
func _migrate_onboarding(had_profile: bool) -> void:
	if int(profile.get_setting("onboarding_version", 0)) >= 1:
		return
	if had_profile:
		profile.set_setting("has_player_name", true)
		profile.set_setting("tutorial_done", true)
	else:
		profile.set_setting("has_player_name", false)
		profile.set_setting("tutorial_done", false)
	profile.set_setting("onboarding_version", 1)
	save_profile()


func needs_player_name() -> bool:
	return not bool(profile.get_setting("has_player_name", false))


func mark_player_name(value: String) -> void:
	profile.set_setting("player_name", value)
	profile.set_setting("has_player_name", true)
	save_profile()


func tutorial_done() -> bool:
	return bool(profile.get_setting("tutorial_done", false))


func mark_tutorial_done() -> void:
	profile.set_setting("tutorial_done", true)
	save_profile()


## 云端排行榜的匿名玩家 ID（一机一号，随档案保存）。
func ensure_player_id() -> String:
	var existing := String(profile.get_setting("player_id", ""))
	if existing != "":
		return existing
	var bytes := Crypto.new().generate_random_bytes(16)
	var hex := bytes.hex_encode()
	var pid := "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]
	profile.set_setting("player_id", pid)
	save_profile()
	return pid


func player_id() -> String:
	return ensure_player_id()


func load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var loaded := Profile.from_json(text)
	if loaded != null:
		profile = loaded


func save_profile() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入存档（user:// 不可写）: %s" % str(FileAccess.get_open_error()))
		return
	file.store_string(profile.to_json())
	file.close()


func get_setting(setting_key: String, fallback: Variant = null) -> Variant:
	return profile.get_setting(setting_key, fallback)


func set_setting(setting_key: String, value: Variant) -> void:
	profile.set_setting(setting_key, value)
	apply_settings()
	save_profile()


## 记录一局成绩（每日模式同时写当日成绩）。
func record_run(mode_key: String, score: int, daily_date: String = "") -> void:
	profile.record_score(mode_key, score)
	if daily_date != "":
		profile.record_daily(daily_date, score)
	save_profile()


func best_score(mode_key: String) -> int:
	return profile.best_score(mode_key)


func daily_best(date_string: String) -> int:
	return profile.daily_best(date_string)


func daily_attempt_used(date_string: String) -> bool:
	return profile.daily_attempt_used(date_string)


func mark_daily_attempt(date_string: String) -> void:
	profile.mark_daily_attempt(date_string)
	save_profile()


func map_best(mode_key: String, city_id: String) -> int:
	return profile.map_best_score(mode_key, city_id)


func record_map_run(mode_key: String, city_id: String, score: int) -> void:
	profile.record_map_score(mode_key, city_id, score)
	save_profile()


func player_name() -> String:
	return String(profile.get_setting("player_name", "玩家"))


func apply_settings() -> void:
	var master := clampf(float(profile.get_setting("master_volume", 0.8)), 0.0, 1.0)
	var music := clampf(float(profile.get_setting("music_volume", 0.7)), 0.0, 1.0)
	if has_node("/root/Audio"):
		var audio := get_node("/root/Audio")
		audio.apply_volumes(master, music)
	Loc.set_language(String(profile.get_setting("language", "zh")))
	if DisplayServer.get_name() != "headless":
		var fullscreen := bool(profile.get_setting("fullscreen", false))
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
