// Volume rendering compute kernel — Metal port of volume_compute.comp (GL 4.3).
//
// Metal needs none of the compromises the GL 3.3 fallback made: paths arrive
// as a plain device buffer (the original SSBO design) and the result is
// written to an RGBA32F texture, which Apple GPUs allow as a compute write.
// The integration math is unchanged from the GL 4.3 original.

#include <metal_stdlib>
using namespace metal;

struct VolumeUniforms {
    int32_t width;
    int32_t height;
    int32_t pathStride;  // 每像素路径数（如32）
    float temperature;
    int32_t if_dopplerI;
    int32_t if_dopplerT;
    float L;
    float time;
};

float3 fade(float3 t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float lerp_(float a, float b, float t) {
    return a + t * (b - a);
}

// GLSL 的 mod(x, y) 结果落在 [0, y)，对负数也回绕；MSL 的 fmod 保留
// 被除数符号，Perlin 的整数格点会取到负值，必须用 GLSL 语义。
float3 mod_glsl(float3 x, float y) {
    return x - y * floor(x / y);
}

float grad(int hash, float3 p) {
    int h = hash & 15;
    float u = h < 8 ? p.x : p.y;
    float v = h < 4 ? p.y : (h == 12 || h == 14 ? p.x : p.z);
    return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
}

// 伪随机排列
int permute(int x) {
    return (int)(fract(sin((float)x) * 43758.5453) * 256.0);
}

float perlin(float3 p) {

    float3 Pi = floor(p);
    float3 Pf = p - Pi;
    Pi = mod_glsl(Pi, 256.0);

    int xi = (int)Pi.x;
    int yi = (int)Pi.y;
    int zi = (int)Pi.z;

    float xf = Pf.x;
    float yf = Pf.y;
    float zf = Pf.z;

    float3 f = fade(Pf);

    // 8 corners of cube
    int aaa = permute(permute(permute(xi) + yi) + zi);
    int aba = permute(permute(permute(xi) + yi + 1) + zi);
    int aab = permute(permute(permute(xi) + yi) + zi + 1);
    int abb = permute(permute(permute(xi) + yi + 1) + zi + 1);
    int baa = permute(permute(permute(xi + 1) + yi) + zi);
    int bba = permute(permute(permute(xi + 1) + yi + 1) + zi);
    int bab = permute(permute(permute(xi + 1) + yi) + zi + 1);
    int bbb = permute(permute(permute(xi + 1) + yi + 1) + zi + 1);

    float x1, x2, y1, y2;
    x1 = lerp_(grad(aaa, Pf), grad(baa, Pf - float3(1,0,0)), f.x);
    x2 = lerp_(grad(aba, Pf - float3(0,1,0)), grad(bba, Pf - float3(1,1,0)), f.x);
    y1 = lerp_(x1, x2, f.y);

    x1 = lerp_(grad(aab, Pf - float3(0,0,1)), grad(bab, Pf - float3(1,0,1)), f.x);
    x2 = lerp_(grad(abb, Pf - float3(0,1,1)), grad(bbb, Pf - float3(1,1,1)), f.x);
    y2 = lerp_(x1, x2, f.y);

    return 0.5 + 0.5 * lerp_(y1, y2, f.z); // 归一化到0~1
}

float fog_density(float3 pos, float time) {
    float T = 0.7;
    float density = 0;
    float r = length(pos);
    float omega = 4/r/sqrt(r-2*0.2);
    float r0 = 0.62;
    if (r < r0) return 0;
    int N = 3;
    for (int i = 0; i < N; ++i){
        float time_eff = time + i * T / N - (float)((int)((time + i * T / N)/T) * T) ;
        float phi_0 = 0.0;
        time_eff +=phi_0;
        float c = cos(time_eff * omega );
        float s = sin(time_eff * omega );
        float3 pos1 =
        float3x3(
            float3(c, -s, 0.0),
            float3(s,  c, 0.0),
            float3(0.0, 0.0, 1.0)
        ) * pos;
        float n1 = perlin(pos1 * 18.5); // 0.05控制雾的块感
        float n2 = perlin(pos1*pow(r,0.5) * 2.5);
        time_eff -= phi_0;
        density += (0.2 * n2 + 0.65 * n1*n2 ) * pow(sin(time_eff/T * 3.1415),2);
    }
    float base = exp(-r*r*0.6 - pos.z * pos.z * 655) * pow(r-r0,1.6);
    density = density * base;
    return density;
}

float dopplerI(float3 pos, float3 vc){
    float r = length(pos);
    float M = 0.2;
    if (r < 3 * M)return 0;
    vc += (1/sqrt(1-2 * M / r) - 1) * dot(pos, vc)/max(dot(pos,pos),1e-6) * pos;
    float3 vp = cross(float3(0,0,1),pos);
    float cos_theta = dot(vc,vp)/length(vc)/length(vp);
    float gammap2 =  (r - 3 * M)/(r - 2 * M);
    float beta = sqrt(M / (r - 2*M));
    return gammap2*gammap2 / pow(1 + beta * cos_theta,4);
}

// 将黑体温度 (K) 转换为 RGB 颜色 (float3, 范围 [0,1])
float3 radiation_color(float T){
    // 约束温度范围 (避免极端值导致计算错误)
    T = clamp(T, 1000.0, 40000.0);

    // 归一化温度
    float temp = T / 100.0;

    // 计算红色通道
    float r;
    if (temp <= 66.0) {
        r = 1.0;
    } else {
        r = temp - 60.0;
        r = 329.698727446 * pow(r, -0.1332047592);
        r = clamp(r / 255.0, 0.0, 1.0);
    }

    // 计算绿色通道
    float g;
    if (temp <= 66.0) {
        g = temp;
        g = 99.4708025861 * log(g) - 161.1195681661;
    } else {
        g = temp - 60.0;
        g = 288.1221695283 * pow(g, -0.0755148492);
    }
    g = clamp(g / 255.0, 0.0, 1.0);

    // 计算蓝色通道
    float b;
    if (temp >= 66.0) {
        b = 1.0;
    } else {
        if (temp <= 19.0) {
            b = 0.0;
        } else {
            b = temp - 10.0;
            b = 138.5177312231 * log(b) - 305.0447927307;
            b = clamp(b / 255.0, 0.0, 1.0);
        }
    }
    return float3(r, g, b);
}

float dopplerT(float3 pos, float3 vc){
    float r = length(pos);
    float M = 0.2;
    if (r < 3*M)return 0;
    vc += (1/sqrt(1-2 * M / r) - 1) * dot(pos, vc)/dot(pos,pos) * pos;
    float3 vp = cross(float3(0,0,1),pos);
    float cos_theta = dot(vc,vp)/length(vc)/length(vp);
    float gammap =  sqrt((r - 3 * M)/(r - 2 * M));
    float beta = sqrt(M / (r - 2*M));
    return  gammap/ (1 + beta * cos_theta);
}

kernel void volume_compute(
    device const float4* paths                    [[buffer(0)]],   // 每像素pathStride条路径，按像素块排列
    constant VolumeUniforms& u                    [[buffer(1)]],
    texture2d<float, access::write> powerImage    [[texture(0)]],  // 输出Power
    uint2 gid                                     [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) return;
    uint idx = gid.y * (uint)u.width + gid.x;

    float3 power = float3(0,0,0);
    float S = 1.0;
    for (uint i = 0; i < (uint)u.pathStride - 1; ++i) {
        float4 p = paths[idx * (uint)u.pathStride + i];
        float3 vc = paths[idx * (uint)u.pathStride + i + 1].xyz - p.xyz;
        if (p.w <= 0.0) break; // w为路径长度，<=0表示无效
        // 沿路径采样
        float3 r_color;
        float tem_eff ;
        if (u.if_dopplerT == 1){
            tem_eff = u.temperature/pow(length(p.xyz),1.2)* dopplerT(p.xyz, vc) ;
        }else{
            tem_eff = u.temperature/pow(length(p.xyz),1.2) ;
        }
        float density = fog_density(p.xyz, u.time);
        r_color = radiation_color(tem_eff*(1.0 + density * 1e1) )/255.0 ;
        r_color.x = pow(r_color.x,2.2);
        r_color.y = pow(r_color.y,2.2);
        r_color.z = pow(r_color.z,2.2);

        if (u.if_dopplerI == 1){
            power += density * p.w * S * dopplerI(p.xyz, vc) * r_color;
        }else{
            power += density * p.w * S * r_color;
        }
        S *= 1+(- 5.2 * density * p.w * length(p.xyz));
        if (S < 0.01){
            break;
        }
    }
    for (int c = 0; c < 3; ++c) {
        if (isnan(power[c]) || isinf(power[c])) {
            power[c] = 0.0;
        }
    }
    power *= u.L;
    for (int i = 0; i < 3; ++i){
        if (power[i] > 1)power[i] = 1;
        if (power[i] < 0)power[i] = 0;
        power[i] = pow(power[i],1/2.2);
    }
    powerImage.write(float4(power, 1), gid);
}
