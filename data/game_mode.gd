class_name GameMode
extends RefCounted
## 模式定义：经典 / 无尽 / 每日挑战。

enum Kind { CLASSIC, ENDLESS, DAILY }

const KEYS := {
	Kind.CLASSIC: "classic",
	Kind.ENDLESS: "endless",
	Kind.DAILY: "daily",
}


static func key(kind: int) -> String:
	return String(KEYS.get(kind, "classic"))


static func from_key(mode_key: String) -> int:
	for kind in KEYS.keys():
		if String(KEYS[kind]) == mode_key:
			return int(kind)
	return Kind.CLASSIC


static func title(kind: int) -> String:
	match kind:
		Kind.ENDLESS:
			return Loc.t("无尽", "Endless")
		Kind.DAILY:
			return Loc.t("每日挑战", "Daily Challenge")
		_:
			return Loc.t("经典", "Classic")


static func description(kind: int) -> String:
	match kind:
		Kind.ENDLESS:
			return Loc.t("不会失败，考验你能撑多久", "No game over: survive!")
		Kind.DAILY:
			return Loc.t("每天同一张地图，冲本地最高分", "Same map for everyone today")
		_:
			return Loc.t("标准规则：拥堵失控即结束", "Overcrowding ends the run")


## 每日挑战种子：由日期字符串决定，同一天所有人一致。
static func daily_seed(date_string: String) -> int:
	return hash("minimetro-daily-" + date_string) & 0x7FFFFFFF


static func today() -> String:
	return Time.get_date_string_from_system()
