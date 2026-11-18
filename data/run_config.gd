class_name RunConfig
extends RefCounted
## 主菜单三轴配置：资源获取（经典/发展）× 结束与评价（无/无尽）× 开局条件（无/管理）。
## 每日挑战与新手教程是特殊配置，固定使用经典资源、非无尽、非管理。

var base: String = "classic" # classic / development
var endless := false
var manager := false
## "" / "daily" / "tutorial"
var special := ""


func _init(p_base: String = "classic", p_endless: bool = false,
		p_manager: bool = false, p_special: String = "") -> void:
	base = p_base
	endless = p_endless
	manager = p_manager
	special = p_special


static func classic() -> RunConfig:
	return RunConfig.new("classic", false, false, "")


static func development() -> RunConfig:
	return RunConfig.new("development", false, false, "")


static func daily() -> RunConfig:
	return RunConfig.new("classic", false, false, "daily")


static func tutorial() -> RunConfig:
	return RunConfig.new("classic", false, false, "tutorial")


static func from_key(mode_key: String) -> RunConfig:
	if mode_key == "daily":
		return daily()
	if mode_key == "tutorial":
		return tutorial()
	var cfg := classic()
	match mode_key:
		"endless":
			cfg.endless = true
		"manager":
			cfg.manager = true
		"development":
			cfg.base = "development"
		"development_endless":
			cfg.base = "development"
			cfg.endless = true
		"development_manager":
			cfg.base = "development"
			cfg.manager = true
		"development_endless_manager":
			cfg.base = "development"
			cfg.endless = true
			cfg.manager = true
		"classic_endless":
			cfg.endless = true
		"classic_manager":
			cfg.manager = true
		"classic_endless_manager":
			cfg.endless = true
			cfg.manager = true
	return cfg


static func from_legacy_mode(kind: int) -> RunConfig:
	match kind:
		GameMode.Kind.DAILY:
			return daily()
		GameMode.Kind.TUTORIAL:
			return tutorial()
		GameMode.Kind.ENDLESS:
			return RunConfig.new("classic", true, false, "")
		GameMode.Kind.MANAGER:
			return RunConfig.new("classic", false, true, "")
		GameMode.Kind.DEVELOPMENT:
			return development()
		_:
			return classic()


func duplicate_config() -> RunConfig:
	return RunConfig.new(base, endless, manager, special)


func key() -> String:
	if special != "":
		return special
	if base == "classic" and not endless and not manager:
		return "classic"
	if base == "classic" and endless and not manager:
		return "endless"
	if base == "classic" and not endless and manager:
		return "manager"
	if base == "development" and not endless and not manager:
		return "development"
	var parts: Array[String] = [base]
	if endless:
		parts.append("endless")
	if manager:
		parts.append("manager")
	return "_".join(parts)


func title() -> String:
	if special == "daily":
		return Loc.t("每日挑战", "Daily Challenge")
	if special == "tutorial":
		return Loc.t("新手教程", "Tutorial")
	var parts: Array[String] = [Loc.t("经典", "Classic") if base == "classic" else Loc.t("发展", "Development")]
	if endless:
		parts.append(Loc.t("无尽", "Endless"))
	if manager:
		parts.append(Loc.t("管理", "Manager"))
	return " · ".join(parts)


func resource_title() -> String:
	return Loc.t("经典", "Classic") if base == "classic" else Loc.t("发展", "Development")


func metric_key() -> String:
	if endless and is_development():
		return "coins30"
	if endless:
		return "passengers30"
	if is_development():
		return "coins"
	return "delivered"


func metric_label() -> String:
	match metric_key():
		"coins30":
			return Loc.t("平均每30秒金币", "Coins per 30s")
		"passengers30":
			return Loc.t("平均每30秒客运量", "Passengers per 30s")
		"coins":
			return Loc.t("累计金币", "Total coins")
		_:
			return Loc.t("送达人数", "Delivered")


func is_development() -> bool:
	return base == "development"


func is_daily() -> bool:
	return special == "daily"


func is_tutorial() -> bool:
	return special == "tutorial"


func is_special() -> bool:
	return special != ""


## 地图排行榜按这 8 种配置分类。
static func leaderboard_configs() -> Array[RunConfig]:
	var result: Array[RunConfig] = []
	for base in ["classic", "development"]:
		for manager in [false, true]:
			for endless in [false, true]:
				result.append(RunConfig.new(base, endless, manager, ""))
	return result
