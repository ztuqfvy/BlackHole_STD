#ifndef METAL_VOLUME_COMPUTE_H
#define METAL_VOLUME_COMPUTE_H

// Metal 版体渲染 compute 管线，接口镜像 OpenGLVolumeRender.h 的
// VolumeComputeShader。
//
// Metal 没有 macOS OpenGL 的那些限制，这里恢复的是作者原始的 GL 4.3
// compute shader 设计（volume_compute.comp）：
//   - 路径数据直接放 device buffer（对应原 SSBO，Apple Silicon 统一内存
//     下 upload 就是一次 memcpy）；
//   - 输出写 RGBA32F 纹理（macOS OpenGL 上不可渲染，Metal 无此限制）。
// 积分数学未改动，见 src/shaders/metal/volume_compute.metal。
//
// dispatch() 把 compute 编码进自己的命令缓冲并提交；Metal 命令缓冲按
// 提交顺序在队列上 FIFO 执行，因此随后的渲染命令缓冲必然读到完成后的
// power 纹理，无需栅栏。

#include <vector>
#include <Eigen>

#ifdef __OBJC__
#import <Metal/Metal.h>
#else
#error "MetalVolumeCompute.h must be included from an Objective-C++ (.mm) translation unit"
#endif

class MetalVolumeCompute {
public:
    MetalVolumeCompute(id<MTLDevice> device, id<MTLCommandQueue> queue,
                       int width, int height, int maxPaths = 32);
    ~MetalVolumeCompute();

    // 编译 metal/volume_compute.metal 并创建管线
    bool init(const char* shaderDIR);

    // 上传路径数据（每像素最多maxPaths条，每条vec4(x,y,z,length)）
    void uploadPaths(const std::vector<std::vector<Eigen::Vector4f>>& allPaths);

    // 启动计算（提交到共享队列）
    void dispatch();

    id<MTLTexture> getPowerTexture() { return powerTex_; }

    float T_ = 5000, L_ = 1e6, time_ = 0;
    bool if_dopplerT_ = true, if_dopplerI_ = true;

private:
    id<MTLDevice> device_ = nil;
    id<MTLCommandQueue> queue_ = nil;
    id<MTLComputePipelineState> pipeline_ = nil;
    id<MTLBuffer> pathBuffer_ = nil;   // width*height*maxPaths 个 float4（对应原 SSBO）
    id<MTLTexture> powerTex_ = nil;       // RGBA32F 输出
    int width_, height_, maxPaths_;
};

#endif // METAL_VOLUME_COMPUTE_H
