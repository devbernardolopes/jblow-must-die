shader_type canvas_item;
render_mode unshaded;


// ----------------------------------------------------
// WORMHOLE SHAPE
// ----------------------------------------------------

uniform float radius : hint_range(0.1, 0.5) = 0.485;
uniform float black_core : hint_range(0.05, 0.45) = 0.19;
uniform float inner_ring : hint_range(0.05, 0.45) = 0.27;

uniform float edge_softness : hint_range(0.001, 0.1) = 0.025;


// ----------------------------------------------------
// ANIMATION
// ----------------------------------------------------

uniform float rotation_speed : hint_range(-5.0, 5.0) = 0.22;
uniform float turbulence_speed : hint_range(0.0, 5.0) = 0.32;
uniform float swirl_strength : hint_range(0.0, 10.0) = 4.2;

uniform float turbulence_scale : hint_range(1.0, 30.0) = 9.0;
uniform float turbulence_amount : hint_range(0.0, 1.0) = 0.62;


// ----------------------------------------------------
// APPEARANCE
// ----------------------------------------------------

uniform vec4 center_color : source_color = vec4(
	0.001,
	0.005,
	0.012,
	1.0
);

uniform vec4 deep_blue : source_color = vec4(
	0.005,
	0.055,
	0.12,
	1.0
);

uniform vec4 blue : source_color = vec4(
	0.0,
	0.28,
	0.58,
	1.0
);

uniform vec4 bright_blue : source_color = vec4(
	0.05,
	0.72,
	1.0,
	1.0
);

uniform vec4 cyan : source_color = vec4(
	0.25,
	0.94,
	1.0,
	1.0
);

uniform float glow_strength : hint_range(0.0, 5.0) = 1.65;
uniform float cloud_brightness : hint_range(0.0, 3.0) = 1.15;


// ----------------------------------------------------
// EXTRA DETAIL
// ----------------------------------------------------

uniform float star_density : hint_range(0.0, 1.0) = 0.12;
uniform float star_brightness : hint_range(0.0, 5.0) = 1.6;

uniform float pulse_strength : hint_range(0.0, 0.5) = 0.055;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.15;


// ----------------------------------------------------
// GAMEPLAY CONTROL
//
// 0 = idle
// 1 = fully activated / travelling
// ----------------------------------------------------

uniform float activity : hint_range(0.0, 1.0) = 0.0;


// ----------------------------------------------------
// RANDOM / NOISE
// ----------------------------------------------------

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(
		mix(a, b, f.x),
		mix(c, d, f.x),
		f.y
	);
}


float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;

	value += noise(p) * amplitude;
	p = p * 2.03 + vec2(17.1, 9.2);
	amplitude *= 0.5;

	value += noise(p) * amplitude;
	p = p * 2.01 + vec2(7.7, 21.6);
	amplitude *= 0.5;

	value += noise(p) * amplitude;
	p = p * 2.04 + vec2(13.5, 4.4);
	amplitude *= 0.5;

	value += noise(p) * amplitude;

	return value;
}


// ----------------------------------------------------
// MAIN
// ----------------------------------------------------

