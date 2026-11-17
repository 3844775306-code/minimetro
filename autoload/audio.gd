extends Node
## 程序化音频：启动时合成音效与氛围音乐，零素材依赖。
## 音效名字：station / deliver / board / upgrade / warn / gameover / click。

var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer = null
var _master_volume := 0.8
var _music_volume := 0.7


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# headless（CI / 冒烟测试）没有音频设备，跳过合成，也让退出日志更干净
	if DisplayServer.get_name() == "headless":
		return
	_build_sfx()
	_build_music()
	for i in 8:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play(sound: String) -> void:
	if not _sfx.has(sound) or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _sfx[sound]
	player.play()


## 应用音量设置（0~1 线性）；headless 下播放器为空，直接跳过。
func apply_volumes(master: float, music: float) -> void:
	_master_volume = clampf(master, 0.0, 1.0)
	_music_volume = clampf(music, 0.0, 1.0)
	for player in _players:
		player.volume_db = linear_to_db(maxf(_master_volume, 0.0001))
	if _music != null:
		_music.volume_db = linear_to_db(maxf(_master_volume * _music_volume * 0.35, 0.0001))


func _exit_tree() -> void:
	# 主动释放音频流，避免退出时 AudioServer 仍持有播放器/资源引用
	if _music != null:
		_music.stop()
		_music.stream = null
	for player in _players:
		player.stop()
		player.stream = null
	_players.clear()
	_sfx.clear()


func _build_sfx() -> void:
	_sfx["station"] = WaveGen.chime([660.0, 990.0], 0.30, 0.32)
	_sfx["deliver"] = WaveGen.blip(880.0, 1320.0, 0.14, 0.30)
	_sfx["board"] = WaveGen.blip(1200.0, 1500.0, 0.05, 0.10)
	_sfx["upgrade"] = WaveGen.chime([523.25, 659.25, 783.99], 0.55, 0.30)
	_sfx["warn"] = WaveGen.blip(240.0, 180.0, 0.30, 0.28)
	_sfx["gameover"] = WaveGen.chime([392.0, 311.13, 246.94], 1.00, 0.32)
	_sfx["click"] = WaveGen.blip(1000.0, 1000.0, 0.04, 0.08)


func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = -14.0
	add_child(_music)
	_music.stream = WaveGen.chord_loop([
		[220.00, 261.63, 329.63],
		[174.61, 220.00, 261.63],
		[196.00, 246.94, 293.66],
	], 2.2, 0.16)
	_music.play()
