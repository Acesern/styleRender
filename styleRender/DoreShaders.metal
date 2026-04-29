#include <metal_stdlib>
using namespace metal;

struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct DoreTechniqueSymbols {
    float hatchSpacing;
    float contrast;
    float paletteIndex;
};

static float hash21_dore(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float paperNoise(float2 uv) {
    float2 i = floor(uv * 180.0);
    float2 f = fract(uv * 180.0);
    float  a = hash21_dore(i);
    float  b = hash21_dore(i + float2(1.0, 0.0));
    float  c = hash21_dore(i + float2(0.0, 1.0));
    float  d = hash21_dore(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    float coarse = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    float fine   = hash21_dore(floor(uv * 520.0)) * 0.4;
    return coarse * 0.6 + fine * 0.4;
}

// 低频手工扰动：大 cell（~80px）平滑噪声，模拟刻刀力道变化
static float craftJitter(float2 px) {
    float2 i = floor(px / 80.0);
    float2 f = fract(px / 80.0);
    float  a = hash21_dore(i);
    float  b = hash21_dore(i + float2(1.0, 0.0));
    float  c = hash21_dore(i + float2(0.0, 1.0));
    float  d = hash21_dore(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 固定角度平行线。angle 为线条延伸方向，spacing 全局固定，lineWidth 控制粗细。
// 返回 [0,1]，1 = 在墨线上。
static float hatchLayer(float2 px, float angle, float spacing, float lineWidth) {
    float c    = cos(angle + M_PI_F * 0.5);
    float s    = sin(angle + M_PI_F * 0.5);
    float proj = px.x * c + px.y * s;
    float t    = fract(proj / spacing);
    float hw   = clamp(lineWidth * 0.5, 0.0, spacing * 0.48) / spacing;
    float aa   = 0.5 / spacing;
    return smoothstep(hw + aa, hw - aa, t) + smoothstep(1.0 - hw - aa, 1.0 - hw + aa, t);
}

fragment float4 doreFragment(
    QuadVertexOut         in           [[stage_in]],
    texture2d<float, access::sample> colorSampler [[texture(0)]],
    depth2d<float,   access::sample> depthSampler [[texture(1)]],
    constant DoreTechniqueSymbols    &symbols      [[buffer(0)]]
) {
    constexpr sampler nearestSampler(coord::normalized,
                                     address::clamp_to_edge,
                                     filter::nearest);

    float safeSpacing  = clamp(symbols.hatchSpacing > 0.0 ? symbols.hatchSpacing : 8.0,
                               3.0, 20.0);
    float safeContrast = clamp(symbols.contrast > 0.0 ? symbols.contrast : 1.5,
                               0.5, 3.0);
    int   paletteIndex = int(round(symbols.paletteIndex));

    float3 paperColor = float3(0.867, 0.831, 0.690);
    float3 inkColor   = float3(0.055, 0.048, 0.032);
    if (paletteIndex == 1) {
        paperColor = float3(0.920, 0.740, 0.380);
        inkColor   = float3(0.180, 0.080, 0.010);
    } else if (paletteIndex == 2) {
        paperColor = float3(0.720, 0.880, 0.740);
        inkColor   = float3(0.020, 0.140, 0.060);
    }

    float2 uv       = in.uv;
    uint   W        = colorSampler.get_width();
    uint   H        = colorSampler.get_height();
    float2 viewport = float2(float(W), float(H));
    float2 texel    = 1.0 / viewport;
    float2 px       = uv * viewport;

    float  depthCenter = depthSampler.sample(nearestSampler, uv);
    float3 sourceColor = colorSampler.sample(nearestSampler, uv).rgb;

    if (depthCenter >= 0.999 && length(sourceColor) < 0.002) {
        float noise = paperNoise(uv);
        return float4(paperColor * (0.94 + noise * 0.08), 1.0);
    }

    float shade = dot(sourceColor, float3(0.299, 0.587, 0.114));
    shade = clamp((shade - 0.5) * safeContrast + 0.5, 0.0, 1.0);

    // ── 深度边缘轮廓 ─────────────────────────────────────────────
    float dR  = depthSampler.sample(nearestSampler, uv + float2( texel.x,  0.0));
    float dU  = depthSampler.sample(nearestSampler, uv + float2( 0.0,      texel.y));
    float dD1 = depthSampler.sample(nearestSampler, uv + float2( texel.x,  texel.y));
    float dD2 = depthSampler.sample(nearestSampler, uv + float2(-texel.x,  texel.y));
    float depthEdge = max(max(abs(depthCenter - dR), abs(depthCenter - dU)),
                         max(abs(depthCenter - dD1), abs(depthCenter - dD2)));
    float edgeInk = smoothstep(0.001, 0.004, depthEdge);

    // ── 手工扰动：低频噪声微调线宽 ───────────────────────────────
    float jitter = craftJitter(px);
    // 扰动幅度在中间色调最大，极亮/极暗区收窄，避免两端出现断线或粘连
    float jitterAmp = safeSpacing * 0.18
                    * smoothstep(0.0, 0.12, shade)
                    * smoothstep(1.0, 0.88, shade);
    float wJitter = (jitter - 0.5) * 2.0 * jitterAmp;

    // ── 三层固定角度阴影线 ────────────────────────────────────────
    // 三层使用不同的固定角度，间距略微错开，避免节点重叠产生网格感。
    // 角度选取：45° / 135° / 22.5°，三者不形成整数倍关系，自然错位。
    //
    // 线宽控制：
    //   - Layer 1（45°）：全亮度范围存在，亮部极细（0.06sp），暗部粗（0.82sp）
    //   - Layer 2（135°）：shade < 0.58 开始出现，平滑渐入
    //   - Layer 3（22.5°）：shade < 0.26 极暗区第三层叠加

    float sp1 = safeSpacing;
    float sp2 = safeSpacing * 1.07;   // 略微错位，消除节点周期重叠
    float sp3 = safeSpacing * 0.96;

    // Layer 1：45° 主斜线，全程存在，线宽随亮度平滑变化
    float w1raw = mix(0.82, 0.06, shade) * safeSpacing;
    float w1    = clamp(w1raw + wJitter, 0.0, safeSpacing * 0.92);
    float ink1  = hatchLayer(px, M_PI_F * 0.25, sp1, w1);

    // Layer 2：135° 交叉线，shade < 0.58 渐入
    float enter2 = smoothstep(0.58, 0.38, shade);
    float w2raw  = enter2 * mix(0.0, 0.72, enter2) * safeSpacing;
    float w2     = clamp(w2raw + wJitter * 0.7, 0.0, safeSpacing * 0.88);
    float ink2   = hatchLayer(px, M_PI_F * 0.75, sp2, w2);

    // Layer 3：22.5° 第三层，shade < 0.26 渐入，极暗区加密
    float enter3 = smoothstep(0.26, 0.06, shade);
    float w3raw  = enter3 * mix(0.0, 0.65, enter3) * safeSpacing;
    float w3     = clamp(w3raw + wJitter * 0.5, 0.0, safeSpacing * 0.84);
    float ink3   = hatchLayer(px, M_PI_F * 0.125, sp3, w3);

    float inkAmount = max(max(ink1, ink2), ink3);
    inkAmount = max(inkAmount, edgeInk);

    float noise = paperNoise(uv);
    float3 tonedPaper = paperColor * (0.92 + noise * 0.10);
    float3 finalColor = mix(tonedPaper, inkColor, inkAmount);
    return float4(finalColor, 1.0);
}
