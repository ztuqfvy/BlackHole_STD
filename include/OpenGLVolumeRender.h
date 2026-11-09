#pragma once
#include <vector>
#include <Eigen>
#include <glad/glad.h>

// Volume pass over the precomputed geodesic paths.
//
// The original implementation was a GL 4.3 compute shader (SSBO in,
// imageStore out). macOS caps OpenGL at 4.1 core, which has neither, so the
// same pass runs as a fragment shader (src/shaders/volume_render.frag):
//   - the path data lives in a GL_TEXTURE_2D_ARRAY (RGBA32F, one layer per
//     path sample) instead of an SSBO — a single width*maxPaths-wide 2D
//     texture would exceed the 16384 macOS texture size limit;
//   - the result is rendered into an RGBA16F color attachment (RGBA32F is
//     not renderable on macOS) which getPowerTexture() hands to the bloom
//     pipeline, exactly as the compute version's power image was.
// The integration math is unchanged; see volume_render.frag.
class VolumeComputeShader {
public:
    VolumeComputeShader(int width, int height, int maxPaths = 32);
    ~VolumeComputeShader();

    // 编译着色器并创建纹理/FBO(从 shaderDIR 加载 volume_render.vert/.frag)
    bool init(const char* shaderDIR);

    // 上传路径数据（每像素最多maxPaths条，每条vec4(x,y,z,length)）
    void uploadPaths(const std::vector<std::vector<Eigen::Vector4f>>& allPaths);

    // 执行一遍体渲染(渲染到 powerTex_)
    void dispatch();

    // 读取结果
    void downloadPower(std::vector<float>& powerOut);
    GLuint getPowerTexture() const { return powerTex_; }

    float T_ = 5000, L_ = 1e6, time_ = 0;
    bool if_dopplerT_ = true, if_dopplerI_ = true;


private:
    int width_, height_, maxPaths_;
    GLuint program_ = 0;
    GLuint pathsTex_ = 0;   // GL_TEXTURE_2D_ARRAY, maxPaths_ 层
    GLuint powerTex_ = 0;   // RGBA16F 渲染目标
    GLuint fbo_ = 0;
    GLuint quadVAO_ = 0, quadVBO_ = 0;
};
