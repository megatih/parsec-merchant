// SPDX-License-Identifier: GPL-2.0-or-later

/// ART-074: the Metal source of the live planet, compiled once with `MTLDevice.makeLibrary(source:)` (no `.metal` file).
/// It is the GPU twin of `PlanetSphere.shade` in ParsecArt: the same orthographic ray–sphere projection, lighting and ring,
/// fed by the same `PlanetSphere.Uniforms` value and the same baked maps, so both paths agree.
enum PlanetSphereShader {
    static let vertexFunction = "planet_vertex"
    static let fragmentFunction = "planet_fragment"

    static let source = header + ringSource + fragmentSource

    private static let header = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 viewport;    // centre x, centre y, disk radius (pixels), unused
        float4 turn;        // surface turn, cloud turn (0…1), flicker phase (radians), texel width
        float4 axis;        // cos tilt, sin tilt, cos inclination, sin inclination
        float4 light;       // direction to the light in view space, ambient
        float4 atmosphere;  // rgb, strength
        float4 cloud;       // rgb, opacity
        float4 night;       // rgb, intensity
        float4 emissive;    // rgb, intensity
        float4 surface;     // specular, bump, limb darkening, cloud shadow offset
        float4 haze;        // rgb, amount
        float4 ring;        // inner radius, outer radius, opacity, seed
        float4 ringColor;   // rgb, flicker amplitude
    };

    struct VertexOut {
        float4 position [[position]];
    };

    vertex VertexOut planet_vertex(uint vid [[vertex_id]]) {
        VertexOut out;
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    static float3 toObject(float3 v, constant Uniforms &u) {
        float ct = u.axis.x, st = u.axis.y, ci = u.axis.z, si = u.axis.w;
        float3 a = float3(ct * v.x + st * v.y, ct * v.y - st * v.x, v.z);
        float3 b = float3(a.x, ci * a.y + si * a.z, ci * a.z - si * a.y);
        float ang = u.turn.x * 6.283185307179586;
        float cy = cos(ang), sy = sin(ang);
        return float3(cy * b.x - sy * b.z, b.y, sy * b.x + cy * b.z);
    }

    """

    private static let ringSource = """
    static float4 ringAt(float2 q, constant Uniforms &u, float &front) {
        front = 0.0;
        if (u.ring.z <= 0.0) { return float4(0.0); }
        float3 n = float3(-u.axis.z * u.axis.y, u.axis.z * u.axis.x, u.axis.w);
        float zp = -(n.x * q.x + n.y * q.y) / n.z;
        float3 p = float3(q, zp);
        float rho = length(p);
        float span = u.ring.y - u.ring.x;
        float t = (rho - u.ring.x) / span;
        if (t <= 0.0 || t >= 1.0) { return float4(0.0); }
        float w = 1.5 / (u.viewport.z * span) + 0.02;
        float edge = smoothstep(0.0, w, t) * (1.0 - smoothstep(1.0 - w, 1.0, t));
        float s = u.ring.w;
        float bands = 0.62 + 0.22 * sin(t * 41.0 + s) + 0.16 * sin(t * 97.0 + s * 1.7);
        float gap = 1.0 - 0.85 * (smoothstep(0.52, 0.56, t) - smoothstep(0.60, 0.64, t));
        float a = u.ring.z * edge * bands * gap;
        float3 l = u.light.xyz;
        float pl = dot(p, l);
        float3 d = p - pl * l;
        float shadow = pl < 0.0 ? 1.0 - smoothstep(0.90, 1.0, dot(d, d)) : 0.0;
        float shade = 1.0 + (0.12 - 1.0) * shadow;
        float3 c = u.ringColor.rgb * ((0.80 + 0.20 * sin(t * 23.0 + s * 0.6)) * shade);
        front = zp > 0.0 ? 1.0 : 0.0;
        return float4(c * a, a);
    }

    """

    private static let fragmentSource = """
    fragment float4 planet_fragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> albedoMap [[texture(0)]],
                                    texture2d<float> auxMap [[texture(1)]], sampler smp [[sampler(0)]]) {
        float radius = u.viewport.z;
        float2 q = float2(in.position.x - u.viewport.x, u.viewport.y - in.position.y) / radius;
        float r2 = dot(q, q);
        float r = sqrt(r2);
        float3 l = u.light.xyz;
        float front = 0.0;
        float4 ringC = ringAt(q, u, front);
        float4 result = front < 0.5 ? ringC : float4(0.0);
        float cov = clamp((1.0 - r) * radius + 0.5, 0.0, 1.0);
        if (u.atmosphere.w > 0.0 && r < 1.25) {
            float inv = 1.0 / max(r, 1e-4);
            float dayH = smoothstep(-0.30, 0.40, q.x * inv * l.x + q.y * inv * l.y);
            float fall = exp(-max(r - 1.0, 0.0) / 0.045) * (1.0 - smoothstep(1.15, 1.25, r));
            float ha = clamp(0.55 * u.atmosphere.w * fall * (0.05 + 0.95 * dayH), 0.0, 1.0);
            result = float4(u.atmosphere.rgb * ha, ha) + result * (1.0 - ha);
        }
        if (cov > 0.0) {
            float z = sqrt(max(1.0 - r2, 0.0));
            float3 n = r > 1.0 ? float3(q / r, 0.0) : float3(q, z);
            float3 o = toObject(n, u);
            float3 lo = toObject(l, u);
            float lat = asin(clamp(o.y, -1.0, 1.0));
            float lon = atan2(o.x, o.z);
            float2 uv = float2(lon / 6.283185307179586 + 0.5, 0.5 - lat / 3.141592653589793);
            float cosLat = sqrt(max(1.0 - o.y * o.y, 0.0));
            float3 east = float3(o.z, 0.0, -o.x) / max(cosLat, 1e-3);
            float3 north = cross(o, east);
            float4 alb = albedoMap.sample(smp, uv, level(0.0));
            float4 aux = auxMap.sample(smp, uv, level(0.0));
            float du = u.turn.w;
            float hE = auxMap.sample(smp, uv + float2(du, 0.0), level(0.0)).a - auxMap.sample(smp, uv - float2(du, 0.0), level(0.0)).a;
            float hN = auxMap.sample(smp, uv - float2(0.0, 2.0 * du), level(0.0)).a - auxMap.sample(smp, uv + float2(0.0, 2.0 * du), level(0.0)).a;
            float3 nb = normalize(o - (east * (hE / max(cosLat, 0.25)) + north * hN) * u.surface.y);
            float2 cuv = float2(uv.x - (u.turn.y - u.turn.x), uv.y);
            float cl = min(auxMap.sample(smp, cuv, level(0.0)).r * u.cloud.w, 1.0);
            float2 sh = float2(u.surface.w * 0.5 * dot(lo, east) / max(cosLat, 0.3), -u.surface.w * dot(lo, north));
            float cs = min(auxMap.sample(smp, cuv + sh, level(0.0)).r * u.cloud.w, 1.0);
            float ndlG = dot(o, lo);
            float ndl = dot(nb, lo);
            float soft = smoothstep(-0.10, 0.22, ndlG);
            float diff = soft * clamp(0.10 + 1.05 * max(ndl, 0.0), 0.0, 1.15);
            float3 col = alb.rgb * (diff * (1.0 - 0.5 * cs) + u.light.w);
            float3 vo = toObject(float3(0.0, 0.0, 1.0), u);
            float nh = max(dot(o, normalize(lo + vo)), 0.0);
            float spec = (pow(nh, 90.0) * 0.55 + pow(nh, 10.0) * 0.07) * alb.a * u.surface.x * soft * (1.0 - cl);
            col += float3(1.0, 0.96, 0.88) * spec;
            float cd = soft * clamp(0.18 + max(ndlG, 0.0), 0.0, 1.1) + u.light.w;
            col = mix(col, u.cloud.rgb * cd, cl);
            float nightF = (1.0 - soft) * (1.0 - soft);
            col += u.night.rgb * (aux.g * u.night.w * nightF * (1.0 - 0.7 * cl));
            float fl = 1.0 + u.ringColor.w * sin(u.turn.z + uv.x * 251.0 + uv.y * 173.0);
            col += u.emissive.rgb * (aux.b * u.emissive.w * fl * (1.0 - 0.5 * cl));
            col = mix(col, u.haze.rgb * (diff + u.light.w), u.haze.w);
            float zc = clamp(z, 0.0, 1.0);
            col *= 1.0 + (pow(zc, 0.45) - 1.0) * u.surface.z;
            float fres = pow(1.0 - zc, 3.0);
            float dayRim = smoothstep(-0.30, 0.40, ndlG);
            col += u.atmosphere.rgb * (u.atmosphere.w * fres * (0.06 + 0.94 * dayRim));
            col = clamp(col, 0.0, 1.0);
            result = float4(col * cov, cov) + result * (1.0 - cov);
        }
        if (front > 0.5) { result = ringC + result * (1.0 - ringC.a); }
        return result;
    }
    """
}
