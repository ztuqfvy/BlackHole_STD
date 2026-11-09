// Display + bloom post-processing passes — Metal port of the
// vertex_shader/fragment_shader + bright/blur/combine GL 3.3 shaders.
//
// All passes draw the same fullscreen quad (triangle strip, vertex_id only),
// mirroring the GL renderer's (-1,-1)(1,-1)(1,1)(-1,1) quad and its
// (0,0)(1,0)(1,1)(0,1) texture coordinates.

#include <metal_stdlib>
using namespace metal;

struct QuadOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex QuadOut fullscreen_vertex(uint vid [[vertex_id]]) {
    const float2 pos[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 uvs[4] = {
        float2(0.0, 0.0), float2(1.0, 0.0),
        float2(0.0, 1.0), float2(1.0, 1.0)
    };
    QuadOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    o.texCoord = uvs[vid];
    return o;
}

constexpr sampler quad_sampler(mag_filter::linear, min_filter::linear,
                               address::clamp_to_edge, address::clamp_to_edge);

// ---- display (fragment_shader.glsl 的移植) ----
fragment float4 display_fragment(QuadOut in [[stage_in]],
                                 texture2d<float> texture1 [[texture(0)]])
{
    return texture1.sample(quad_sampler, in.texCoord);
}

// ---- bright pass (bright.frag 的移植) ----
struct BrightUniforms {
    float brightnessThreshold;
    int32_t _pad[3];
};

fragment float4 bright_fragment(QuadOut in [[stage_in]],
                                texture2d<float> scene [[texture(0)]],
                                constant BrightUniforms& u [[buffer(0)]])
{
    float3 color = scene.sample(quad_sampler, in.texCoord).rgb;
    float brightness = dot(color, float3(0.2126, 0.7152, 0.0722)); // 亮度加权
    if (brightness >= u.brightnessThreshold)
        return float4(color, 1.0);
    else
        return float4(color * pow(brightness / u.brightnessThreshold, 1), 1.0); // 暗部按比例压暗
}

// ---- gaussian blur (blur.frag 的移植) ----
struct BlurUniforms {
    int32_t horizontal; // 1: 水平方向, 0: 垂直方向
    int32_t _pad[3];
};

fragment float4 blur_fragment(QuadOut in [[stage_in]],
                              texture2d<float> image [[texture(0)]],
                              constant BlurUniforms& u [[buffer(0)]])
{
    const float weight[10] = {
        0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216,
        0.008, 0.004, 0.002, 0.001, 0.0005
    };
    float2 tex_offset = 1.0 / float2((float)image.get_width(), (float)image.get_height()); // 纹理像素大小
    float3 result = image.sample(quad_sampler, in.texCoord).rgb * weight[0];

    if (u.horizontal != 0) {
        for (int i = 1; i < 10; ++i) {
            result += image.sample(quad_sampler, in.texCoord + float2(tex_offset.x * i, 0.0)).rgb * weight[i];
            result += image.sample(quad_sampler, in.texCoord - float2(tex_offset.x * i, 0.0)).rgb * weight[i];
        }
    } else {
        for (int i = 1; i < 10; ++i) {
            result += image.sample(quad_sampler, in.texCoord + float2(0.0, tex_offset.y * i)).rgb * weight[i];
            result += image.sample(quad_sampler, in.texCoord - float2(0.0, tex_offset.y * i)).rgb * weight[i];
        }
    }

    return float4(result, 1.0);
}

// ---- combine (combine.frag 的移植) ----
struct CombineUniforms {
    float bloomStrength;
    int32_t bloom;
    int32_t _pad[2];
};

fragment float4 combine_fragment(QuadOut in [[stage_in]],
                                 texture2d<float> scene [[texture(0)]],
                                 texture2d<float> bloomBlur [[texture(1)]],
                                 constant CombineUniforms& u [[buffer(0)]])
{
    float3 result = scene.sample(quad_sampler, in.texCoord).rgb;
    if (u.bloom != 0)
        result += bloomBlur.sample(quad_sampler, in.texCoord).rgb * u.bloomStrength;
    return float4(result, 1.0);
}
