class_name GameMode
extends RefCounted
## 模式定义：经典 / 无尽 / 每日挑战。

enum Kind { CLASSIC, ENDLESS, DAILY, MANAGER, TUTORIAL, DEVELOPMENT }

const KEYS := {
	Kind.CLASSIC: "classic",
	Kind.ENDLESS: "endless",
	Kind.DAILY: "daily",
	Kind.MANAGER: "manager",
	Kind.TUTORIAL: "tutorial",
	Kind.DEVELOPMENT: "development",
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
		Kind.MANAGER:
			return Loc.t("管理", "Manager")
		Kind.TUTORIAL:
			return Loc.t("新手教程", "Tutorial")
		Kind.DEVELOPMENT:
			return Loc.t("发展", "Development")
		_:
			return Loc.t("经典", "Classic")


static func description(kind: int) -> String:
	match kind:
		Kind.ENDLESS:
			return Loc.t("每30秒客运量 · 每+10升级",
				"Per-30s throughput · +10 upgrade")
		Kind.DAILY:
			return Loc.t("每日随机地图 · 每天1次 · 云端榜",
				"Random daily map · 1/day · cloud")
		Kind.MANAGER:
			return Loc.t("40站 · 7线5隧道 · 固定视角",
				"40 stations · 7 lines · fixed camera")
		Kind.TUTORIAL:
			return Loc.t("画线 · 环线 · 换乘 · 过河",
				"Draw · loop · transfer · bridge")
		Kind.DEVELOPMENT:
			return Loc.t("运送赚金币 · 商店购资源 · 无周奖励 · 不判负",
				"Earn coins · buy resources · no weekly · no fail")
		_:
			return Loc.t("拥堵失控即结束", "Overcrowding ends the run")


## 每日挑战种子：由日期字符串决定，同一天所有人一致。
static func daily_seed(date_string: String) -> int:
	return hash("minimetro-daily-" + date_string) & 0x7FFFFFFF


## 每日挑战地图：同一天固定随机选一张官方地图。
static func daily_city_index(date_string: String, count: int) -> int:
	if count <= 0:
		return 0
	return absi(hash("minimetro-daily-city-" + date_string)) % count


static func today() -> String:
	return Time.get_date_string_from_system()
