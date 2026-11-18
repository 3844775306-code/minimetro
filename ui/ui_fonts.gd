class_name UiFonts
extends RefCounted
## 桌面端继续用系统字体；Web 端浏览器拿不到系统中文字体，必须打包 Noto Sans SC。

const BUNDLED_PATH := "res://art/fonts/NotoSansSC-Regular.otf"

static var _font: Font = null


static func get_font() -> Font:
	if _font != null:
		return _font
	if OS.has_feature("web") and ResourceLoader.exists(BUNDLED_PATH):
		var packed: FontFile = load(BUNDLED_PATH)
		if packed != null:
			packed.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			packed.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
			_font = packed
			return _font
	var system := SystemFont.new()
	system.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Source Han Sans SC", "sans-serif",
	])
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_font = system
	return _font
