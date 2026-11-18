extends RefCounted
## 적 몸통의 수묵담채 재질: 화선지 위에 붓으로 그리고 옅게 채색한 것처럼 보이게 한다.
## (GDD 8.3: 흑백은 이펙트에만 쓰고 캐릭터는 색을 유지한다 → 몸통 색은 담채로 남기고, 먹은 선·명암·흡수에만 쓴다)
##   - 화선지 + 담채: 미색 종이 위에 적 고유색을 고르지 않게 칠해 군데군데 종이가 비친다
##   - 담묵 명암: 실제 조명 대신, 그늘진 면에 옅은 먹을 두세 번 덧칠한 것처럼 번진 회색 층
##   - 붓 윤곽선: 상자의 모서리를 먹선으로 긋는다. 굵기가 일정하지 않고 마른 붓처럼 군데군데 끊긴다
##   - 먹 흡수: 먹 수치(ink_amount)가 오를수록 아래에서부터 먹이 종이에 스며 올라온다 (울퉁불퉁한 경계)
##   - 피격 번쩍임(flash): 흰 종이로 하얗게 빛난다
## 상자 메시(BoxMesh, 원점 중심) 전용. size에 상자 크기를 넘긴다.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 size = vec3(1.0);
uniform vec3 paper = vec3(0.5, 0.47, 0.4);    // 화선지 색 (선형 공간)
uniform vec3 tint = vec3(0.42, 0.38, 0.31);   // 담채: 적 고유색 (선형 공간)
uniform float ink_amount = 0.0;               // 0~1: 아래에서부터 먹이 스며 오른다
uniform float flash = 0.0;                    // 1이면 하얗게 번쩍
uniform float seed = 0.0;
uniform float outline_width = 0.07;           // 붓 윤곽선 굵기 (m)
uniform float holes = 1.0;                    // 담채 사이로 종이가 비치는 정도 (지형은 낮게)
uniform float stripes = 0.0;                  // 1이면 옆면에 세로 붓결 (탈 수 있는 벽 표시, arena_look.gd)

varying vec3 lp;   // 로컬 위치
varying vec3 ln;   // 로컬 법선

