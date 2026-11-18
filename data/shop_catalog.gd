class_name ShopCatalog
extends RefCounted
## 发展模式商店：用送达乘客赚到的金币购买线路 / 列车 / 车厢 / 桥隧 / 换乘站。
## 价格是游戏内运营成本，不是现实车辆采购价；乘客票价按地铁起步价折算。

const ITEMS := [
	{
		"id": "train",
		"kind": "train",
		"title_zh": "列车",
		"title_en": "Train",
		"desc_zh": "入库一列车，拖到线路上增开运力",
		"desc_en": "One train in inventory",
		"price": 45,
	},
	{
		"id": "carriage",
		"kind": "carriage",
		"title_zh": "车厢",
		"title_en": "Carriage",
		"desc_zh": "给列车加挂，单车容量 +6",
		"desc_en": "Attach to a train: +6 capacity",
		"price": 25,
	},
	{
		"id": "line",
		"kind": "line",
		"title_zh": "新线路",
		"title_en": "New Line",
		"desc_zh": "解锁一条新线路资源（不含列车）",
		"desc_en": "Unlock one more line (no train)",
		"price": 80,
	},
	{
		"id": "bridge",
		"kind": "bridge",
		"title_zh": "桥梁 / 隧道",
		"title_en": "Bridge / Tunnel",
		"desc_zh": "跨河额度 +1",
		"desc_en": "One more river crossing",
		"price": 30,
	},
	{
		"id": "interchange",
		"kind": "interchange",
		"title_zh": "换乘站",
		"title_en": "Interchange",
		"desc_zh": "换乘中心 +1，提升最拥挤站点容量",
		"desc_en": "One interchange upgrade",
		"price": 55,
	},
	{
		"id": "express",
		"kind": "express",
		"title_zh": "新干线",
		"title_en": "Shinkansen",
		"desc_zh": "高速列车，最高速为普通列车 2 倍",
		"desc_en": "High-speed train, 2x top speed",
		"price": 110,
	},
]


static func items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source in ITEMS:
		var entry: Dictionary = source
		result.append({
			"id": String(entry["id"]),
			"kind": String(entry["kind"]),
			"title": Loc.t(String(entry["title_zh"]), String(entry["title_en"])),
			"desc": Loc.t(String(entry["desc_zh"]), String(entry["desc_en"])),
			"price": int(entry["price"]),
		})
	return result


static func get_item(item_id: String) -> Dictionary:
	for entry in items():
		if String(entry["id"]) == item_id:
			return entry
	return {}
