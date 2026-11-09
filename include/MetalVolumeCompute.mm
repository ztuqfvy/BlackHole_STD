#include "MetalVolumeCompute.h"

#include <fstream>
#include <sstream>
#include <iostream>

// 与 volume_compute.metal 中 VolumeUniforms 的布局严格一致
struct VolumeUniforms {
    int32_t width;
    int32_t height;
    int32_t pathStride;
    float temperature;
    int32_t if_dopplerI;
    int32_t if_dopplerT;
    float L;
    float time;
};

MetalVolumeCompute::MetalVolumeCompute(id<MTLDevice> device, id<MTLCommandQueue> queue,
                                       int width, int height, int maxPaths)
    : device_(device), queue_(queue), width_(width), height_(height), maxPaths_(maxPaths) {}

MetalVolumeCompute::~MetalVolumeCompute() {}

bool MetalVolumeCompute::init(const char* shaderDIR) {
    std::ifstream f(std::string(shaderDIR) + "/metal/volume_compute.metal");
    if (!f) {
        std::cerr << "Failed to load metal/volume_compute.metal" << std::endl;
        return false;
    }
    std::stringstream ss;
    ss << f.rdbuf();
    NSString* src = [NSString stringWithUTF8String:ss.str().c_str()];

    NSError* err = nil;
    id<MTLLibrary> lib = [device_ newLibraryWithSource:src options:nil error:&err];
    if (!lib) {
        std::cerr << "Metal shader compile error: "
                  << [[err localizedDescription] UTF8String] << std::endl;
        return false;
    }
    id<MTLFunction> fn = [lib newFunctionWithName:@"volume_compute"];
    if (!fn) {
        std::cerr << "Failed to find compute function 'volume_compute'" << std::endl;
        return false;
    }
    NSError* perr = nil;
    pipeline_ = [device_ newComputePipelineStateWithFunction:fn error:&perr];
    if (!pipeline_) {
        std::cerr << "Metal compute pipeline error: "
                  << [[perr localizedDescription] UTF8String] << std::endl;
        return false;
    }

    // 路径缓冲（对应原 SSBO）。Apple Silicon 统一内存：Shared 存储，CPU 直接 memcpy。
    pathBuffer_ = [device_ newBufferWithLength:(NSUInteger)width_ * height_ * maxPaths_ * sizeof(float) * 4
                                       options:MTLResourceStorageModeShared];

    // 输出纹理：RGBA32F（Metal compute 可直接写入，无 macOS GL 的渲染限制）
    MTLTextureDescriptor* desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                           width:(NSUInteger)width_
                                                          height:(NSUInteger)height_
                                                       mipmapped:NO];
    desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModePrivate;
    powerTex_ = [device_ newTextureWithDescriptor:desc];

    return true;
}

void MetalVolumeCompute::uploadPaths(const std::vector<std::vector<Eigen::Vector4f>>& allPaths) {
    // 与原 SSBO 版相同的像素主序布局: flat[pixel * maxPaths + sample]
    std::vector<Eigen::Vector4f> flat((size_t)width_ * height_ * maxPaths_, Eigen::Vector4f(0, 0, 0, 0));
    for (int i = 0; i < width_ * height_; ++i) {
        for (int j = 0; j < (int)allPaths[i].size() && j < maxPaths_; ++j) {
            flat[i * maxPaths_ + j] = allPaths[i][j];
        }
    }
    memcpy(pathBuffer_.contents, flat.data(), flat.size() * sizeof(Eigen::Vector4f));
}

void MetalVolumeCompute::dispatch() {
    @autoreleasepool {
        VolumeUniforms u;
        u.width = width_;
        u.height = height_;
        u.pathStride = maxPaths_;
        u.temperature = T_;
        u.if_dopplerI = if_dopplerI_ ? 1 : 0;
        u.if_dopplerT = if_dopplerT_ ? 1 : 0;
        u.L = L_;
        u.time = time_;

        id<MTLCommandBuffer> cmd = [queue_ commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:pipeline_];
        [enc setBuffer:pathBuffer_ offset:0 atIndex:0];
        [enc setBytes:&u length:sizeof(u) atIndex:1];
        [enc setTexture:powerTex_ atIndex:0];
        // dispatchThreads 会自动裁剪边缘线程组（对应 GL 的 local_size + 越界检查）
        MTLSize grid = MTLSizeMake((NSUInteger)width_, (NSUInteger)height_, 1);
        MTLSize tg = MTLSizeMake(16, 16, 1);
        [enc dispatchThreads:grid threadsPerThreadgroup:tg];
        [enc endEncoding];
        [cmd commit];
    }
}
