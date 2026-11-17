## 河道用「真实经纬度中心线 + 宽度」生成多边形（见 CityMaps.geo_band），
## 按真实城市河道的简化坐标投影到世界坐标，宽度为玩法放大，不是精确测绘数据。
class_name CityMap
extends Resource
## 一张城市地图：名字（双语）+ 河道多边形 + 初始资源。
## 河道用「中心线 + 宽度」生成多边形（见 CityMaps.band），全部是风格化示意，不是精确地理数据。

@export var id: String = ""
@export var name_zh: String = ""
@export var name_en: String = ""
@export var rivers: Array[PackedVector2Array] = []
@export var start_lines: int = 3
@export var start_trains: int = 3
@export var start_bridges: int = 2


func display_name() -> String:
	return Loc.t(name_zh, name_en)
