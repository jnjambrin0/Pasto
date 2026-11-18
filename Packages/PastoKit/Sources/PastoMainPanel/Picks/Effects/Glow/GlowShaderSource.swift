/// The shader for the suggestions glow, compiled when the view is created: `swift build` does not
/// compile `.metal` files, so the source travels as a string.
///
/// What the fragment function draws:
///
/// - **Distance** — signed distance to the panel's rounded rectangle, in half-heights; negative
///   inside.
/// - **Band** — an edge mask that flickers with the noise (`bandAmount`, `bandFlame`), scaled by
///   `bandAlpha`, whitened where the noise is strong.
/// - **Focus** — at 1 (the closed scene) band and fill shrink to a spot `emberReach` points wide
///   around the reveal origin, the suggestions button; at 0 they run round the whole panel.
/// - **Burst** — while `burstWeight` is up, a soft-edged disc grows from the origin at
///   `burstSpeed` widths per second under a short envelope, brightening the band inside.
/// - **Fill** — a glow that decays inwards with `fillDepth`, eight times faster outside.
/// - **Pointer** — a small bright spot under the pointer, inside the panel, `mouseWeight` strong.
/// - **Colour** — the hues blended by closeness to the eleven lights, slightly saturated.
///
/// The colour is not premultiplied by coverage; the layer adds it to what is underneath.
nonisolated enum GlowShaderSource {
    static let vertexFunction = "glowVertex"
    static let fragmentFunction = "glowFragment"

    static let code = """
        #include <metal_stdlib>
        using namespace metal;

        struct GlowUniforms {
            float sizeX; float sizeY; float scale; float cornerRadius;
            float originX; float originY; float burstTime; float burstWeight;
            float noiseX; float noiseY; float noiseZ;
            float bandAlpha; float bandFlame; float bandAmount; float bandIntensity;
            float fillAlpha; float fillIntensity; float fillDepth; float focus;
            float mouseX; float mouseY; float mouseWeight; float emberReach;
            float burstSpeed; float burstDuration; float burstIntensity;
        };

        struct GlowVertexOut {
            float4 position [[position]];
            // 0...1 across the view, from its top-left corner.
            float2 uv;
        };

        // One triangle that covers the whole view.
        vertex GlowVertexOut glowVertex(uint vertexID [[vertex_id]]) {
            float2 corner = float2(float((vertexID << 1) & 2), float(vertexID & 2));
            GlowVertexOut out;
            out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
            out.uv = float2(corner.x, 1.0 - corner.y);
            return out;
        }

        static float smoothUnit(float x) {
            float k = saturate(x);
            return k * k * (3.0 - 2.0 * k);
        }

        // How much band there is at a signed distance s (half-heights) from the edge.
        static float edgeMask(float s, float amount, float flame, float n) {
            float t = (s < 0.0 ? -s : 4.0 * s) * 2.1 / max(flame, 0.05);
            float g = n * amount;
            float tongue = saturate(pow(max(4.0 - 2.0 * g, 0.05), -60.0 * (t - 0.05 * g)));
            float m = mix(0.7, 1.2, amount);
            float core = exp2((90.0 * m - 120.0) * t) - 0.05 * m * max(0.0, 1.0 - 4.0 * t);
            float flare = 0.8 * tongue;
            return flare * (n + 0.7) / sqrt(flare * flare + 1.0) + 2.0 * n * core / sqrt(core * core + 1.0);
        }

        fragment float4 glowFragment(GlowVertexOut in [[stage_in]],
                                     constant GlowUniforms &u [[buffer(0)]],
                                     constant float2 *lights [[buffer(1)]],
                                     constant float4 *hues [[buffer(2)]],
                                     texture3d<float> noise [[texture(0)]],
                                     sampler noiseSampler [[sampler(0)]]) {
            float2 size = float2(u.sizeX, u.sizeY);
            float2 uv = in.uv;
            float2 point = uv * size;
            float aspect = size.y / size.x;
            // Width-normalised and centred: the space of the origin, the pointer and the lights.
            float2 q = float2(uv.x - 0.5, (uv.y - 0.5) * aspect);
            float n = noise.sample(noiseSampler, float3(0.5 * uv.x + u.noiseX, 0.5 * aspect * uv.y + u.noiseY, u.noiseZ)).r;

            // Signed distance to the rounded rectangle in half-widths, then in half-heights.
            float2 centred = float2(2.0 * uv.x - 1.0, (2.0 * uv.y - 1.0) * aspect);
            float radius = u.cornerRadius / (0.5 * size.x);
            float2 d = abs(centred) - float2(1.0, aspect) + radius;
            float edge = min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - radius;
            float s = edge / aspect;

            float band = edgeMask(s, u.bandAmount, u.bandFlame, n);
            float2 origin = float2(u.originX + 0.5, u.originY / aspect + 0.5) * size;
            float spot = distance(point, origin) / max(u.emberReach, 1.0);
            float focus = mix(1.0, exp(-spot * spot), u.focus);

            float burst = 0.0;
            float bandGain = 0.8;
            if (u.burstTime < 9.9 && u.burstWeight > 0.001) {
                float tau = (u.burstTime - 0.0833) / max(u.burstDuration, 0.05);
                float envelope = 0.333 * pow(max(0.0, 1.0 - tau * tau), 15.0);
                float x = 3.0 * (distance(q, float2(u.originX, u.originY)) - u.burstSpeed * u.burstTime);
                float disc = x < 0.0 ? 1.0 : pow(max(0.0, 1.0 - x * x), 2.0);
                burst = 2.0 * u.burstWeight * envelope * disc;
                bandGain = 0.8 * (1.0 + burst);
            }
            float burstInside = smoothUnit(-200.0 * edge) * burst;

            float bandLevel = bandGain * u.bandAlpha * saturate(focus * band);
            float whiteness = min(1.1, 0.6 + 1.7 * n * n * u.bandAmount);
            float depth = s < 0.0 ? s : -8.0 * s;
            float fill = focus * (0.75 + 0.25 * n) * exp2(2.2 * depth / max(u.fillDepth, 0.05)) * u.fillAlpha;

            float pointer = distance(q, float2(u.mouseX, u.mouseY)) / 0.14;
            float mouse = 0.35 * u.mouseWeight * exp(-pointer * pointer) * smoothUnit(-20.0 * edge);

            float2 field = float2(1.5 * (uv.x - 0.5), 1.5 * aspect * (uv.y - 0.5));
            float3 colour = hues[3].rgb;
            float lit = 0.0;
            for (int i = 0; i < 11; i++) {
                float closeness = distance(lights[i], field);
                colour = mix(colour, hues[i].rgb, smoothUnit(1.0 - closeness));
                float near = saturate(1.0 - 1.6 * closeness);
                lit = max(lit, near * near);
            }
            colour = min(colour, 1.0);
            float vividness = saturate(u.fillAlpha + u.bandAmount);
            float luma = dot(colour, float3(0.2126, 0.7152, 0.0722));
            colour = mix(float3(luma), colour, 1.0 + 0.2 * vividness) * mix(0.75, 0.775, vividness);

            float fillLight = u.fillIntensity * saturate((mouse + fill) * (0.25 + 0.75 * lit));
            float bandLight = max(0.0, u.bandIntensity * (saturate(bandLevel + burstInside) + (u.burstIntensity - 1.0) * burstInside));
            float3 rgb = min((fillLight + bandLight * whiteness) * colour, 1.5);
            float alpha = saturate(min(0.35 * fillLight + bandLight, max(rgb.r, max(rgb.g, rgb.b))));
            return float4(rgb, alpha);
        }
        """
}
