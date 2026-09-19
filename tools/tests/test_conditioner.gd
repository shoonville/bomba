extends TestCase


func test_profile_math() -> void:
	var c := NetConditioner.new()
	c.configure({"rtt_ms": 120, "jitter_ms": 30, "loss_percent": 3.0}, "bad", 1)
	assert_near(c.rtt_ms, 120.0)
	assert_false(c.is_passthrough())
	var lo := 1 << 30
	var hi := 0
	for i in 2000:
		var d := c._delay_usec()
		lo = mini(lo, d)
		hi = maxi(hi, d)
	# one-way delay is 60 ms ± 15 ms
	assert_true(lo >= 45000 and lo < 47000, "min delay %d" % lo)
	assert_true(hi <= 75000 and hi > 73000, "max delay %d" % hi)


func test_drop_decisions_are_seeded() -> void:
	var a := NetConditioner.new()
	a.configure({"rtt_ms": 0, "jitter_ms": 0, "loss_percent": 8.0}, "awful", 99)
	var b := NetConditioner.new()
	b.configure({"rtt_ms": 0, "jitter_ms": 0, "loss_percent": 8.0}, "awful", 99)
	var drops := 0
	for i in 5000:
		var da := a._should_drop()
		assert_eq(da, b._should_drop())
		if da:
			drops += 1
	assert_true(drops > 300 and drops < 500, "8%% of 5000 ≈ 400, got %d" % drops)


func test_lan_is_passthrough() -> void:
	var c := NetConditioner.new()
	c.configure({"rtt_ms": 0, "jitter_ms": 0, "loss_percent": 0}, "lan", 1)
	assert_true(c.is_passthrough())
	assert_false(c._should_drop())
	assert_eq(c._delay_usec(), 0)
