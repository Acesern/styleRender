#include <metal_stdlib>
using namespace metal;

struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct TechniqueSymbols {
    float ditherScale;
    float contrast;
    float paletteIndex;
};

vertex QuadVertexOut obraDinnVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    constexpr float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    uint index = vertexID & 3u;
    QuadVertexOut out;
    out.position = float4(positions[index], 0.0, 1.0);
    out.uv = uvs[index];
    return out;
}

static float bayer8(uint2 pixel) {
    constexpr float values[64] = {
         0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
        48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
        12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
        60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
         3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
        51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
        15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
        63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
    };

    uint x = pixel.x & 7u;
    uint y = pixel.y & 7u;
    return (values[y * 8u + x] + 0.5) / 64.0;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

fragment float4 obraDinnFragment(
    QuadVertexOut in [[stage_in]],
    texture2d<float, access::sample> colorSampler [[texture(0)]],
    depth2d<float, access::sample> depthSampler [[texture(1)]],
    constant TechniqueSymbols &symbols [[buffer(0)]]
) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

    float safeDitherScale = clamp(symbols.ditherScale > 0.0 ? symbols.ditherScale : 72.0, 24.0, 180.0);
    float safeContrast = clamp(symbols.contrast > 0.0 ? symbols.contrast : 1.35, 0.5, 3.0);
    int paletteIndex = int(round(symbols.paletteIndex));

    float3 safeInkColor = float3(0.055, 0.052, 0.043);
    float3 safePaperColor = float3(0.87, 0.82, 0.68);
    if (paletteIndex == 1) {
        safeInkColor = float3(0.13, 0.075, 0.015);
    } else if (paletteIndex == 2) {
        safeInkColor = float3(0.025, 0.12, 0.075);
    }

    float2 uv = in.uv;
    uint width = colorSampler.get_width();
    uint height = colorSampler.get_height();
    float2 viewport = float2(float(width), float(height));
    float2 texel = 1.0 / viewport;

    float depthCenter = depthSampler.sample(nearestSampler, uv);
    float3 sourceColor = colorSampler.sample(nearestSampler, uv).rgb;
    if (depthCenter >= 0.999 && length(sourceColor) < 0.002) {
        sourceColor = float3(1.0);
    }

    float shade = dot(sourceColor, float3(0.299, 0.587, 0.114));
    shade = clamp((shade - 0.5) * safeContrast + 0.5, 0.0, 1.0);
    shade = floor(shade * 8.0 + 0.5) / 8.0;

    float depthRight = depthSampler.sample(nearestSampler, uv + float2(texel.x, 0.0));
    float depthUp = depthSampler.sample(nearestSampler, uv + float2(0.0, texel.y));
    float depthEdge = max(abs(depthCenter - depthRight), abs(depthCenter - depthUp));
    float edgeInk = step(0.0025, depthEdge);

    float cellSize = clamp(144.0 / safeDitherScale, 1.0, 5.0);
    float highDensity = smoothstep(88.0, 150.0, safeDitherScale);
    float2 screenPixel = uv * viewport;
    float coarseNoise = hash21(floor(screenPixel / 16.0));
    float2 jitter = (float2(
        hash21(floor(screenPixel / 5.0) + 17.0),
        hash21(floor(screenPixel / 5.0) + 43.0)
    ) - 0.5) * highDensity * cellSize * 0.85;
    uint2 pixel = uint2((screenPixel + jitter) / cellSize);

    float ordered = bayer8(pixel);
    float blueNoise = hash21(float2(pixel) * 1.37 + coarseNoise * 19.0);
    float threshold = clamp(mix(ordered, blueNoise, highDensity * 0.42), 0.0, 1.0);

    float lineA = fmod(float(pixel.x + pixel.y), 11.0) < 1.0 ? 1.0 : 0.0;
    float lineB = fmod(float(pixel.x * 2u + pixel.y), 17.0) < 1.0 ? 1.0 : 0.0;
    float hatch = (lineA * 0.035 + lineB * 0.025) * (1.0 - smoothstep(0.18, 0.82, shade));
    float grain = (blueNoise - 0.5) * mix(0.035, 0.075, highDensity);

    float inkAmount = step(shade + hatch + grain, threshold);
    inkAmount = max(inkAmount, edgeInk);

    float paperShade = 1.0 - (1.0 - shade) * 0.16;
    float3 tonedPaper = safePaperColor * paperShade;
    float3 finalColor = mix(tonedPaper, safeInkColor, inkAmount);
    return float4(finalColor, 1.0);
}
