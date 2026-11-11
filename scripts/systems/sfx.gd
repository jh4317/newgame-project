extends Node
## 효과음: 오디오 파일 없이 코드로 합성한 소리를 재생한다.
## res://assets/sfx/<이름>.ogg|.wav|.mp3 파일이 있으면 그 파일을 대신 쓴다 → 나중에 실제 소리로 바꿔 끼우기 쉽게.
##
## 쓰는 법 (그룹 "sfx"):
##   sfx.play("swing")                         화면 전체에 들리는 소리 (플레이어 동작)
##   sfx.play_at("enemy_shoot", global_position) 플레이어와의 거리만큼 작아지는 소리 (적)
##   적처럼 참조가 없는 곳에서는 get_tree().call_group("sfx", "play_at", "rush", global_position)
##
## 히트스톱(Engine.time_scale)은 오디오에 영향을 주지 않으므로 멈춘 순간에도 소리는 그대로 난다.

const RATE := 44100
const POOL := 24                 # 동시에 날 수 있는 소리 수 (넘치면 가장 오래된 것을 끊는다)
const SAME_SOUND_GAP_MS := 30    # 같은 소리가 이보다 짧은 간격으로 겹치면 무시 (검기가 여러 적을 한꺼번에 벨 때)
const FILE_DIR := "res://assets/sfx/"

## 소리마다 기본 음량(dB)과 무작위 음높이 폭. 반복되는 소리일수록 음높이를 흔들어 단조롭지 않게
const LEVEL := {
	"swing": [-8.0, 0.08], "swing_big": [-5.0, 0.05],
	"hit": [-4.0, 0.08], "hit_heavy": [-1.0, 0.05], "wave_hit": [-9.0, 0.1],
	"kill": [-2.0, 0.06], "ink_burst": [0.0, 0.04],
	"stroke": [-3.0, 0.04], "stroke_big": [0.0, 0.03], "charge": [-10.0, 0.0],
	"parry": [-2.0, 0.03], "hurt": [-3.0, 0.05], "heal": [-16.0, 0.04],
	"jump": [-14.0, 0.05], "wall_jump": [-11.0, 0.05], "land": [-8.0, 0.08],
	"dash": [-7.0, 0.06], "slide": [-11.0, 0.08],
	"telegraph": [-12.0, 0.03], "telegraph_red": [-9.0, 0.03],
	"enemy_shoot": [-10.0, 0.08], "enemy_shoot_red": [-8.0, 0.06], "rush": [-7.0, 0.06],
	"shape": [-6.0, 0.0], "pull": [-4.0, 0.03],
	"wave_start": [-5.0, 0.0], "clear": [-4.0, 0.0],
}

@export var enabled := true
@export var master_db := 0.0
## play_at 거리 감쇠: near 안은 그대로, far에서 -falloff_db, 그 너머는 재생하지 않는다
@export var near := 8.0
@export var far := 60.0
@export var falloff_db := 18.0

var listener: Node3D  # 거리 감쇠 기준 (보통 플레이어)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_ms := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("sfx")
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()


## 이름으로 소리를 낸다. vol_db: 기본 음량에 더하는 값, pitch: 음높이 배율
func play(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(sound, -1000)) < SAME_SOUND_GAP_MS:
		return
	_last_ms[sound] = now
	var lv: Array = LEVEL.get(sound, [0.0, 0.0])
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.volume_db = master_db + float(lv[0]) + vol_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-1.0, 1.0) * float(lv[1])))
	p.play()


