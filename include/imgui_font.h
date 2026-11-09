#ifndef IMGUI_FONT_H
#define IMGUI_FONT_H

// 加载一个支持中文(CJK)的系统字体作为 ImGui 默认字体。
//
// ImGui 内置字体只含 ASCII,中文会显示为 '?';这里按平台尝试常见的
// 中文字体(macOS 的 Hiragino/冬黑体/Arial Unicode,Windows 的微软雅黑/
// 黑体,Linux 的 Noto/文泉驿)。ImGui 1.92 的动态字体图集按需光栅化字形,
// 因此无需指定字形范围,任何 UTF-8 文本都能渲染。
//
// 返回是否成功;失败时补加载默认字体(UI 退化为 ASCII)。

#include "imgui.h"
#include <cstdio>

inline bool load_imgui_cjk_font(float size_pixels = 20.0f) {
    const char* candidates[] = {
        // macOS
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
        // Windows
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/simsun.ttc",
        // Linux
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    };
    ImGuiIO& io = ImGui::GetIO();
    for (const char* path : candidates) {
        FILE* f = std::fopen(path, "rb");
        if (!f) continue;
        std::fclose(f);
        ImFont* font = io.Fonts->AddFontFromFileTTF(path, size_pixels, nullptr, nullptr);
        if (font) return true;
    }
    io.Fonts->AddFontDefault();
    return false;
}

#endif
