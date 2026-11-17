class_name TestHarness
extends RefCounted
## 极简断言器：不依赖第三方插件，headless 下直接跑。
## 每条检查记录一次计数，失败时记录带章节前缀的消息。

var checks: int = 0
var failures: Array[String] = []
var current: String = ""


func section(name: String) -> void:
	current = name


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("[%s] %s" % [current, message])


func eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("[%s] %s (got=%s, want=%s)" % [current, message, str(actual), str(expected)])


func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("[%s] %s (got=%.4f, want=%.4f±%.4f)" % [current, message, actual, expected, tolerance])
