class_name TestCase
extends RefCounted
## Minimal test base. Methods named test_* are run by tests/test_runner.gd.
## Test methods may `await` (e.g. physics frames) through `tree`.

## A node in the running scene tree that tests can parent nodes under.
var root: Node
var failures: Array[String] = []
var _current := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append("%s: %s" % [_current, message])


func assert_true(value: bool, message := "expected true") -> void:
	if not value:
		fail(message)


func assert_false(value: bool, message := "expected false") -> void:
	if value:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("expected %s, got %s %s" % [var_to_str(expected), var_to_str(actual), message])


func assert_near(actual: float, expected: float, tolerance := 0.001, message := "") -> void:
	if absf(actual - expected) > tolerance:
		fail("expected %f ± %f, got %f %s" % [expected, tolerance, actual, message])


func physics_frames(count: int) -> void:
	for i in count:
		await root.get_tree().physics_frame
