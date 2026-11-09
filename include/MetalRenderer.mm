#include "MetalRenderer.h"
#include "window_fit.h"

#include <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3native.h>
#import <AppKit/AppKit.h>

#include <fstream>
#include <sstream>
#include <iostream>
#include <stdexcept>

static NSString* read_shader_source(const std::string& path) {
    std::ifstream f(path);
    if (!f) return nil;
    std::stringstream ss;
    ss << f.rdbuf();
    return [NSString stringWithUTF8String:ss.str().c_str()];
}

MetalRenderer::MetalRenderer(int width, int height, const std::string& title)
    : width(width), height(height) {
    initWindow(title);
    initBuffers();
}

MetalRenderer::~MetalRenderer() {
    glfwDestroyWindow(window);
    glfwTerminate();
}

void MetalRenderer::initWindow(const std::string& title) {
    if (!glfwInit()) {
        throw std::runtime_error("Failed to initialize GLFW");
    }

    // Metal 渲染：窗口不需要 OpenGL 上下文
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

    // 渲染纹理固定为 (width, height);窗口按屏幕工作区收缩并锁定尺寸
    int win_w, win_h;
    fit_window_size(width, height, win_w, win_h);
    window = glfwCreateWindow(win_w, win_h, title.c_str(), nullptr, nullptr);
    if (!window) {
        glfwTerminate();
        throw std::runtime_error("Failed to create GLFW window");
    }
    glfwSetWindowSizeLimits(window, win_w, win_h, win_w, win_h);

    device_ = MTLCreateSystemDefaultDevice();
    if (!device_) {
        throw std::runtime_error("Failed to create Metal device");
    }
    queue_ = [device_ newCommandQueue];

    // 把 CAMetalLayer 挂到 GLFW 的 Cocoa contentView 上。
    // drawable 取视图 backing 尺寸(Retina 下为窗口点尺寸×2):ImGui 经
    // DisplayFramebufferScale 以同一比例光栅化,鼠标坐标天然一致,文字
    // 也是原生分辨率;渲染分辨率纹理由屏幕 pass 放大铺满 drawable。
    NSWindow* nswin = (NSWindow*)glfwGetCocoaWindow(window);
    glfwGetFramebufferSize(window, &fbW_, &fbH_);
    double scale = (double)nswin.backingScaleFactor;
    CAMetalLayer* layer = [CAMetalLayer layer];
    layer.device = device_;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.drawableSize = CGSizeMake(fbW_, fbH_);
    layer.contentsScale = scale;
    nswin.contentView.wantsLayer = YES;
    nswin.contentView.layer = layer;
    layer_ = layer;

    std::cout << "Metal window " << win_w << "x" << win_h << " drawable " << fbW_
              << "x" << fbH_ << " (render " << width << "x" << height << ")"
              << std::endl;
}

void MetalRenderer::initBuffers() {
    // 加载进度纹理（CPU 每行更新，与 GL 版 glTexSubImage2D 对应）
    MTLTextureDescriptor* loadDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                        width:(NSUInteger)width
                                                                                       height:(NSUInteger)height
                                                                                    mipmapped:NO];
    loadDesc.usage = MTLTextureUsageShaderRead;
    loadDesc.storageMode = MTLStorageModeManaged;
    loadTexture_ = [device_ newTextureWithDescriptor:loadDesc];

    // 泛光纹理（亮部 + ping-pong，均为 RGBA16F，与 GL 版一致）
    MTLTextureDescriptor* bloomDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                          width:(NSUInteger)width
                                                                                         height:(NSUInteger)height
                                                                                      mipmapped:NO];
    bloomDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    bloomDesc.storageMode = MTLStorageModePrivate;
    brightTexture_ = [device_ newTextureWithDescriptor:bloomDesc];
    for (int i = 0; i < 2; ++i) {
        pingpongTex_[i] = [device_ newTextureWithDescriptor:bloomDesc];
    }
}

id<MTLRenderPipelineState> MetalRenderer::makePSO(id<MTLLibrary> lib, NSString* frag,
                                                  MTLPixelFormat format) {
    id<MTLFunction> vs = [lib newFunctionWithName:@"fullscreen_vertex"];
    id<MTLFunction> fs = [lib newFunctionWithName:frag];
    MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = vs;
    desc.fragmentFunction = fs;
    desc.colorAttachments[0].pixelFormat = format;
    NSError* err = nil;
    id<MTLRenderPipelineState> pso = [device_ newRenderPipelineStateWithDescriptor:desc error:&err];
    if (!pso) {
        std::cerr << "Metal pipeline error (" << [frag UTF8String] << "): "
                  << [[err localizedDescription] UTF8String] << std::endl;
    }
    return pso;
}