void fragment() {

	// Convert UV to centered coordinates.
	vec2 p = UV - vec2(0.5);

	float dist = length(p);
	float angle = atan(p.y, p.x);

	float t = TIME;


	// ------------------------------------------------
	// Slight breathing / energy pulse
	// ------------------------------------------------

	float pulse =
		sin(t * pulse_speed) *
		pulse_strength *
		(0.35 + activity * 0.65);

	float portal_radius = radius + pulse;


	// ------------------------------------------------
	// Circular mask
	// ------------------------------------------------

	float portal_mask =
		1.0 -
		smoothstep(
			portal_radius - edge_softness,
			portal_radius,
			dist
		);


	// ------------------------------------------------
	// Polar vortex coordinates
	//
	// More rotation toward center creates the spiral.
	// ------------------------------------------------

	float normalized_radius =
		dist / max(portal_radius, 0.001);

	float center_pull =
		1.0 - clamp(normalized_radius, 0.0, 1.0);

	float spiral_angle =
		angle
		+ t * rotation_speed
		+ center_pull * swirl_strength;


	vec2 vortex_uv = vec2(
		cos(spiral_angle),
		sin(spiral_angle)
	);

	vortex_uv *=
		normalized_radius *
		turbulence_scale;


	// Pull the noise around the circle over time.
	vortex_uv += vec2(
		t * turbulence_speed,
		-t * turbulence_speed * 0.47
	);


	// ------------------------------------------------
	// Two turbulence layers
	// ------------------------------------------------

	float n1 = fbm(vortex_uv);

	float n2 = fbm(
		vortex_uv * 1.75
		+ vec2(
			t * -0.18,
			t * 0.27
		)
	);

	float turbulence =
		mix(n1, n2, 0.42);


	// Stronger variation nearer the bright ring.
	float warped_radius =
		normalized_radius
		+ (
			turbulence - 0.5
		) *
		turbulence_amount *
		0.15;


	// ------------------------------------------------
	// BLACK CENTRAL VOID
	// ------------------------------------------------

	float core =
		1.0 -
		smoothstep(
			black_core,
			black_core + 0.15,
			warped_radius
		);


	// ------------------------------------------------
	// INNER BLUE CLOUD
	// ------------------------------------------------

	float cloud_inner =
		smoothstep(
			black_core * 0.65,
			inner_ring,
			warped_radius
		);

	float cloud_outer =
		1.0 -
		smoothstep(
			0.77,
			1.0,
			warped_radius
		);

	float cloud =
		cloud_inner *
		cloud_outer;


	cloud *=
		mix(
			0.35,
			1.25,
			turbulence
		);


	// ------------------------------------------------
	// BRIGHT EVENT-HORIZON STYLE RING
	// ------------------------------------------------

	float ring_center =
		mix(
			0.66,
			0.72,
			turbulence
		);

	float ring_distance =
		abs(
			warped_radius -
			ring_center
		);

	float ring =
		1.0 -
		smoothstep(
			0.015,
			0.105,
			ring_distance
		);


	// Thin hot inner filament.
	float hot_ring =
		1.0 -
		smoothstep(
			0.008,
			0.037,
			abs(warped_radius - 0.67)
		);


	// ------------------------------------------------
	// OUTER BLUE ENERGY
	// ------------------------------------------------

	float outer_energy =
		smoothstep(
			0.68,
			0.84,
			warped_radius
		);

	outer_energy *=
		1.0 -
		smoothstep(
			0.84,
			1.0,
			warped_radius
		);

	outer_energy *=
		0.4 + turbulence * 0.9;


	// ------------------------------------------------
	// STAR / ENERGY PARTICLES
	// ------------------------------------------------

	vec2 star_grid =
		floor(
			vortex_uv * 3.0
		);

	float star_random =
		hash21(star_grid);

	float star =
		step(
			1.0 - star_density,
			star_random
		);

	star *=
		step(
			0.57,
			turbulence
		);

	star *= cloud;

	// flicker
	star *=
		0.45 +
		0.55 *
		sin(
			t * 4.0 +
			star_random * 20.0
		);


	// ------------------------------------------------
	// BUILD COLOR
	// ------------------------------------------------

	vec3 color =
		center_color.rgb;


	// Dark blue around the void.
	color =
		mix(
			color,
			deep_blue.rgb,
			cloud * 0.8
		);


	// Turbulent blue clouds.
	color +=
		blue.rgb *
		cloud *
		turbulence *
		cloud_brightness;


	// Cyan event-horizon ring.
	color +=
		bright_blue.rgb *
		ring *
		glow_strength;


	color +=
		cyan.rgb *
		hot_ring *
		glow_strength *
		0.75;


	// Outer rotating energy.
	color +=
		blue.rgb *
		outer_energy *
		0.85;


	// Small luminous points.
	color +=
		cyan.rgb *
		star *
		star_brightness;


	// Keep center genuinely black.
	color =
		mix(
			color,
			center_color.rgb,
			core * 0.92
		);


	// ------------------------------------------------
	// ACTIVATED STATE
	// ------------------------------------------------

	float activation =
		activity *
		(
			ring * 0.5 +
			outer_energy * 0.4
		);

	color +=
		cyan.rgb *
		activation *
		1.4;


	COLOR = vec4(
		color,
		portal_mask
	);
}