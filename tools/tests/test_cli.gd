extends TestCase


func test_flags_and_values() -> void:
	var a := Cli.parse(PackedStringArray(["--host", "--bots=2", "--join", "10.0.0.5:27015", "--conditioner=bad"]))
	assert_eq(a["host"], true)
	assert_eq(a["bots"], "2")
	assert_eq(a["join"], "10.0.0.5:27015")
	assert_eq(a["conditioner"], "bad")


func test_flag_followed_by_flag() -> void:
	var a := Cli.parse(PackedStringArray(["--start", "--expect=1"]))
	assert_eq(a["start"], true)
	assert_eq(a["expect"], "1")


func test_empty() -> void:
	assert_eq(Cli.parse(PackedStringArray()).size(), 0)
