#ifndef SVG_PLOT_H
#define SVG_PLOT_H

// 极简 SVG 折线图 — matplotlibcpp 的跨平台替代。
//
// 原 CMake 构建里 GEODESIC_TEST / GEODESIC_AUTO_TEST 通过嵌入 Python 的
// matplotlib 绘制测地线;mcpp 构建去掉了 Python 依赖,改为把曲线写进
// SVG 文件(浏览器/Finder 预览可直接打开)。坐标范围自动确定,并保持
// 等比缩放(对应原测试里的 set_aspect('equal'))。

#include <vector>
#include <string>
#include <fstream>
#include <algorithm>
#include <cmath>
#include <cstdio>

class SVGPlot {
public:
    void plot(const std::vector<double>& xs, const std::vector<double>& ys) {
        if (xs.empty() || xs.size() != ys.size()) return;
        series_.emplace_back(xs, ys);
        for (size_t i = 0; i < xs.size(); ++i) {
            if (xs[i] < xmin_) xmin_ = xs[i];
            if (xs[i] > xmax_) xmax_ = xs[i];
            if (ys[i] < ymin_) ymin_ = ys[i];
            if (ys[i] > ymax_) ymax_ = ys[i];
        }
    }

    bool save(const std::string& path, int size = 800) const {
        if (series_.empty() || !(xmax_ > xmin_ || ymax_ > ymin_)) return false;

        // 等比:以较大跨度为准扩展另一轴
        double cx = 0.5 * (xmax_ + xmin_), cy = 0.5 * (ymax_ + ymin_);
        double span = std::max(xmax_ - xmin_, ymax_ - ymin_);
        if (!(span > 0)) span = 1.0;
        const double x0 = cx - 0.5 * span, x1 = cx + 0.5 * span;
        const double y0 = cy - 0.5 * span, y1 = cy + 0.5 * span;
        const double M = 40.0; // 边距

        auto X = [&](double x) { return M + (x - x0) / (x1 - x0) * (size - 2 * M); };
        auto Y = [&](double y) { return size - M - (y - y0) / (y1 - y0) * (size - 2 * M); };

        std::ofstream f(path);
        if (!f) return false;
        f << "<svg xmlns='http://www.w3.org/2000/svg' width='" << size << "' height='"
          << size << "' viewBox='0 0 " << size << " " << size << "'>\n";
        f << "<rect width='100%' height='100%' fill='white'/>\n";

        // 坐标轴(穿过原点,若原点在范围内)
        f << "<g stroke='#bbbbbb' stroke-width='1'>";
        if (y0 <= 0 && y1 >= 0) f << "<line x1='" << M << "' y1='" << Y(0) << "' x2='" << size - M << "' y2='" << Y(0) << "'/>";
        if (x0 <= 0 && x1 >= 0) f << "<line x1='" << X(0) << "' y1='" << M << "' x2='" << X(0) << "' y2='" << size - M << "'/>";
        f << "</g>\n";

        static const char* colors[] = {
            "#1f77b4", "#d62728", "#2ca02c", "#ff7f0e", "#9467bd", "#8c564b"
        };
        for (size_t s = 0; s < series_.size(); ++s) {
            f << "<polyline fill='none' stroke='" << colors[s % 6]
              << "' stroke-width='2' points='";
            const auto& [xs, ys] = series_[s];
            for (size_t i = 0; i < xs.size(); ++i)
                f << (i ? " " : "") << X(xs[i]) << "," << Y(ys[i]);
            f << "'/>\n";
        }
        f << "</svg>\n";
        return true;
    }

private:
    std::vector<std::pair<std::vector<double>, std::vector<double>>> series_;
    double xmin_ = 1e300, xmax_ = -1e300, ymin_ = 1e300, ymax_ = -1e300;
};

#endif