// sin을 쓰지 않는 해시: 입력이 커져도 GPU 정밀도 때문에 각진 얼룩이 생기지 않는다
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));   // 옥타브마다 돌려 격자 무늬(네모난 계단)를 없앤다
	p = rot * p + vec2(3.1, 5.7);                         // 첫 옥타브도 격자에서 비껴 놓는다
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = rot * p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	// 지금 그리는 면의 2D 좌표와 반폭 (어느 축을 향한 면인지로 고른다)
	vec3 an = abs(ln);
	vec2 fuv; vec2 hs; float face;
	if (an.x > an.y && an.x > an.z) { fuv = lp.zy; hs = size.zy * 0.5; face = sign(ln.x) * 1.0; }
	else if (an.y > an.z)           { fuv = lp.xz; hs = size.xz * 0.5; face = sign(ln.y) * 2.0; }
	else                            { fuv = lp.xy; hs = size.xy * 0.5; face = sign(ln.z) * 3.0; }
	float fs = mod(seed, 13.0) + face * 3.7;   // 면마다 다른 붓질 (값을 작게 유지)

	// 화선지: 큰 얼룩 + 잔 섬유
	float grain = fbm(fuv * 5.0 + fs) * 0.6 + noise(fuv * 45.0 + fs) * 0.4;
	vec3 col = paper * (0.9 + 0.12 * grain);
	// 담채: 물감을 고르지 않게 칠해 붓 자국 사이로 종이가 비친다
	float pigment = fbm(fuv * 1.6 + fs * 0.7 + vec2(0.0, lp.y * 0.6));
	float cover = mix(1.0, smoothstep(0.18, 0.46, pigment) * 0.85 + 0.15, holes);
	col = mix(col, tint * (0.88 + 0.2 * grain), cover);

	// 담묵 명암: 빛을 등진 면일수록 옅은 먹을 덧칠한다. 경계는 물에 번진 듯 울퉁불퉁
	vec3 wn = normalize((MODEL_MATRIX * vec4(ln, 0.0)).xyz);
	float l = dot(wn, normalize(vec3(-0.45, 0.8, 0.4)));
	float wn_noise = fbm(fuv * 2.2 + fs * 3.0);
	float lw = l + (wn_noise - 0.5) * 0.45;
	float wash1 = 1.0 - smoothstep(0.42, 0.55, lw);
	float wash2 = 1.0 - smoothstep(-0.2, -0.05, lw);
	col *= 1.0 - 0.32 * wash1 - 0.3 * wash2;

	// 아래로 갈수록 먹이 옅게 고인다 (바닥에 닿은 부분이 살짝 어둡다)
	float h = clamp((lp.y + size.y * 0.5) / size.y, 0.0, 1.0);
	col *= mix(0.78, 1.0, smoothstep(0.0, 0.3, h + (wn_noise - 0.5) * 0.25));

	// 먹 흡수: 아래에서 위로 스며 오른다. 경계는 종이에 번지는 먹처럼 울퉁불퉁하고 천천히 일렁인다
	float inkn = fbm(fuv * 2.6 + vec2(fs, TIME * 0.06));
	float level = ink_amount * 1.12;
	// 윗면: 가장자리부터 안쪽으로 먹이 스며든다 (먹 55%쯤부터). 탑뷰에서도 먹이 차오르는 게 보이게
	if (abs(face - 2.0) < 0.5) {   // 윗면(+Y)만
		vec2 ed_top = hs - abs(fuv);
		h = 0.55 + 0.6 * clamp(min(ed_top.x, ed_top.y) / min(hs.x, hs.y), 0.0, 1.0);
	}
	float inked = (1.0 - smoothstep(level - 0.07, level + 0.01, h + (inkn - 0.5) * 0.35)) * step(0.002, ink_amount);
	// 경계 바로 위에 번진 옅은 먹 테두리
	float halo = (1.0 - smoothstep(level, level + 0.12, h + (inkn - 0.5) * 0.35)) * step(0.002, ink_amount) * (1.0 - inked);
	// 색은 선형 값: 0.01만 돼도 화면에선 회색이 되므로 아주 낮게 잡는다
	vec3 ink_col = vec3(0.002, 0.002, 0.003) + 0.006 * inkn;
	col = mix(col, col * 0.55, halo * 0.6);
	col = mix(col, ink_col, inked);

	// 세로 붓결: 옆면에 위아래로 그은 마른 붓 자국 (탈 수 있는 벽)
	if (stripes > 0.0 && abs(face - 2.0) > 0.5 && abs(face + 2.0) > 0.5) {
		float streak = smoothstep(0.55, 0.85, fbm(vec2(fuv.x * 3.0 + fs, fuv.y * 0.12)));
		col *= 1.0 - 0.35 * stripes * streak;
	}

	// 붓 윤곽선: 모서리를 따라 굵기가 변하는 먹선, 마른 붓처럼 군데군데 끊긴다
	vec2 ed = hs - abs(fuv);
	float e = min(ed.x, ed.y);
	float along = (ed.x < ed.y) ? fuv.y : fuv.x;
	float bw = outline_width * (0.55 + 0.9 * fbm(vec2(along * 1.8, fs)));
	float line = 1.0 - smoothstep(bw * 0.55, bw, e);
	line *= mix(1.0, smoothstep(0.28, 0.5, fbm(vec2(along * 9.0, e * 30.0) + fs)), 0.7);
	col = mix(col, vec3(0.0015, 0.0015, 0.002), line);

	// 피격: 흰 종이로 번쩍
	col = mix(col, vec3(1.0), flash);
	ALBEDO = col;
}
"""

static var _shader: Shader


## 상자 몸통용 수묵담채 재질. tint: 적 고유색(선형), seed: 개체마다 다른 붓질
static func body_material(box_size: Vector3, tint: Color, seed: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("size", box_size)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("seed", seed)
	return m


## 매 프레임: 먹 비율과 피격 번쩍임을 넘긴다
static func update(m: ShaderMaterial, ink_ratio: float, flashing: bool) -> void:
	m.set_shader_parameter("ink_amount", clampf(ink_ratio, 0.0, 1.0))
	m.set_shader_parameter("flash", 1.0 if flashing else 0.0)