void MetalRenderer::initShaders_Bloom(const char* shaderDIR) {
    NSString* src = read_shader_source(std::string(shaderDIR) + "/metal/bloom_display.metal");
    if (!src) {
        throw std::runtime_error("Failed to load metal/bloom_display.metal");
    }
    NSError* err = nil;
    id<MTLLibrary> lib = [device_ newLibraryWithSource:src options:nil error:&err];
    if (!lib) {
        std::cerr << "Metal shader compile error: "
                  << [[err localizedDescription] UTF8String] << std::endl;
        throw std::runtime_error("Failed to compile bloom_display.metal");
    }

    // 显示/合成渲染到 drawable(BGRA8)，亮部/模糊渲染到 RGBA16F
    displayPSO_  = makePSO(lib, @"display_fragment",  MTLPixelFormatBGRA8Unorm);
    brightPSO_   = makePSO(lib, @"bright_fragment",   MTLPixelFormatRGBA16Float);
    blurPSO_     = makePSO(lib, @"blur_fragment",     MTLPixelFormatRGBA16Float);
    combinePSO_  = makePSO(lib, @"combine_fragment",  MTLPixelFormatBGRA8Unorm);

    if (!displayPSO_ || !brightPSO_ || !blurPSO_ || !combinePSO_) {
        throw std::runtime_error("Failed to create Metal bloom pipelines.");
    }
}

void MetalRenderer::updatePixels(const std::vector<unsigned char>& pixels) {
    // GL 版上传 RGB 数据；Metal replaceRegion 不做格式转换，先展开成 RGBA8
    static std::vector<unsigned char> rgba;
    rgba.resize((size_t)width * height * 4);
    for (size_t i = 0; i < (size_t)width * height; ++i) {
        rgba[4 * i + 0] = pixels[3 * i + 0];
        rgba[4 * i + 1] = pixels[3 * i + 1];
        rgba[4 * i + 2] = pixels[3 * i + 2];
        rgba[4 * i + 3] = 255;
    }
    MTLRegion region = MTLRegionMake2D(0, 0, (NSUInteger)width, (NSUInteger)height);
    [loadTexture_ replaceRegion:region mipmapLevel:0 withBytes:rgba.data() bytesPerRow:(NSUInteger)width * 4];
}

void MetalRenderer::updatePixels(id<MTLTexture> textureId) {
    extTexture_ = textureId;
}

bool MetalRenderer::shouldClose() {
    return glfwWindowShouldClose(window);
}

bool MetalRenderer::ensureFrame() {
    // drawable 尺寸跟随视图 backing(窗口移到不同缩放的屏幕时同步)
    int fbw, fbh;
    glfwGetFramebufferSize(window, &fbw, &fbh);
    if (fbw > 0 && fbh > 0 && (fbw != fbW_ || fbh != fbH_)) {
        fbW_ = fbw;
        fbH_ = fbh;
        layer_.drawableSize = CGSizeMake(fbw, fbh);
    }
    if (!currentDrawable_) {
        currentDrawable_ = [layer_ nextDrawable];
        currentCmd_ = [queue_ commandBuffer];
    }
    return currentDrawable_ != nil;
}

MTLRenderPassDescriptor* MetalRenderer::makePassDesc(id<MTLTexture> target, MTLLoadAction load) {
    MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor renderPassDescriptor];
    desc.colorAttachments[0].texture = target;
    desc.colorAttachments[0].loadAction = load;
    desc.colorAttachments[0].storeAction = MTLStoreActionStore;
    return desc;
}

MTLRenderPassDescriptor* MetalRenderer::screenPassDescriptor() {
    if (!ensureFrame()) return nil;
    // Load 语义：本帧已渲染的图像保留，供 ImGui 叠加
    return makePassDesc(currentDrawable_.texture, MTLLoadActionLoad);
}

