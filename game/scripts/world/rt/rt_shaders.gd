class_name RtShaders
extends RefCounted
## GLSL for RayTracedLighting, compiled on the player's GPU at start-up (ray
## tracing shaders can't be pre-built on machines without it, like CI).

const PARAMS := """
layout(set = 0, binding = %d, std140) uniform Params {
	mat4 inv_proj;
	mat4 view_proj;     // world -> clip
	mat4 view_to_world;
	vec4 settings;      // AO radius, AO strength, max distance, rays per pixel
	vec4 frame;         // width, height, frame, debug view
	vec4 sun_dir;       // towards the sun
	vec4 sun_color;     // linear, × energy
	vec4 ambient;       // linear, × energy; w: reflection strength
	vec4 water;         // sea level, 1 if there is a sea, time, unused
} p;
"""

## What a ray brings back.
const PAYLOAD := """
struct Hit {
	vec3 albedo;
	float t;       // < 0: missed
	vec3 normal;   // world space, facing the ray
	float pad;
};
"""

## Marks sky pixels in the AO buffer's distance channel (fits in a half float).
const SKY := 60000.0

## One thread per pixel: occlusion rays from the surface it sees, and for a
## glossy surface a mirror ray (plus a shadow ray where the mirror ray lands).
const RAYGEN := """#version 460
#extension GL_EXT_ray_tracing : require

layout(set = 0, binding = 0) uniform accelerationStructureEXT tlas;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D normal_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D ao_image;
""" + PARAMS % 4 + """
layout(set = 0, binding = 5, std430) readonly buffer Triangles {
	uvec4 tris[];
};
layout(rgba16f, set = 0, binding = 6) uniform restrict writeonly image2D refl_image;
layout(set = 0, binding = 7) uniform sampler2D color_tex;
""" + PAYLOAD + """
layout(location = 0) rayPayloadEXT Hit hit;

// Interleaved gradient noise: a per-pixel rotation that a small blur removes.
float ign(vec2 px) {
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

// A world point's pixel and the distance of what's drawn there, if on screen.
bool on_screen(vec3 wp, ivec2 size, out ivec2 spx, out float sdist) {
	vec4 clip = p.view_proj * vec4(wp, 1.0);
	if (clip.w <= 0.0) {
		return false;
	}
	vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) {
		return false;
	}
	spx = ivec2(uv * vec2(size));
	vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, texelFetch(depth_tex, spx, 0).r, 1.0);
	sdist = -vp.z / vp.w;
	return true;
}

void reflect_ray(ivec2 px, ivec2 size, vec3 origin, vec3 n, vec3 v, float amount);

void main() {
	ivec2 px = ivec2(gl_LaunchIDEXT.xy);
	ivec2 size = ivec2(p.frame.xy);
	if (px.x >= size.x || px.y >= size.y) {
		return;
	}
	imageStore(refl_image, px, vec4(0.0));
	vec2 uv = (vec2(px) + 0.5) / vec2(size);
	vec3 cam = p.view_to_world[3].xyz;
	vec4 near = p.inv_proj * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 wdir = normalize(mat3(p.view_to_world) * (near.xyz / near.w));
	float depth = texelFetch(depth_tex, px, 0).r;
	vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, max(depth, 1e-7), 1.0);
	vec3 view_pos = vp.xyz / vp.w;
	float dist = depth > 0.0 ? -view_pos.z : 60000.0;
	vec4 nr = texelFetch(normal_tex, px, 0);

	// The sea is drawn transparent, so the buffers hold the seabed under it:
	// find the water surface along the view ray instead.
	bool sea = false;
	float t_sea = 0.0;
	if (p.water.y > 0.5 && cam.y > p.water.x && wdir.y < -1e-4) {
		t_sea = (p.water.x - cam.y) / wdir.y;
		sea = t_sea * dot(wdir, -p.view_to_world[2].xyz) < dist;
	}
	if (sea) {
		imageStore(ao_image, px, vec4(1.0, t_sea * dot(wdir, -p.view_to_world[2].xyz), 0.0, 0.0));
		vec3 sp = cam + wdir * t_sea;
		// Gentle ripples, calmer than the water shader's (and calmer still far
		// away, where they'd only alias) so the mirror image holds together.
		float tm = p.water.z;
		float calm = 1.0 / (1.0 + t_sea * 0.03);
		vec3 wn = normalize(vec3(
			(sin(sp.x * 0.45 + tm * 0.9) * 0.012 + sin(sp.z * 0.8 - tm * 0.7) * 0.008) * calm,
			1.0,
			(cos(sp.z * 0.4 + tm * 0.8) * 0.012 + cos(sp.x * 0.7 + tm * 0.5) * 0.008) * calm));
		reflect_ray(px, size, sp + vec3(0.0, 0.05, 0.0), wn, -wdir, 1.0);
		return;
	}
	if (depth <= 0.0) {
		imageStore(ao_image, px, vec4(1.0, 60000.0, 0.0, 0.0));
		return;
	}
	vec3 n = normalize(mat3(p.view_to_world) * normalize(nr.xyz * 2.0 - 1.0));
	vec3 pos = (p.view_to_world * vec4(view_pos, 1.0)).xyz;
	vec3 origin = pos + n * (0.015 + dist * 0.0015);

	// --- Occlusion ---
	float ao = 1.0;
	if (dist < p.settings.z) {
		vec3 t = normalize(abs(n.y) < 0.99 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(1.0, 0.0, 0.0)));
		vec3 b = cross(n, t);
		int rays = int(p.settings.w);
		float radius = p.settings.x;
		float r1 = ign(vec2(px));
		float r2 = ign(vec2(px) + vec2(47.0, 17.0));
		float occ = 0.0;
		for (int i = 0; i < rays; i++) {
			// Cosine-weighted directions, stratified per ray and rotated per pixel.
			float u1 = fract((float(i) + r1) / float(rays));
			float phi = 6.2831853 * fract(r2 + float(i) * 0.618034);
			float r = sqrt(u1);
			vec3 dir = normalize(t * (r * cos(phi)) + b * (r * sin(phi)) + n * sqrt(max(0.0, 1.0 - u1)));
			hit.t = -1.0;
			// Back faces are culled only on instances that ask for it (character capsules).
			traceRayEXT(tlas, gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsCullBackFacingTrianglesEXT,
				0xFF, 0, 0, 0, origin, 0.0, dir, radius, 0);
			if (hit.t >= 0.0) {
				float h = hit.t / radius;
				occ += 1.0 - h * h;
			}
		}
		ao = 1.0 - occ / float(rays);
		ao = mix(ao, 1.0, smoothstep(p.settings.z * 0.7, p.settings.z, dist));
	}
	imageStore(ao_image, px, vec4(ao, dist, 0.0, 0.0));

	// --- Reflection (glossy surfaces: polished steel, lacquer) ---
	float roughness = nr.w > 0.5 ? 1.0 - nr.w : nr.w;
	roughness /= (127.0 / 255.0);
	float glossy = 1.0 - smoothstep(0.08, 0.3, roughness);
	if (glossy > 0.0) {
		reflect_ray(px, size, origin, n, normalize(cam - pos), glossy);
	}
}

// Fires a mirror ray from `origin` off a surface with normal `n` seen from
// direction `v`, and stores what it sees and how much of it shows (Fresnel
// × `amount`) in the reflection image.
void reflect_ray(ivec2 px, ivec2 size, vec3 origin, vec3 n, vec3 v, float amount) {
	amount *= p.ambient.w;
	if (amount <= 0.0) {
		return;
	}
	vec3 cam = p.view_to_world[3].xyz;
	vec3 rdir = reflect(-v, n);
	if (dot(rdir, n) <= 0.0) {
		return; // a ripple tilted the mirror ray back into the surface
	}
	hit.t = -1.0;
	traceRayEXT(tlas, gl_RayFlagsOpaqueEXT | gl_RayFlagsCullBackFacingTrianglesEXT, 0xFF, 0, 0, 0,
		origin, 0.0, rdir, 400.0, 0);
	if (hit.t < 0.0) {
		if (p.frame.w > 0.5) {
			imageStore(refl_image, px, vec4(0.0, 0.0, 1.0, 1.0));
		}
		return; // the sky: Godot's own sky reflection is already there
	}
	vec3 hp = origin + rdir * hit.t;
	vec3 col;
	ivec2 spx;
	float sdist;
	vec3 fwd = -p.view_to_world[2].xyz;
	float hdist = dot(hp - cam, fwd);
	if (on_screen(hp, size, spx, sdist) && abs(sdist - hdist) < 0.03 * hdist + 0.3) {
		// The reflected point is on screen and not hidden: use its real colour.
		col = texelFetch(color_tex, spx, 0).rgb;
	} else {
		vec3 albedo = hit.albedo;
		vec3 hn = hit.normal;
		float lit = max(dot(hn, p.sun_dir.xyz), 0.0);
		if (lit > 0.0) {
			// Skipping the closest-hit stage leaves t alone on a hit; only a miss resets it.
			hit.t = 1.0;
			traceRayEXT(tlas, gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT,
				0xFF, 0, 0, 0, hp + hn * 0.05, 0.0, p.sun_dir.xyz, 500.0, 0);
			lit *= hit.t < 0.0 ? 1.0 : 0.0;
		}
		col = albedo * (p.ambient.rgb + p.sun_color.rgb * lit);
	}
	float f = 0.04 + 0.96 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
	imageStore(refl_image, px, vec4(col, p.frame.w > 0.5 ? 1.0 : f * amount));
}
"""

