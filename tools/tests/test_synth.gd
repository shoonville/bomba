extends TestCase


func test_every_named_sound_builds() -> void:
	for n in SoundSynth.names():
		var buf := SoundSynth.build(n)
		assert_gt(buf.size(), 400, "%s has samples" % n)
		assert_gt(SoundSynth.peak(buf), 0.05, "%s is not silent" % n)
		assert_lt(buf.size(), SoundSynth.RATE * 2, "%s under 2 s" % n)


func test_deterministic() -> void:
	var a := SoundSynth.build("sniper_fire")
	var b := SoundSynth.build("sniper_fire")
	assert_eq(a.size(), b.size())
	var same := true
	for i in range(0, a.size(), 97):
		if a[i] != b[i]:
			same = false
	assert_true(same, "same name gives the same samples")


func test_wav_conversion() -> void:
	var wav := SoundSynth.to_wav(SoundSynth.build("hitmarker"))
	assert_eq(wav.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(wav.mix_rate, SoundSynth.RATE)
	assert_eq(wav.data.size(), SoundSynth.build("hitmarker").size() * 2)
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	assert_true(peak > 25000 and peak <= 32767, "normalised to about -1 dB, peak %d" % peak)


func test_music_loop_length_and_seam() -> void:
	var buf := SoundSynth.build_music_menu()
	var expected := SoundSynth.samples(60.0 / 105.0 * 16.0)
	assert_eq(buf.size(), expected)
	assert_gt(SoundSynth.peak(buf), 0.3)
	var wav := SoundSynth.to_wav(buf, true)
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(wav.loop_end, buf.size())


func test_filters_and_envelopes() -> void:
	var n := SoundSynth.samples(0.1)
	var white := SoundSynth.noise(n, 5)
	var low := SoundSynth.lowpass(white, 300.0)
	assert_lt(SoundSynth.peak(low), SoundSynth.peak(white), "low-pass removes energy")
	var env := SoundSynth.env_exp(n, 0.02)
	assert_near(env[0], 1.0)
	assert_lt(env[n - 1], 0.01)
	var adsr := SoundSynth.env_adsr(n, 0.01, 0.02, 0.5, 0.02)
	assert_near(adsr[n - 1], 0.0, 0.02)