id<MTLRenderCommandEncoder> MetalRenderer::beginScreenPass() {
    if (!ensureFrame()) return nil;
    MTLRenderPassDescriptor* desc = makePassDesc(currentDrawable_.texture, MTLLoadActionLoad);
    id<MTLRenderCommandEncoder> enc = [currentCmd_ renderCommandEncoderWithDescriptor:desc];
    [enc setViewport:{0, 0, (double)fbW_, (double)fbH_, 0.0, 1.0}];
    return enc;
}

void MetalRenderer::RenderQuad(id<MTLRenderCommandEncoder> enc) {
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

void MetalRenderer::extractBrightAreas(id<MTLTexture> sourceTexture) {
    id<MTLRenderCommandEncoder> enc =
        [currentCmd_ renderCommandEncoderWithDescriptor:makePassDesc(brightTexture_, MTLLoadActionDontCare)];
    [enc setViewport:{0, 0, (double)width, (double)height, 0.0, 1.0}];
    [enc setRenderPipelineState:brightPSO_];
    [enc setFragmentTexture:sourceTexture atIndex:0];
    struct { float brightnessThreshold; int32_t pad[3]; } u = {bloomThreshold, {0, 0, 0}};
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    RenderQuad(enc);
    [enc endEncoding];
}

void MetalRenderer::gaussianBlur(id<MTLTexture> sourceTexture, int iterations) {
    bool horizontal = true, first_iteration = true;
    for (int i = 0; i < iterations; ++i) {
        int index = horizontal ? 0 : 1;
        id<MTLRenderCommandEncoder> enc =
            [currentCmd_ renderCommandEncoderWithDescriptor:makePassDesc(pingpongTex_[index], MTLLoadActionDontCare)];
        [enc setViewport:{0, 0, (double)width, (double)height, 0.0, 1.0}];
        [enc setRenderPipelineState:blurPSO_];
        [enc setFragmentTexture:first_iteration ? sourceTexture : pingpongTex_[1 - index] atIndex:0];
        struct { int32_t horizontal; int32_t pad[3]; } u = {horizontal ? 1 : 0, {0, 0, 0}};
        [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
        RenderQuad(enc);
        [enc endEncoding];
        horizontal = !horizontal;
        if (first_iteration) first_iteration = false;
    }
}

void MetalRenderer::combineFinalImage(id<MTLTexture> originalTexture, id<MTLTexture> bloomTexture) {
    // 渲染到屏幕（drawable，viewport 为 drawable 尺寸，渲染分辨率纹理放大铺满）
    id<MTLRenderCommandEncoder> enc =
        [currentCmd_ renderCommandEncoderWithDescriptor:makePassDesc(currentDrawable_.texture, MTLLoadActionClear)];
    [enc setViewport:{0, 0, (double)fbW_, (double)fbH_, 0.0, 1.0}];
    [enc setRenderPipelineState:combinePSO_];
    struct { float bloomStrength; int32_t bloom; int32_t pad[2]; } u = {bloomStrength, 1, {0, 0}};
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    [enc setFragmentTexture:originalTexture atIndex:0];
    [enc setFragmentTexture:bloomTexture atIndex:1];
    RenderQuad(enc);
    [enc endEncoding];
}

void MetalRenderer::render(bool if_swap) {
    @autoreleasepool {
        if (!ensureFrame()) return;

        id<MTLTexture> texToUse = extTexture_ ? extTexture_ : loadTexture_;

        if (bloomEnabled) {
            extractBrightAreas(texToUse);
            gaussianBlur(brightTexture_, bloom_N);
            combineFinalImage(texToUse, pingpongTex_[1]);
        } else {
            id<MTLRenderCommandEncoder> enc =
                [currentCmd_ renderCommandEncoderWithDescriptor:makePassDesc(currentDrawable_.texture, MTLLoadActionClear)];
            [enc setViewport:{0, 0, (double)fbW_, (double)fbH_, 0.0, 1.0}];
            [enc setRenderPipelineState:displayPSO_];
            [enc setFragmentTexture:texToUse atIndex:0];
            RenderQuad(enc);
            [enc endEncoding];
        }

        if (if_swap) {
            present();
        }
    }
}

void MetalRenderer::present() {
    @autoreleasepool {
        if (currentCmd_ && currentDrawable_) {
            [currentCmd_ presentDrawable:currentDrawable_];
            [currentCmd_ commit];
        }
        currentCmd_ = nil;
        currentDrawable_ = nil;
        glfwPollEvents();
    }
}