const MISS := """#version 460
#extension GL_EXT_ray_tracing : require
""" + PAYLOAD + """
layout(location = 0) rayPayloadInEXT Hit hit;
void main() {
	hit.t = -1.0;
}
"""

## Looks up the triangle's colour and normal (records start at the
## instance's id).
const CLOSEST_HIT := """#version 460
#extension GL_EXT_ray_tracing : require
layout(set = 0, binding = 5, std430) readonly buffer Triangles {
	uvec4 tris[];
};
""" + PAYLOAD + """
layout(location = 0) rayPayloadInEXT Hit hit;
void main() {
	uvec4 rec = tris[gl_InstanceCustomIndexEXT + gl_PrimitiveID];
	vec3 n = normalize(mat3(gl_ObjectToWorldEXT) * uintBitsToFloat(rec.xyz));
	if (dot(n, gl_WorldRayDirectionEXT) > 0.0) {
		n = -n;
	}
	vec3 c = unpackUnorm4x8(rec.w).rgb;
	// sRGB to linear.
	hit.albedo = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	hit.normal = n;
	hit.t = gl_HitTEXT;
}
"""

const APPLY := """#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D ao_tex;
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D color_image;
""" + PARAMS % 2 + """
layout(set = 0, binding = 3) uniform sampler2D refl_tex;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(p.frame.xy);
	if (px.x >= size.x || px.y >= size.y) {
		return;
	}
	vec2 c = texelFetch(ao_tex, px, 0).rg;
	if (c.g > 50000.0) {
		if (p.frame.w > 0.5) {
			imageStore(color_image, px, vec4(1.0, 0.0, 1.0, 1.0));
		}
		return;
	}
	// Depth-aware blur: neighbours at a similar distance only, so contact
	// shadows don't bleed across silhouettes.
	float sum = 0.0;
	float wsum = 0.0;
	float tol = 0.03 * c.g + 0.05;
	for (int y = -3; y <= 3; y++) {
		for (int x = -3; x <= 3; x++) {
			ivec2 q = clamp(px + ivec2(x, y), ivec2(0), size - 1);
			vec2 s = texelFetch(ao_tex, q, 0).rg;
			float w = exp(-abs(s.g - c.g) / tol) * exp(-float(x * x + y * y) / 12.0);
			sum += s.r * w;
			wsum += w;
		}
	}
	float ao = sum / max(wsum, 1e-4);
	vec4 col = imageLoad(color_image, px);
	// Reflections smeared a little up and down, as on moving water.
	vec3 csum = vec3(0.0);
	float asum = 0.0;
	float rwsum = 0.0;
	for (int k = -3; k <= 3; k++) {
		for (int j = -1; j <= 1; j++) {
			vec4 r = texelFetch(refl_tex, clamp(px + ivec2(j, k), ivec2(0), size - 1), 0);
			float w = 4.0 - abs(float(k));
			csum += r.rgb * r.a * w;
			asum += r.a * w;
			rwsum += w;
		}
	}
	vec4 refl = vec4(asum > 0.0 ? csum / asum : vec3(0.0), asum / rwsum);
	if (p.frame.w > 0.5) {
		col.rgb = refl.a > 0.0 ? refl.rgb : vec3(ao);
		imageStore(color_image, px, col);
		return;
	}
	// Glowing things (jutsu, lantern light) drawn over an occluded surface
	// keep their glow.
	float glow = smoothstep(1.0, 3.0, max(col.r, max(col.g, col.b)));
	col.rgb *= mix(1.0, ao, p.settings.y * (1.0 - glow));
	// Reflections replace even bright water: a tree in the way hides the sun's glint.
	col.rgb = mix(col.rgb, refl.rgb, clamp(refl.a, 0.0, 1.0));
	imageStore(color_image, px, col);
}
"""
