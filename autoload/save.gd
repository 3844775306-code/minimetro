extends Node
## 存档与设置：读写 user://profile.json，并把设置应用到音频 / 窗口 / 语言。
## 注意：在受限沙箱里 user:// 可能不可写，此时只警告、不崩溃（游戏照常运行）。

const PROFILE_PATH := "user://profile.json"

var profile: Profile = null


func _ready() -> void:
	profile = Profile.new()
	load_profile()
	apply_settings()


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
