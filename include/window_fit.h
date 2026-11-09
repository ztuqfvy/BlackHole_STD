#ifndef WINDOW_FIT_H
#define WINDOW_FIT_H

// 按主显示器工作区计算窗口尺寸。
//
// 渲染分辨率(测地线光线步进的纹理尺寸)是固定的,但窗口不能超出屏幕:
// macOS 上 1600x1200 的窗口在 ~1710x1112 逻辑像素的内置屏上会被底部
// 裁切。这里保持渲染分辨率的宽高比,把窗口收缩到工作区内,渲染纹理
// 由显示管线缩放到窗口。调用方随后应 glfwSetWindowSizeLimits 锁定。

#include <GLFW/glfw3.h>
#include <algorithm>

inline void fit_window_size(int render_w, int render_h, int& win_w, int& win_h) {
    win_w = render_w;
    win_h = render_h;
    GLFWmonitor* mon = glfwGetPrimaryMonitor();
    if (!mon) return;
    int wx, wy, ww, wh;
    glfwGetMonitorWorkarea(mon, &wx, &wy, &ww, &wh);
    if (ww <= 0 || wh <= 0) return;
    const double aspect = (double)render_w / (double)render_h;
    if ((double)win_w / ww > (double)win_h / wh) {
        win_w = std::min(win_w, ww);
        win_h = (int)(win_w / aspect);
    } else {
        win_h = std::min(win_h, wh);
        win_w = (int)(win_h * aspect);
    }
    // 取整兜底,确保不越界
    if (win_w > ww) { win_w = ww; win_h = (int)(ww / aspect); }
    if (win_h > wh) { win_h = wh; win_w = (int)(wh * aspect); }
}

#endif
