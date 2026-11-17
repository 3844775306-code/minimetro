class_name Loc
extends RefCounted
## 极简本地化：调用处直接写 "中文" 与 "English" 两个字面量，避免维护 key 表。
## 语言由 Save 根据存档设置切换；切换后重绘 UI 即可生效。

static var language := "zh"


static func set_language(lang: String) -> void:
	language = "en" if lang == "en" else "zh"


static func is_english() -> bool:
	return language == "en"


static func t(zh: String, en: String) -> String:
	return en if language == "en" else zh
