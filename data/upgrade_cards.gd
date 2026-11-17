class_name UpgradeCards
extends RefCounted
## 周奖励卡池：id / 标题 / 描述 / 权重。
## 可用性由 Simulation 按当前资源过滤（线路/列车/车厢/桥隧上限、能否升级换乘站）。

const CARDS := {
	"line": {
		"id": "line",
		"title": "新线路",
		"desc": "可以再画一条线路，补齐网络盲区",
		"weight": 3.0,
	},
	"train": {
		"id": "train",
		"title": "列车",
		"desc": "增开一列车次，缩短乘客等车时间",
		"weight": 4.0,
	},
	"carriage": {
		"id": "carriage",
		"title": "车厢",
		"desc": "给线路加挂车厢，单车容量 +6",
		"weight": 3.0,
	},
	"bridge": {
		"id": "bridge",
		"title": "桥梁 / 隧道",
		"desc": "跨河线路每座桥消耗 1 个，额度 +1",
		"weight": 2.5,
	},
	"interchange": {
		"id": "interchange",
		"title": "换乘站",
		"desc": "把最拥挤站点的容量提升到 12",
		"weight": 2.0,
	},
}


static func get_card(card_id: String) -> Dictionary:
	return CARDS.get(card_id, {}).duplicate()
