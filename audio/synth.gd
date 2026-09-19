class_name SoundSynth
extends RefCounted
## Procedural sound: every SFX and the menu loop are synthesised here from seeded noise and
## oscillators (DESIGN.md §6: CC0 or procedural only). Deterministic: same name → same bytes.

const RATE := 22050


static func samples(seconds: float) -> int:
	return int(seconds * RATE)


static func silence(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	b.fill(0.0)
	return b


static func noise(n: int, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0)
	return b


## Oscillator with an exponential frequency sweep. wave: sine, saw, square, tri.
static func tone(n: int, f0: float, f1: float, wave: String = "sine", phase0: float = 0.0) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	var phase := phase0
	var ratio := f1 / maxf(f0, 0.01)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var f := f0 * pow(ratio, t)
		phase += f / RATE
		var p := phase - floorf(phase)
		var v := 0.0
		match wave:
			"saw":
				v = 2.0 * p - 1.0
			"square":
				v = 1.0 if p < 0.5 else -1.0
			"tri":
				v = 4.0 * absf(p - 0.5) - 1.0
			_:
				v = sin(p * TAU)
		b[i] = v
	return b


static func env_exp(n: int, decay_seconds: float, hold_seconds: float = 0.0) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	var hold := samples(hold_seconds)
	for i in n:
		var t := float(maxi(i - hold, 0)) / RATE
		b[i] = exp(-t / maxf(decay_seconds, 0.0005))
	return b


static func env_adsr(n: int, a: float, d: float, s_level: float, r: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	var na := samples(a)
	var nd := samples(d)
	var nr := samples(r)
	for i in n:
		var v := s_level
		if i < na:
			v = float(i) / maxi(na, 1)
		elif i < na + nd:
			v = lerpf(1.0, s_level, float(i - na) / maxi(nd, 1))
		if i >= n - nr:
			v *= float(n - i) / maxi(nr, 1)
		b[i] = v
	return b


static func lowpass(src: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	var rc := 1.0 / (TAU * maxf(cutoff_hz, 1.0))
	var dt := 1.0 / RATE
	var a := dt / (rc + dt)
	var y := 0.0
	for i in src.size():
		y += a * (src[i] - y)
		out[i] = y
	return out


static func highpass(src: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var low := lowpass(src, cutoff_hz)
	var out := PackedFloat32Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = src[i] - low[i]
	return out


static func mul(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := mini(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = a[i] * b[i]
	return out


## dst += src * g, starting at offset samples (dst grows if needed).
static func mix(dst: PackedFloat32Array, src: PackedFloat32Array, g: float = 1.0, offset: int = 0) -> PackedFloat32Array:
	var need := offset + src.size()
	if dst.size() < need:
		var old := dst.size()
		dst.resize(need)
		for i in range(old, need):
			dst[i] = 0.0
	for i in src.size():
		dst[offset + i] += src[i] * g
	return dst


static func gain(a: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i] * g
	return out


static func softclip(a: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = tanh(a[i] * drive)
	return out


static func peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for v in a:
		p = maxf(p, absf(v))
	return p


static func to_wav(buf: PackedFloat32Array, loop: bool = false, normalize_to: float = 0.9) -> AudioStreamWAV:
	var p := peak(buf)
	var g := (normalize_to / p) if p > 0.0001 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	return wav


static func names() -> PackedStringArray:
	return PackedStringArray(["sniper_fire", "ar_fire", "hitmarker", "headshot", "kill", "death", "hurt",
		"bolt", "reload_start", "reload_end", "dry", "swap", "jump", "land", "footstep", "respawn",
		"ui_hover", "ui_click", "ui_back", "round_start", "round_end", "dice", "coin", "shell_in"])


## Build a named sound as float samples. Unknown names return a short click so a typo is audible.
static func build(name: String) -> PackedFloat32Array:
	match name:
		"sniper_fire":
			var n := samples(0.95)
			var crack := mul(lowpass(noise(n, 11), 3200.0), env_exp(n, 0.07))
			var boom := mul(tone(n, 190.0, 42.0, "sine"), env_exp(n, 0.26))
			var tail := mul(lowpass(noise(n, 12), 700.0), env_exp(n, 0.42, 0.03))
			var out := mix(silence(n), crack, 1.0)
			out = mix(out, boom, 1.1)
			out = mix(out, tail, 0.45)
			return softclip(out, 2.2)
		"ar_fire":
			# Crisp, not a thud (Sean): a hard 1.5–7 kHz snap, a mid crack, a short low kick that
			# is over in 30 ms, and a tiny action click behind it.
			var n := samples(0.16)
			var snap := mul(lowpass(highpass(noise(n, 21), 1500.0), 7000.0), env_exp(n, 0.006))
			var crack := mul(lowpass(highpass(noise(n, 22), 900.0), 4200.0), env_exp(n, 0.018))
			var kick := mul(tone(n, 260.0, 110.0, "sine"), env_exp(n, 0.022))
			var click := mul(lowpass(noise(samples(0.015), 23), 3000.0), env_exp(samples(0.015), 0.004))
			var out := mix(silence(n), snap, 1.0)
			out = mix(out, crack, 0.8)
			out = mix(out, kick, 0.5)
			out = mix(out, click, 0.5, samples(0.035))
			return softclip(out, 2.2)
		"hitmarker":
			# Call of Duty style, take two (Sean: "too high pitched"): a woody click banded
			# 0.9–3.2 kHz, a 1.5→1.15 kHz knock and a little 320 Hz body; 60 ms, instant attack.
			var n := samples(0.06)
			var click := mul(lowpass(highpass(noise(n, 31), 900.0), 3200.0), env_exp(n, 0.0045))
			var knock := mul(tone(n, 1500.0, 1150.0, "tri"), env_exp(n, 0.02))
			var body := mul(tone(n, 320.0, 240.0, "sine"), env_exp(n, 0.017))
			var out := mix(silence(n), click, 1.0)
			out = mix(out, knock, 0.9)
			out = mix(out, body, 0.55)
			return softclip(out, 2.0)
		"headshot":
			# Two knocks 45 ms apart, the second lower, over a 200 Hz thud: heavier than a body hit.
			var n := samples(0.18)
			var c1 := mul(lowpass(highpass(noise(samples(0.06), 32), 900.0), 3200.0), env_exp(samples(0.06), 0.0045))
			var k1 := mul(tone(samples(0.06), 1500.0, 1150.0, "tri"), env_exp(samples(0.06), 0.02))
			var c2 := mul(lowpass(highpass(noise(samples(0.08), 33), 700.0), 2600.0), env_exp(samples(0.08), 0.005))
			var k2 := mul(tone(samples(0.08), 1100.0, 820.0, "tri"), env_exp(samples(0.08), 0.028))
			var thud := mul(tone(samples(0.12), 200.0, 120.0, "sine"), env_exp(samples(0.12), 0.05))
			var out := mix(silence(n), c1, 1.0)
			out = mix(out, k1, 0.9)
			out = mix(out, c2, 1.0, samples(0.045))
			out = mix(out, k2, 0.95, samples(0.045))
			out = mix(out, thud, 0.7, samples(0.04))
			return softclip(out, 2.0)
		"kill":
			var out := silence(samples(0.55))
			var notes := [659.25, 783.99, 987.77]
			for i in notes.size():
				var m := samples(0.16)
				var v := mul(lowpass(tone(m, notes[i], notes[i], "saw"), 2400.0), env_adsr(m, 0.005, 0.05, 0.6, 0.06))
				out = mix(out, v, 0.7, samples(0.11 * i))
			return mix(out, mul(lowpass(noise(samples(0.4), 41), 1500.0), env_exp(samples(0.4), 0.12)), 0.25)
		"death":
			var n := samples(0.65)
			var out := mul(lowpass(tone(n, 420.0, 70.0, "saw"), 1400.0), env_adsr(n, 0.01, 0.2, 0.5, 0.25))
			return mix(out, mul(lowpass(noise(n, 51), 500.0), env_exp(n, 0.3)), 0.4)
		"hurt":
			var n := samples(0.13)
			var out := mul(lowpass(noise(n, 61), 900.0), env_exp(n, 0.045))
			return mix(out, mul(tone(n, 210.0, 150.0, "tri"), env_exp(n, 0.06)), 0.7)
		"bolt":
			var out := silence(samples(0.34))
			var c1 := mul(lowpass(noise(samples(0.03), 71), 2500.0), env_exp(samples(0.03), 0.006))
			var c2 := mul(lowpass(noise(samples(0.04), 72), 1800.0), env_exp(samples(0.04), 0.009))
			var ring := mul(tone(samples(0.12), 950.0, 900.0, "sine"), env_exp(samples(0.12), 0.03))
			out = mix(out, c1, 1.0)
			out = mix(out, ring, 0.35, samples(0.005))
			return mix(out, c2, 1.0, samples(0.19))
		"reload_start":
			var out := silence(samples(0.12))
			out = mix(out, mul(lowpass(noise(samples(0.03), 81), 2000.0), env_exp(samples(0.03), 0.008)), 1.0)
			return mix(out, mul(tone(samples(0.08), 620.0, 480.0, "tri"), env_exp(samples(0.08), 0.03)), 0.5, samples(0.02))
		"reload_end":
			var out := silence(samples(0.18))
			out = mix(out, mul(lowpass(noise(samples(0.025), 91), 3000.0), env_exp(samples(0.025), 0.006)), 1.0)
			out = mix(out, mul(tone(samples(0.09), 700.0, 900.0, "tri"), env_exp(samples(0.09), 0.03)), 0.5, samples(0.03))
			return mix(out, mul(lowpass(noise(samples(0.03), 92), 2200.0), env_exp(samples(0.03), 0.007)), 0.9, samples(0.1))
		"dry":
			var n := samples(0.05)
			return mul(lowpass(noise(n, 101), 1600.0), env_exp(n, 0.008))
		"swap":
			var n := samples(0.16)
			var out := mul(lowpass(noise(n, 111), 1200.0), env_adsr(n, 0.03, 0.05, 0.4, 0.06))
			return mix(out, mul(lowpass(noise(samples(0.02), 112), 2500.0), env_exp(samples(0.02), 0.006)), 0.8, samples(0.1))
		"jump":
			var n := samples(0.11)
			var out := mul(tone(n, 260.0, 520.0, "tri"), env_adsr(n, 0.01, 0.04, 0.3, 0.05))
			return mix(out, mul(lowpass(noise(n, 121), 900.0), env_exp(n, 0.04)), 0.3)
		"land":
			var n := samples(0.13)
			var out := mul(tone(n, 95.0, 55.0, "sine"), env_exp(n, 0.06))
			return mix(out, mul(lowpass(noise(n, 131), 650.0), env_exp(n, 0.035)), 0.6)
		"footstep":
			var n := samples(0.075)
			var out := mul(lowpass(noise(n, 141), 750.0), env_exp(n, 0.026))
			return mix(out, mul(tone(n, 120.0, 90.0, "sine"), env_exp(n, 0.03)), 0.35)
		"respawn":
			var n := samples(0.45)
			var out := mul(tone(n, 220.0, 880.0, "sine"), env_adsr(n, 0.02, 0.1, 0.5, 0.2))
			return mix(out, mul(tone(n, 1760.0, 2200.0, "square"), env_adsr(n, 0.1, 0.1, 0.3, 0.2)), 0.18)
		"ui_hover":
			# Menu sounds, low and soft (Sean: "too high pitched and annoying"): a felt tap.
			var n := samples(0.05)
			var out := mul(tone(n, 300.0, 250.0, "tri"), env_exp(n, 0.016))
			return mix(out, mul(lowpass(noise(n, 150), 1200.0), env_exp(n, 0.005)), 0.35)
		"ui_click":
			# A woody knock: a low-passed click over a 240→190 Hz thump.
			var n := samples(0.09)
			var out := mul(lowpass(noise(n, 151), 1400.0), env_exp(n, 0.007))
			return mix(out, mul(tone(n, 240.0, 190.0, "sine"), env_exp(n, 0.03)), 0.8)
		"ui_back":
			var n := samples(0.1)
			var out := mul(lowpass(noise(n, 152), 1100.0), env_exp(n, 0.007))
			return mix(out, mul(tone(n, 190.0, 140.0, "sine"), env_exp(n, 0.035)), 0.8)
		"round_start":
			var out := silence(samples(0.6))
			out = mix(out, mul(lowpass(tone(samples(0.2), 523.25, 523.25, "square"), 2500.0), env_adsr(samples(0.2), 0.005, 0.05, 0.6, 0.08)), 0.7)
			return mix(out, mul(lowpass(tone(samples(0.35), 783.99, 783.99, "square"), 2500.0), env_adsr(samples(0.35), 0.005, 0.08, 0.6, 0.15)), 0.7, samples(0.18))
		"round_end":
			var out := silence(samples(1.0))
			var notes := [783.99, 659.25, 523.25]
			for i in notes.size():
				var m := samples(0.34)
				out = mix(out, mul(lowpass(tone(m, notes[i], notes[i] * 0.99, "saw"), 2000.0), env_adsr(m, 0.01, 0.1, 0.5, 0.15)), 0.6, samples(0.22 * i))
			return out
		"dice":
			var out := silence(samples(0.3))
			for i in 4:
				var m := samples(0.04)
				out = mix(out, mul(lowpass(noise(m, 161 + i), 3000.0 - 400.0 * i), env_exp(m, 0.008)), 0.9, samples(0.06 * i))
			return out
		"shell_in":
			# One heavy round going into the deadliest rifle (Sean: think Halo 3's shotgun): a
			# thick low-passed clack, a metal ring around 500 Hz, a deep seat thump under 100 Hz,
			# and the action closing 80 ms later. 220 ms.
			var out := silence(samples(0.24))
			out = mix(out, mul(lowpass(noise(samples(0.03), 171), 1600.0), env_exp(samples(0.03), 0.008)), 1.0)
			out = mix(out, mul(lowpass(tone(samples(0.09), 560.0, 430.0, "square"), 1800.0), env_exp(samples(0.09), 0.03)), 0.35, samples(0.01))
			out = mix(out, mul(tone(samples(0.13), 120.0, 62.0, "sine"), env_exp(samples(0.13), 0.05)), 1.0, samples(0.018))
			out = mix(out, mul(lowpass(noise(samples(0.035), 172), 1300.0), env_exp(samples(0.035), 0.009)), 0.9, samples(0.085))
			out = mix(out, mul(tone(samples(0.1), 95.0, 55.0, "sine"), env_exp(samples(0.1), 0.04)), 0.7, samples(0.09))
			return softclip(out, 1.8)
		"coin":
			var n := samples(0.22)
			var out := mul(tone(n, 1318.5, 1318.5, "square"), env_exp(n, 0.08))
			return mix(out, mul(tone(n, 1975.5, 1975.5, "square"), env_exp(n, 0.1)), 0.7, samples(0.05))
	var n := samples(0.05)
	return mul(noise(n, 1), env_exp(n, 0.01))


## The match loop: eight bars at 128 BPM in A minor for the minigames. Four-on-the-floor kick
## with a pushed extra, clap-layered snare, sixteenth hats with opens, an octave-jumping saw
## bass over a sub, off-beat chord stabs walking Am–Dm–F–G, and a triangle lead riff with
## vibrato every other pair of bars. Same seamless-loop contract as the menu loop.
static func build_music_match() -> PackedFloat32Array:
	var bpm := 128.0
	var beat := 60.0 / bpm
	var bars := 8
	var n := samples(beat * 4.0 * bars)
	var out := silence(n)
	var step := beat / 4.0
	var kick_s := samples(0.22)
	var kick := mul(tone(kick_s, 160.0, 46.0, "sine"), env_exp(kick_s, 0.08))
	var snare_s := samples(0.18)
	var snare := mix(mul(lowpass(noise(snare_s, 301), 3600.0), env_exp(snare_s, 0.06)), mul(tone(snare_s, 190.0, 150.0, "tri"), env_exp(snare_s, 0.04)), 0.5)
	snare = mix(snare, mul(lowpass(noise(snare_s, 302), 2600.0), env_exp(snare_s, 0.03)), 0.6, samples(0.011))
	var hat_s := samples(0.05)
	var hat := mul(highpass(noise(hat_s, 303), 6500.0), env_exp(hat_s, 0.012))
	var open_s := samples(0.16)
	var open_hat := mul(highpass(noise(open_s, 304), 5500.0), env_exp(open_s, 0.06))
	# bass: [step, hz, length in steps]; octave jumps on the marked steps every other bar
	var bass := [[0, 110.0, 1.5], [2, 110.0, 1.0], [4, 110.0, 1.5], [6, 130.81, 1.5], [8, 110.0, 1.5], [10, 146.83, 1.0], [12, 110.0, 1.5], [14, 98.0, 1.5]]
	var chords := [
		[220.0, 261.63, 329.63], [220.0, 261.63, 329.63], [293.66, 349.23, 440.0], [293.66, 349.23, 440.0],
		[349.23, 440.0, 523.25], [392.0, 493.88, 587.33], [220.0, 261.63, 329.63], [329.63, 415.3, 493.88],
	]
	var lead := [[0, 329.63, 2.5], [3, 392.0, 2.5], [6, 440.0, 1.5], [8, 523.25, 2.5], [11, 493.88, 1.5], [13, 440.0, 2.5]]
	for bar in bars:
		for st in 16:
			var at := samples((bar * 16 + st) * step)
			if st % 4 == 0 or (bar % 2 == 1 and st == 10):
				out = mix(out, kick, 0.95, at)
			if st == 4 or st == 12 or (bar == 7 and st == 14):
				out = mix(out, snare, 0.6, at)
			if st == 2 or st == 10:
				out = mix(out, open_hat, 0.16, at)
			else:
				out = mix(out, hat, 0.2 if st % 4 == 0 else 0.12, at)
		for b in bass:
			var f: float = b[1]
			if bar % 2 == 1 and (b[0] == 6 or b[0] == 14):
				f *= 2.0
			if bar >= 4 and bar < 6:
				f *= 1.3348  # up a fourth under the F and G bars
			var m := samples(step * float(b[2]) * 0.92)
			var v := mul(lowpass(tone(m, f, f * 0.996, "saw"), 700.0), env_adsr(m, 0.003, 0.05, 0.75, 0.03))
			v = mix(v, mul(tone(m, f * 0.5, f * 0.5, "sine"), env_adsr(m, 0.003, 0.05, 0.8, 0.03)), 0.6)
			out = mix(out, v, 0.48, samples((bar * 16 + b[0]) * step))
		for st in [3, 11]:
			var m := samples(step * 1.4)
			var stab := silence(m)
			for f in chords[bar]:
				stab = mix(stab, tone(m, f * 1.004, f * 0.996, "saw"), 0.3)
				stab = mix(stab, tone(m, f * 0.996, f * 1.004, "square"), 0.2)
			stab = mul(lowpass(stab, 2200.0), env_adsr(m, 0.004, 0.07, 0.35, 0.05))
			out = mix(out, stab, 0.3, samples((bar * 16 + st) * step))
		if bar % 4 == 2 or bar % 4 == 3:
			for l in lead:
				var m := samples(step * float(l[2]))
				var f: float = l[1] * (1.0 if bar % 4 == 2 else 1.1225)
				var v := mul(lowpass(tone(m, f, f * 1.006, "tri"), 3200.0), env_adsr(m, 0.01, 0.08, 0.6, 0.06))
				out = mix(out, v, 0.28, samples((bar * 16 + l[0]) * step))
	if out.size() > n:
		for i in range(n, out.size()):
			out[i - n] += out[i]
		out.resize(n)
	return softclip(out, 1.5)


## The menu loop: four bars of funk at 105 BPM in A minor. Kick, snare, hats, a low-passed saw
## bass and detuned chord stabs on the off-beats. Returns float samples for a seamless loop.
static func build_music_menu() -> PackedFloat32Array:
	var bpm := 105.0
	var beat := 60.0 / bpm
	var bars := 4
	var n := samples(beat * 4.0 * bars)
	var out := silence(n)
	var step := beat / 4.0  # sixteenth
	var steps := bars * 16
	# Kick pattern per bar (sixteenths): 1, the "and" of 2, 3
	var kick_steps := [0, 6, 8, 11]
	var snare_steps := [4, 12]
	var hat_steps := [0, 2, 4, 6, 8, 10, 12, 14]
	var bass := [
		[0, 110.0, 3], [3, 110.0, 1], [6, 130.81, 2], [8, 110.0, 2], [10, 98.0, 2], [12, 87.31, 2], [14, 98.0, 2],
	]
	var chords := [[6, [220.0, 261.63, 329.63]], [14, [196.0, 246.94, 293.66]]]
	var kick_s := samples(0.24)
	var kick := mul(tone(kick_s, 150.0, 48.0, "sine"), env_exp(kick_s, 0.09))
	var snare_s := samples(0.16)
	var snare := mix(mul(lowpass(noise(snare_s, 201), 3200.0), env_exp(snare_s, 0.05)), mul(tone(snare_s, 200.0, 160.0, "tri"), env_exp(snare_s, 0.04)), 0.5)
	var hat_s := samples(0.05)
	var hat := mul(highpass(noise(hat_s, 202), 6000.0), env_exp(hat_s, 0.014))
	for bar in bars:
		for st in 16:
			var at := samples((bar * 16 + st) * step)
			if kick_steps.has(st):
				out = mix(out, kick, 0.9, at)
			if snare_steps.has(st) or (bar == 3 and st == 15):
				out = mix(out, snare, 0.55, at)
			if hat_steps.has(st):
				out = mix(out, hat, 0.22 if st % 4 == 0 else 0.14, at)
		for b in bass:
			var f: float = b[1] * (1.0 if bar % 2 == 0 else 1.0)
			if bar == 3 and b[0] >= 12:
				f *= 1.1225
			var m := samples(step * b[2] * 0.9)
			var v := mul(lowpass(tone(m, f, f * 0.995, "saw"), 520.0), env_adsr(m, 0.004, 0.06, 0.7, 0.04))
			out = mix(out, v, 0.5, samples((bar * 16 + b[0]) * step))
		for c in chords:
			var m := samples(step * 1.5)
			var stab := silence(m)
			for f in c[1]:
				stab = mix(stab, tone(m, f * 1.003, f * 0.997, "saw"), 0.33)
				stab = mix(stab, tone(m, f * 0.997, f * 1.003, "saw"), 0.33)
			stab = mul(lowpass(stab, 1800.0), env_adsr(m, 0.005, 0.08, 0.4, 0.05))
			out = mix(out, stab, 0.32, samples((bar * 16 + c[0]) * step))
	# Anything that overhangs the loop end wraps to the start so the seam is silent-free.
	if out.size() > n:
		for i in range(n, out.size()):
			out[i - n] += out[i]
		out.resize(n)
	return softclip(out, 1.4)
