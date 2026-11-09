// Metal 版主程序：src/Swz_Realtime.cpp 的镜像。
//
// CPU 侧（测地线光线步进）与 GL 版完全一致；渲染栈换成 Metal
// （MetalRenderer + MetalVolumeCompute + ImGui Metal 后端），见
// include/MetalRenderer.h 与 include/MetalVolumeCompute.h 的注释。

#include "MetalRenderer.h"
#include "MetalVolumeCompute.h"
#include "ray_march.h"
#include "Schwarzschild_march.h"
#include "gauge_march.h"
#include "shader_path.h"
#include "imgui_font.h"
#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"
#include <Eigen>
#include <vector>
#include <memory>
#include <assert.h>
#include <chrono>
#include <cmath>
#include <iostream>
#include <algorithm>

#define X_SIGHT 2.0*0.6
#define Y_SIGHT 1.5*0.6
#define PATH_N 32
#define N 3
#define L 2
#define M 2
#define R 0.15
typedef std::shared_ptr<std::vector<Eigen::Vector3d>> svVector;

bool stop(double x, double y, double z){
    return x*x + y*y + z*z > 8*8;
}
int main() {
    std::unique_ptr<RayMarch> RM0 = std::make_unique<Schwarzschild_BH_RayMarch>();
    //std::unique_ptr<RayMarch> RM0 = std::make_unique<Flat_ST_RayMarch>();

    //std::unique_ptr<RayMarch> RM0 = std::make_unique<Gauge_March>();
    RM0->M_ = 0.2;

    double theta0 = 0.2*3.142, phi0 =  -0.205 * 1.571, r0 = 4.7;
    double theta1 = 0.2*3.142, phi1 = -0.205 * 1.571;
    const int width = 400*4;
    const int height = 300*4;
    std::cout << "Window:  " << width << " x " << height << " (Metal)" << std::endl;
    Eigen::Vector3d x0(-r0*cos(theta0)*cos(phi0),-r0*sin(theta0)*cos(phi0),-r0*sin(phi0));
    Eigen::Vector3d v1(cos(theta1)*cos(phi1),sin(theta1)*cos(phi1),sin(phi1));
    Eigen::Vector3d vx(sin(theta1),-cos(theta1),0);
    Eigen::Vector3d vy(-cos(theta1)*sin(phi1),-sin(theta1)*sin(phi1),cos(phi1));
    Eigen::Vector3d v0 = v1;
    RM0->set_camera_pos(x0);
    RM0->set_v(v0);
    svVector light0 = RM0->compute_light(0.05,stop);
    std::vector<std::vector<Eigen::Vector4f>> lights(width * height);
    MetalRenderer renderer(width, height, "Metal Renderer");
    const std::string shader_dir = find_shader_dir();
    renderer.initShaders_Bloom(shader_dir.c_str());
    MetalVolumeCompute shader(renderer.device(), renderer.queue(), width, height, PATH_N);//32采样
    shader.init(shader_dir.c_str());

    //ImGui Init
    ImGui::CreateContext();
    load_imgui_cjk_font(20.0f);
    ImGui_ImplGlfw_InitForOther(renderer.getWindow(), true);
    ImGui_ImplMetal_Init(renderer.device());
    //*
    std::vector<unsigned char> pixels(width * height * 3, 0);
    std::vector<float> pixels_d(width * height * 3, 0);
    for (int i = 0; i < width * height * 3; i += 3) {
        pixels[i] = 235;     // R
        pixels[i + 1] = 235;   // G
        pixels[i + 2] = 235;   // B
    }

    //------------------------------------
    //Ray Marching
    int k = 0;
    std::cout << "Ray Marching Started." << std::endl;
    auto start = std::chrono::high_resolution_clock::now();
    while (!renderer.shouldClose() && k < width * height) {
        if (k % 1000 == 0)std::cout << "\r  loading... " << k<< "/" << width * height << std::flush;
        double kx,ky;
        kx = (((double)(k%width))/width - 0.5)/0.5 * X_SIGHT;
        ky = (((double)(k/width))/height - 0.5)/0.5 * Y_SIGHT;
        //Warning : the v0 is no the real v0 in the Schwarzschild Spacetime,because of the
        //          g_rr is sqrt(1-2M/r)^{-1} instead of 1 which in R^3,the method is let the r_phi *= sqrt(1-2M/r)
        v0 = v1 + kx * vx + ky * vy;
        //std::cout << (v2-v1) << std::endl;
        RM0->set_camera_pos(x0);
        RM0->set_v(v0);
        light0 = RM0->compute_light(0.015,stop);
        auto l0 = RM0->compute_l();
        for (int i = 0; i < light0->size(); ++i){
            if(pow((*light0)[i][2],2) > 0.1 * 0.1)continue;
            if(pow((*light0)[i][0],2) + pow((*light0)[i][1],2)> 4 * 4)continue;
            Eigen::Vector4f point_i;
            for (int j = 0; j < 3;j++)point_i[j] = (*light0)[i][j];
            point_i[3] = (*l0)[i];
            lights[k].push_back(point_i);
            //if (lights[k].size() == 64)break;
        }
        //int light_N = 32;
        if (lights[k].size() > PATH_N){
            int k_delete = (lights[k].size()/PATH_N) + 1;
            for (int j = lights[k].size() - 1; j >=0; j--){
                if (j % k_delete != 0){
                    lights[k].erase(lights[k].begin() + j);
                }else {
                    lights[k][j][3] *= k_delete;
                }
            }
        }
        while (lights[k].size() < PATH_N) {
            lights[k].push_back(Eigen::Vector4f(0, 0, 0, 0));
        }
        //if (lights[k].size() >64)std::cout << lights[k].size() << std::endl;
        pixels[k * 3 ] = std::min((int)(*light0).size(),255);
        pixels[k * 3 +1] = std::min((int)(*light0).size(),255);
        pixels[k * 3 +2] = std::min((int)(*light0).size(),255);
        k++;
        if (k % width == 1 ){
            renderer.updatePixels(pixels);
            renderer.render();
        }
    }//*/
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> elapsed = end - start;
    std::cout << "Ray Marching spent:" << elapsed.count() << "ms" <<std::endl;

    //----------------------------------
    //Volume Rendering
    std::cout << "Volume Rendering Started." << std::endl;
    start = std::chrono::high_resolution_clock::now();
    std::vector<float> Power(width * height);

    // 2. 上传路径数据
    shader.uploadPaths(lights);

    end = std::chrono::high_resolution_clock::now();
    elapsed = end - start;
    std::cout << "  -Upload Done " << elapsed.count() << "ms" << std::endl;
    // 3. 渲染循环

    float time = 0;
    int time_int = 0;
    //shader.dispatch();
    while (!renderer.shouldClose()) {

        shader.dispatch();

        shader.time_ = time;
        ImGui_ImplMetal_NewFrame(renderer.screenPassDescriptor());
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();
        ImGui::Begin("控制面板", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
        static float strength = 0.2f, LM = 6.f;
        if (ImGui::SliderFloat("泛光强度", &strength, 0.0f, 2.0f))
            renderer.setBloomStrength(strength);
        static float T = 5000.f;
        if (ImGui::SliderFloat("温度 (K)", &T, 500.0f, 20000.0f))
            shader.T_ = T;
        static int if_dopplerI = true, if_dopplerT = true, bloom_N = 8;
        if (ImGui::SliderInt("多普勒亮度", &if_dopplerI, 0, 1))
            shader.if_dopplerI_ = if_dopplerI;
        if (ImGui::SliderInt("多普勒温度", &if_dopplerT, 0, 1))
            shader.if_dopplerT_ = if_dopplerT;
        if (ImGui::SliderInt("泛光迭代数", &bloom_N, 1, 20))
            renderer.bloom_N = bloom_N * 2;
        if (ImGui::SliderFloat("对数亮度", &LM, 1, 20))
            shader.L_ = pow(10.f,LM);
        ImGui::End();
        ImGui::Render();
        renderer.enableBloom(true);
        renderer.updatePixels(shader.getPowerTexture());


        if (time_int % 30 == 0){
            elapsed = std::chrono::high_resolution_clock::now() - end;
            std::cout << "\r  -Compute Done " << 30 * 1000.f/elapsed.count() << "fps " << time << std::flush;
            end = std::chrono::high_resolution_clock::now();
        }
        time += elapsed.count() * 1e-6;
        time_int ++;
        //_sleep(100);
        renderer.render(false);
        id<MTLRenderCommandEncoder> enc = renderer.beginScreenPass();
        if (enc) {
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), renderer.currentCommandBuffer(), enc);
            [enc endEncoding];
        }
        renderer.present();
    }

    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    return 0;
}
