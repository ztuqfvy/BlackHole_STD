目前是测试阶段。

## 构建(mcpp,全平台)

项目已完全使用 [mcpp](https://github.com/mcpp-community/mcpp) 管理(支持 macOS / Linux / Windows 与交叉编译),
原 CMake 构建体系已移除。依赖(glfw / glad / imgui)由 mcpp 包管理器自动下载,
Eigen 使用仓库内的 `external/Eigen`,其余全部零外部依赖。

```bash
xlings install mcpp -y        # 或参考 mcpp README 的其他安装方式
mcpp build                          # 构建全部目标(默认 release)

# 渲染程序
mcpp run swz-bh-realtime-metal      # Metal 渲染路径(macOS/Apple Silicon,推荐)
mcpp run swz-bh-realtime            # OpenGL 渲染路径(全平台)
mcpp run schwarzschild              # 原离线渲染程序(CPU)

# 测试
mcpp run geodesic-test              # 施瓦西测地线 → geodesic_test.svg
mcpp run geodesic-auto-test         # 任意时空测地线 → geodesic_auto_test.svg
mcpp run volume-render-test         # 体渲染(氢原子电子轨道云)
mcpp run bloom-test                 # CPU 泛光器
mcpp run window-test                # OpenGL 窗口/着色器
mcpp run imgui-test                 # ImGui 冒烟测试
mcpp run io-test                    # 输入输出
```

### 目标说明

核心内容:
- **swz-bh-realtime-metal / swz-bh-realtime**:半实时黑洞渲染程序,调整参数(光线步进器、
  相机位置和角度)在 `src/Swz_Realtime.cpp` / `src/Swz_Realtime_Metal.mm` 中更改。
  两者的 CPU 物理代码完全共享,仅渲染栈不同(Metal / OpenGL 3.3)。
- schwarzschild:原离线渲染程序(Schwarzschild.cpp,早期版本)。

测试内容(对应原 CMake 构建的同名 *_TEST):
- geodesic-test / geodesic-auto-test:测地线测试,绘图输出为 SVG 文件(浏览器打开,等比坐标)。
  原版通过嵌入 Python 的 matplotlib 绘图,已改为内置 SVG 输出以去除 Python 依赖。
- volume-render-test:体渲染测试(氢原子电子轨道云)。GSL 特殊函数(gamma/拉盖尔/球谐勒让德)
  已内置自实现(`include/sf_hydrogen.h`),无 GSL 依赖。
- bloom-test / window-test / imgui-test / io-test:泛光器、窗口、ImGui、输入输出冒烟测试。

## 代码结构速览

- `include/` — 核心库(GR_LIB 对应物):测地线(`geodesic/ray_march/Schwarzschild_march/gauge_march`)、
  渲染器(`OpenGLRenderer` GL 版 / `MetalRenderer` Metal 版 / `OpenGLVolumeRender` GL 体渲染 /
  `MetalVolumeCompute` Metal 体渲染)、共享辅助(`shader_path.h` 运行时着色器目录、
  `window_fit.h` 窗口适配、`imgui_font.h` 中文字体、`svg_plot.h`、`sf_hydrogen.h`)
- `src/` — 各程序入口 + `shaders/`(GLSL:`volume_render.*`、bloom 三件套;`metal/`:MSL)
- `src/imgui_backends/` — vendored ImGui 后端(GLFW/OpenGL3/Metal,1.92.8,与 compat:imgui 匹配)
- `python/` — sympy 符号计算(生成联络头文件,已提交,`gauge_march` 编译期使用)

## 移植说明(相对原 Windows/CMake 构建的差异)

- **macOS OpenGL 上限 4.1 core**,不支持 GL 4.3 的 compute shader / SSBO / image load/store,
  GL 路径的体渲染已移植为 GL 3.3 片元着色器(`src/shaders/volume_render.{vert,frag}`):
  路径数据改存 TEXTURE_2D_ARRAY(单张 2D 纹理会超 macOS 16384 纹理上限),输出渲染到
  RGBA16F FBO(macOS 上 RGBA32F 不可渲染)。
- **Metal 路径**(Apple Silicon):恢复作者原始 GL 4.3 compute 设计
  (`src/shaders/metal/volume_compute.metal`:路径走 MTLBuffer/统一内存,输出直接写 RGBA32F),
  bloom/显示管线移植为 `src/shaders/metal/bloom_display.metal`(运行时编译)。
  实测 M 系列上体渲染循环 ~46 fps,快于 GL 4.1 路径的 ~31 fps。
- **HiDPI/Retina 一致性**:两版渲染器均按"帧缓冲 = 窗口点尺寸×缩放"渲染
  (GL: viewport 用 glfwGetFramebufferSize;Metal: drawable = backing 尺寸),
  ImGui 的 DisplayFramebufferScale 与实际表面比例一致,显示与鼠标坐标不错位;
  窗口按显示器工作区自适应并锁定尺寸(渲染分辨率固定为 1600×1200,由显示管线缩放)。
- **ImGui 中文化**:`imgui_font.h` 按平台加载系统中文字体(macOS Hiragino/冬黑体/Arial Unicode,
  Windows 微软雅黑/黑体,Linux Noto/文泉驿),1.92 动态字体图集按需光栅化中文;
  控制面板标签为中文且窗口自动适应内容(AlwaysAutoResize)。
- 未纳入 mcpp 目标的文件:`src/Swz_Realtime_GL.cpp`(BH_REALTIME_GL,依赖 GL 4.3 compute,
  compat:glad 仅 4.1 无法编译)与 `src/Swz_Realtime_OMP.cpp`(原构建已弃用)。

## 符号计算(python)

在 `python/symbolic2.py` 中更改 50 行左右的 g_spherical(目前给了三种:平直时空、
施瓦西时空以及 Kerr 时空)。每次更改运行完,请重新编译程序(想要保证使用的是计算结果的联络,
请保证主程序中未被注释的光线步进器是
`std::unique_ptr<RayMarch> RM0 = std::make_unique<Gauge_March>();`)。

主程序中的光线步进器:
    Gauge_March:使用符号计算后的联络进行步进,速度较慢。
    Flat_ST_RayMarch:平直时空(也即一般的射线)。
    Schwarzschild_BH_RayMarch:施瓦西时空(真空球对称黑洞)。
    double theta0 = 0.2*3.142, phi0 =  -0.305 * 1.571, r0 = 4.7;//摄像机位置的负向
    double theta1 = 0.2*3.142, phi1 = -0.305 * 1.571;//摄像机方向
