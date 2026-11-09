#include "OpenGLVolumeRender.h"
#include "OpenGLShaderInit.h"
#include <fstream>
#include <sstream>
#include <iostream>

VolumeComputeShader::VolumeComputeShader(int width, int height, int maxPaths)
    : width_(width), height_(height), maxPaths_(maxPaths) {}

VolumeComputeShader::~VolumeComputeShader() {
    if (program_) glDeleteProgram(program_);
    if (pathsTex_) glDeleteTextures(1, &pathsTex_);
    if (powerTex_) glDeleteTextures(1, &powerTex_);
    if (fbo_) glDeleteFramebuffers(1, &fbo_);
    if (quadVAO_) glDeleteVertexArrays(1, &quadVAO_);
    if (quadVBO_) glDeleteBuffers(1, &quadVBO_);
}

bool VolumeComputeShader::init(const char* shaderDIR) {
    std::string base = shaderDIR;
    program_ = LoadShader(base + "/volume_render.vert", base + "/volume_render.frag");
    if (!program_) return false;

    // 路径数据纹理：每层一个采样点，层大小 = 帧大小
    glGenTextures(1, &pathsTex_);
    glBindTexture(GL_TEXTURE_2D_ARRAY, pathsTex_);
    glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA32F, width_, height_, maxPaths_,
                 0, GL_RGBA, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // 输出纹理（RGBA16F：macOS 上 RGBA32F 不可作为渲染目标）
    glGenTextures(1, &powerTex_);
    glBindTexture(GL_TEXTURE_2D, powerTex_);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width_, height_, 0, GL_RGBA, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenFramebuffers(1, &fbo_);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, powerTex_, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        std::cerr << "volume pass FBO not complete!" << std::endl;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    // 全屏四边形（TRIANGLE_STRIP，只需位置属性）
    float quad[] = {
        -1.0f, -1.0f,
         1.0f, -1.0f,
        -1.0f,  1.0f,
         1.0f,  1.0f
    };
    glGenVertexArrays(1, &quadVAO_);
    glGenBuffers(1, &quadVBO_);
    glBindVertexArray(quadVAO_);
    glBindBuffer(GL_ARRAY_BUFFER, quadVBO_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0);

    return true;
}

void VolumeComputeShader::uploadPaths(const std::vector<std::vector<Eigen::Vector4f>>& allPaths) {
    // 输入按像素主序存放(allPaths[pixel][sample])，纹理按层存放(层 = 采样点)，
    // 逐层转置上传。
    glBindTexture(GL_TEXTURE_2D_ARRAY, pathsTex_);
    std::vector<Eigen::Vector4f> layer(width_ * height_, Eigen::Vector4f(0, 0, 0, 0));
    for (int j = 0; j < maxPaths_; ++j) {
        for (int i = 0; i < width_ * height_; ++i) {
            layer[i] = (i < (int)allPaths.size() && j < (int)allPaths[i].size())
                           ? allPaths[i][j] : Eigen::Vector4f(0, 0, 0, 0);
        }
        glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, j, width_, height_, 1,
                        GL_RGBA, GL_FLOAT, layer.data());
    }
}

void VolumeComputeShader::dispatch() {
    glUseProgram(program_);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
    glViewport(0, 0, width_, height_);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D_ARRAY, pathsTex_);
    glUniform1i(glGetUniformLocation(program_, "paths"), 0);
    glUniform1i(glGetUniformLocation(program_, "pathStride"), maxPaths_);
    glUniform1f(glGetUniformLocation(program_, "temperature"), T_);
    glUniform1i(glGetUniformLocation(program_, "if_dopplerI"), if_dopplerI_);
    glUniform1i(glGetUniformLocation(program_, "if_dopplerT"), if_dopplerT_);
    glUniform1f(glGetUniformLocation(program_, "time"), time_);
    glUniform1f(glGetUniformLocation(program_, "L"), L_);

    glBindVertexArray(quadVAO_);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindVertexArray(0);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void VolumeComputeShader::downloadPower(std::vector<float>& powerOut) {
    powerOut.resize(width_ * height_);
    std::vector<float> tmp(width_ * height_ * 4);
    glBindTexture(GL_TEXTURE_2D, powerTex_);
    glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, tmp.data());
    for (int i = 0; i < width_ * height_; ++i){
        for (int j = 0; j < 3; ++j)powerOut[3 * i + j] = tmp[i*4 + j];
    }
}
