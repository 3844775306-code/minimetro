class_name UpgradeCards
extends RefCounted
## 周奖励卡池：中英双语的标题/描述 + 权重。
## 可用性由 Simulation 按当前资源过滤（线路/列车/车厢/桥隧上限、能否升级换乘站）。

const CARDS := {
	"line": {
		"id": "line",
		"title_zh": "新线路",
		"title_en": "New Line",
		"desc_zh": "可以再画一条线路，补齐网络盲区",
		"desc_en": "Draw another line",
		"weight": 3.0,
	},
	"train": {
		"id": "train",
		"title_zh": "列车",
		"title_en": "Train",
		"desc_zh": "增开一列车次，缩短乘客等车时间",
		"desc_en": "Add a train, shorter waits",
		"weight": 4.0,
	},
	"carriage": {
		"id": "carriage",
		"title_zh": "车厢",
		"title_en": "Carriage",
		"desc_zh": "给线路加挂车厢，单车容量 +6",
		"desc_en": "Attach a carriage: +6 capacity",
		"weight": 3.0,
	},
	"bridge": {
		"id": "bridge",
		"title_zh": "桥梁 / 隧道",
		"title_en": "Bridge / Tunnel",
		"desc_zh": "跨河线路每座桥消耗 1 个，额度 +1",
		"desc_en": "One more river crossing",
		"weight": 2.5,
	},
	"interchange": {
		"id": "interchange",
		"title_zh": "换乘站",
		"title_en": "Interchange",
		"desc_zh": "把最拥挤站点的容量提升到 12",
		"desc_en": "Upgrade a station to capacity 12",
		"weight": 2.0,
	},
}


static func get_card(card_id: String) -> Dictionary:
	var source: Dictionary = CARDS.get(card_id, {})
	if source.is_empty():
		return {}
	return {
		"id": String(source["id"]),
		"title": Loc.t(String(source["title_zh"]), String(source["title_en"])),
		"desc": Loc.t(String(source["desc_zh"]), String(source["desc_en"])),
		"weight": float(source["weight"]),
	}