## 월드 위치에서 나는 소리: 플레이어에게서 멀수록 작게
func play_at(sound: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var d := 0.0
	if is_instance_valid(listener):
		d = listener.global_position.distance_to(pos)
	if d > far:
		return
	var t := clampf((d - near) / (far - near), 0.0, 1.0)
	play(sound, vol_db - t * falloff_db, pitch)


# ---------------------------------------------------------------- 합성

func _build_all() -> void:
	var recipes := {
		"swing": func(): return _whoosh(0.14, 600.0, 3400.0, 1.1),
		"swing_big": func(): return _mix([_whoosh(0.24, 350.0, 2600.0, 1.0), _whoosh(0.24, 1400.0, 5500.0, 1.4)], [1.0, 0.45]),
		"hit": func(): return _mix([_thump(0.13, 240.0, 70.0, 28.0), _burst(0.07, 55.0, 5000.0)], [1.0, 0.7]),
		"hit_heavy": func(): return _mix([_thump(0.26, 190.0, 42.0, 14.0), _burst(0.14, 26.0, 3500.0), _burst(0.02, 200.0, 9000.0)], [1.0, 0.8, 0.6]),
		"wave_hit": func(): return _mix([_burst(0.08, 50.0, 3200.0), _tone(0.08, 950.0, 600.0, "tri", 0.002, 35.0)], [0.8, 0.35]),
		"kill": func(): return _mix([_thump(0.4, 170.0, 38.0, 9.0), _burst(0.3, 13.0, 2600.0), _tone(0.32, 700.0, 170.0, "square", 0.002, 9.0)], [1.0, 0.8, 0.2]),
		"ink_burst": func(): return _mix([_thump(0.65, 130.0, 28.0, 6.0), _burst(0.55, 7.0, 1800.0), _whoosh(0.4, 3200.0, 380.0, 0.9)], [1.0, 0.75, 0.5]),
		"stroke": func(): return _mix([_whoosh(0.34, 300.0, 4200.0, 0.8), _burst(0.2, 14.0, 1400.0)], [1.0, 0.4]),
		"stroke_big": func(): return _mix([_whoosh(0.4, 250.0, 4800.0, 0.7), _thump(0.55, 110.0, 32.0, 7.0), _burst(0.3, 10.0, 1600.0)], [1.0, 1.0, 0.5]),
		"charge": func(): return _mix([_tone(0.14, 520.0, 1040.0, "tri", 0.005, 14.0), _tone(0.14, 1560.0, 1560.0, "sine", 0.002, 22.0)], [1.0, 0.3]),
		"parry": func(): return _mix([_ring([1320.0, 1985.0, 2790.0, 3960.0], 0.6, 7.0), _burst(0.015, 300.0, 9000.0), _thump(0.1, 320.0, 120.0, 30.0)], [1.0, 0.7, 0.5]),
		"hurt": func(): return _mix([_tone(0.24, 280.0, 85.0, "square", 0.002, 10.0), _burst(0.16, 18.0, 1500.0)], [0.5, 1.0]),
		"heal": func(): return _mix([_tone(0.3, 880.0, 880.0, "sine", 0.01, 10.0), _tone(0.3, 1320.0, 1320.0, "sine", 0.03, 12.0)], [1.0, 0.6]),
		"jump": func(): return _mix([_tone(0.1, 300.0, 640.0, "tri", 0.003, 24.0), _whoosh(0.1, 800.0, 2500.0, 1.2)], [1.0, 0.5]),
		"wall_jump": func(): return _mix([_tone(0.11, 360.0, 760.0, "tri", 0.003, 22.0), _burst(0.02, 150.0, 4000.0), _whoosh(0.12, 900.0, 3000.0, 1.2)], [1.0, 0.8, 0.5]),
		"land": func(): return _mix([_thump(0.13, 130.0, 50.0, 28.0), _burst(0.09, 38.0, 900.0)], [1.0, 0.8]),
		"dash": func(): return _whoosh(0.24, 380.0, 4800.0, 0.85),
		"slide": func(): return _scrape(0.38, 1300.0),
		"telegraph": func(): return _tone(0.32, 420.0, 1050.0, "sine", 0.26, 30.0),
		"telegraph_red": func(): return _mix([_tone(0.32, 190.0, 480.0, "square", 0.26, 30.0), _tone(0.32, 203.0, 512.0, "square", 0.26, 30.0)], [0.5, 0.5]),
		"enemy_shoot": func(): return _mix([_tone(0.14, 1150.0, 380.0, "square", 0.002, 18.0), _burst(0.03, 90.0, 4000.0)], [0.5, 0.6]),
		"enemy_shoot_red": func(): return _mix([_tone(0.18, 620.0, 190.0, "saw", 0.002, 14.0), _thump(0.12, 200.0, 60.0, 25.0)], [0.6, 0.8]),
		"rush": func(): return _mix([_whoosh(0.38, 180.0, 1000.0, 0.7), _tone(0.3, 110.0, 70.0, "saw", 0.02, 8.0)], [1.0, 0.35]),
		"shape": func(): return _arp([523.25, 659.25, 783.99, 1046.5], 0.0, 0.7, 5.0, "sine"),
		"pull": func(): return _mix([_whoosh(0.36, 5200.0, 280.0, 0.9), _thump(0.3, 90.0, 140.0, 9.0)], [1.0, 0.6]),
		"wave_start": func(): return _mix([_ring([196.0, 293.7, 395.0, 523.0, 788.0], 1.3, 3.0), _thump(0.4, 110.0, 50.0, 8.0)], [1.0, 0.7]),
		"clear": func(): return _arp([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.09, 0.9, 4.0, "tri"),
	}
	for sound in recipes:
		var file := _file_override(sound)
		_streams[sound] = file if file else _to_wav(recipes[sound].call())


func _file_override(sound: String) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var path := "%s%s.%s" % [FILE_DIR, sound, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a


## 띠대역 필터를 지난 잡음. 중심 주파수가 f0 → f1로 쓸려 지나간다 (휘두르기·대시의 '휙')
func _whoosh(dur: float, f0: float, f1: float, q: float) -> PackedFloat32Array:
	var a := _buf(dur)
	var low := 0.0
	var band := 0.0
	var n := a.size()
	for i in n:
		var t := float(i) / n
		var fc := f0 * pow(f1 / f0, t)
		var f := 2.0 * sin(PI * minf(fc, RATE * 0.2) / RATE)
		var x := _rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - q * band
		band += f * high
		a[i] = band * pow(sin(PI * t), 1.5)
	return a


## 음높이가 뚝 떨어지는 사인파 (타격의 '쿵')
func _thump(dur: float, f0: float, f1: float, decay: float) -> PackedFloat32Array:
	var a := _buf(dur)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var freq := f1 + (f0 - f1) * exp(-t * 22.0)
		ph += TAU * freq / RATE
		a[i] = sin(ph) * exp(-t * decay) * minf(t / 0.002, 1.0)
	return a


## 저역 통과 잡음이 터졌다 사라진다 (타격의 '팍', 먹 튀는 소리)
func _burst(dur: float, decay: float, cutoff: float) -> PackedFloat32Array:
	var a := _buf(dur)
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in a.size():
		var t := float(i) / RATE
		y += k * (_rng.randf_range(-1.0, 1.0) - y)
		a[i] = y * exp(-t * decay)
	return a


## 바닥을 긁는 잡음: 천천히 올라왔다 빠진다 (슬라이드)
func _scrape(dur: float, cutoff: float) -> PackedFloat32Array:
	var a := _buf(dur)
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	var n := a.size()
	for i in n:
		var t := float(i) / n
		y += k * (_rng.randf_range(-1.0, 1.0) - y)
		var grit := 0.7 + 0.3 * sin(TAU * 38.0 * t * dur)
		a[i] = y * minf(t / 0.12, 1.0) * pow(1.0 - t, 1.6) * grit
	return a


## 음높이가 f0 → f1로 움직이는 음. wave: sine / tri / square / saw
func _tone(dur: float, f0: float, f1: float, wave: String, attack: float, decay: float) -> PackedFloat32Array:
	var a := _buf(dur)
	var ph := 0.0
	var n := a.size()
	for i in n:
		var t := float(i) / RATE
		var freq := f0 * pow(f1 / f0, float(i) / n)
		ph = fmod(ph + freq / RATE, 1.0)
		var s := 0.0
		match wave:
			"square": s = 1.0 if ph < 0.5 else -1.0
			"saw": s = ph * 2.0 - 1.0
			"tri": s = 1.0 - 4.0 * absf(ph - 0.5)
			_: s = sin(TAU * ph)
		var env := minf(t / maxf(attack, 0.0005), 1.0)
		if t > attack:
			env *= exp(-(t - attack) * decay)
		a[i] = s * env * minf((dur - t) / 0.01, 1.0)
	return a


## 배음이 어긋난 사인파 여러 개: 쇠가 울리는 소리 (패링 '챙', 웨이브 시작 징)
func _ring(freqs: Array, dur: float, decay: float) -> PackedFloat32Array:
	var a := _buf(dur)
	for i in a.size():
		var t := float(i) / RATE
		var s := 0.0
		for j in freqs.size():
			s += sin(TAU * float(freqs[j]) * t) * exp(-t * decay * (1.0 + j * 0.5)) / (1.0 + j * 0.6)
		a[i] = s * minf(t / 0.001, 1.0)
	return a


## 음을 차례로 쌓는다 (step = 0이면 화음)
func _arp(freqs: Array, step: float, dur: float, decay: float, wave: String) -> PackedFloat32Array:
	var parts := []
	var gains := []
	for j in freqs.size():
		var pad := _buf(step * j)
		pad.append_array(_tone(dur - step * j, freqs[j], freqs[j], wave, 0.004, decay))
		parts.append(pad)
		gains.append(1.0)
	return _mix(parts, gains)


func _mix(parts: Array, gains: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for k in parts.size():
		var p: PackedFloat32Array = parts[k]
		var g: float = gains[k]
		for i in p.size():
			out[i] += p[i] * g
	return out


## 최고점을 0.9로 맞춰 16비트 WAV로
func _to_wav(a: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for x in a:
		peak = maxf(peak, absf(x))
	var g := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(a.size() * 2)
	for i in a.size():
		bytes.encode_s16(i * 2, int(clampf(a[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
