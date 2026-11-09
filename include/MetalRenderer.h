#ifndef METAL_RENDERER_H
#define METAL_RENDERER_H

// Metal 版渲染器，接口镜像 OpenGLRenderer.h（见其注释）。
//
// 与 GL 版的结构对应关系：
//   GLFW 窗口 + Cocoa CAMetalLayer          <-> GLFW + NSOpenGLContext
//   loadTexture_(RGBA8, CPU 上传)            <-> GL_TEXTURE_2D texture
//   brightTexture_ / pingpongTex_(RGBA16F)   <-> 泛光 FBO 纹理
//   displayPSO_/brightPSO_/blurPSO_/combinePSO <-> 四个着色器程序
//   extTexture_(体渲染输出纹理)              <-> updatePixels(GLuint)
//
// Metal 下窗口不含 GL 上下文（GLFW_CLIENT_API = NO_API），渲染目标为
// CAMetalLayer 的 drawable。render(false) 只编码不提交，主循环随后用
// beginScreenPass() 在同一命令缓冲上编码 ImGui，再调 present() 呈现。

#include <vector>
#include <string>

struct GLFWwindow;

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#else
#error "MetalRenderer.h must be included from an Objective-C++ (.mm) translation unit"
#endif

class MetalRenderer {
public:
    MetalRenderer(int width, int height, const std::string& title);
    ~MetalRenderer();

    void updatePixels(const std::vector<unsigned char>& pixels);//用<unsigned char>更新屏幕
    void updatePixels(id<MTLTexture> textureId);//用texture更新屏幕
    void render(bool if_swap = true);//渲染
    bool shouldClose();//检测关闭

    void initShaders_Bloom(const char* shaderDIR);//输入shader的位置(加载 metal/bloom_display.metal)
    void enableBloom(bool enable){bloomEnabled = enable;};// 启用/禁用泛光
    void setBloomThreshold(float threshold){ this->bloomThreshold = threshold; }
    void setBloomStrength(float strength) { this->bloomStrength = strength;}//泛光强度

    GLFWwindow* getWindow() { return window; }
    id<MTLDevice> device() { return device_; }
    id<MTLCommandQueue> queue() { return queue_; }

    // render(false) 之后的 ImGui 编码与呈现
    id<MTLCommandBuffer> currentCommandBuffer() { return currentCmd_; }
    id<MTLRenderCommandEncoder> beginScreenPass();
    MTLRenderPassDescriptor* screenPassDescriptor();
    void present();// present + commit + poll events

    int bloom_N = 16;//ping pong 次数,2次相当于一次高斯卷积

private:
    void initWindow(const std::string& title);
    void initBuffers();
    bool ensureFrame();//获取本帧 drawable 与命令缓冲
    id<MTLRenderPipelineState> makePSO(id<MTLLibrary> lib, NSString* frag,
                                       MTLPixelFormat format);
    MTLRenderPassDescriptor* makePassDesc(id<MTLTexture> target, MTLLoadAction load);
    void extractBrightAreas(id<MTLTexture> sourceTexture);//截取高亮区
    void gaussianBlur(id<MTLTexture> sourceTexture, int iterations);//pingpong高斯卷积
    void combineFinalImage(id<MTLTexture> originalTexture, id<MTLTexture> bloomTexture);//将泛光图叠加到原图上
    void RenderQuad(id<MTLRenderCommandEncoder> enc);//绘制全屏四边形

    GLFWwindow* window = nullptr;
    int width, height;       // 渲染分辨率(纹理尺寸)
    int fbW_ = 0, fbH_ = 0;  // drawable 尺寸(Retina 下为窗口点尺寸×缩放)

    id<MTLDevice> device_ = nil;
    id<MTLCommandQueue> queue_ = nil;
    CAMetalLayer* layer_ = nil;

    id<MTLCommandBuffer> currentCmd_ = nil;
    id<CAMetalDrawable> currentDrawable_ = nil;

    id<MTLTexture> loadTexture_ = nil;  // 光线步进加载进度(RGBA8)
    id<MTLTexture> extTexture_ = nil;   // 体渲染输出(power 纹理)

    id<MTLRenderPipelineState> displayPSO_ = nil;
    id<MTLRenderPipelineState> brightPSO_ = nil;
    id<MTLRenderPipelineState> blurPSO_ = nil;
    id<MTLRenderPipelineState> combinePSO_ = nil;

    id<MTLTexture> brightTexture_ = nil;                  // 提取的亮部纹理
    id<MTLTexture> pingpongTex_[2] = {nil, nil};          // Ping-Pong Textures

    bool bloomEnabled = true;
    float bloomThreshold = 0.2f;
    float bloomStrength = 0.2f;
};

#endif // METAL_RENDERER_H
