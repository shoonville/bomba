class_name TestCase
extends RefCounted
## Minimal headless test base. Methods named test_* are run by tools/test_runner.gd.

var _failures: PackedStringArray = []
var _current: String = ""
var _asserts: int = 0


func setup() -> void:
	pass


func teardown() -> void:
	pass


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg: String = "") -> void:
	_asserts += 1
	if not cond:
		fail("expected true. " + msg)


func assert_false(cond: bool, msg: String = "") -> void:
	_asserts += 1
	if cond:
		fail("expected false. " + msg)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	_asserts += 1
	if a != b:
		fail("expected %s == %s. %s" % [str(a), str(b), msg])


func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	_asserts += 1
	if a == b:
		fail("expected %s != %s. %s" % [str(a), str(b), msg])


func assert_near(a: float, b: float, eps: float = 1e-6, msg: String = "") -> void:
	_asserts += 1
	if absf(a - b) > eps:
		fail("expected %f ≈ %f (eps %s). %s" % [a, b, str(eps), msg])


func assert_vec_near(a: Vector3, b: Vector3, eps: float = 1e-5, msg: String = "") -> void:
	_asserts += 1
	if (a - b).length() > eps:
		fail("expected %s ≈ %s (eps %s). %s" % [a, b, str(eps), msg])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	_asserts += 1
	if not (a > b):
		fail("expected %s > %s. %s" % [str(a), str(b), msg])


func assert_lt(a: float, b: float, msg: String = "") -> void:
	_asserts += 1
	if not (a < b):
		fail("expected %s < %s. %s" % [str(a), str(b), msg])
