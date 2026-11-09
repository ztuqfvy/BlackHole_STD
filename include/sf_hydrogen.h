#ifndef SF_HYDROGEN_H
#define SF_HYDROGEN_H

// GSL 特殊函数的最小自实现 — 仅覆盖 volume_render_test(氢原子轨道)用到的
// 三个函数,且只面向小整数参数:
//
//   sf_gamma_int(k)          = Γ(k) = (k-1)!(原 gsl_sf_gamma)
//   sf_laguerre_n(n,a,x)     = 广义拉盖尔多项式 L_n^a(x)(原 gsl_sf_laguerre_n)
//   sf_legendre_sphPlm(l,m,x)= 球谐归一化连带勒让德(原 gsl_sf_legendre_sphPlm,
//                              含 Condon-Shortley 相位,与 GSL 定义一致)
//
// 背景:compat:gsl 2.8 的源码构建在新版 clang 下失败(C89 隐式函数声明被
// 视为错误);测试只需小整数阶,标准递推公式即精确。

#include <cmath>
#include <algorithm>

inline double sf_gamma_int(int k) {
    if (k < 1) return NAN;
    double r = 1.0;
    for (int i = 2; i <= k - 1; ++i) r *= i;
    return r; // Γ(k) = (k-1)!
}

inline double sf_laguerre_n(int n, double a, double x) {
    if (n < 0) return 0.0;
    if (n == 0) return 1.0;
    double lm1 = 0.0;      // L_{-1}^a := 0
    double l0 = 1.0 + a - x; // L_1^a
    for (int i = 1; i < n; ++i) {
        // (i+1) L_{i+1}^a = (2i+1+a-x) L_i^a - (i+a) L_{i-1}^a
        double ln = ((2.0 * i + 1.0 + a - x) * l0 - (i + a) * lm1) / (i + 1.0);
        lm1 = l0;
        l0 = ln;
    }
    return l0;
}

inline double sf_legendre_sphPlm(int l, int m, double x) {
    if (m < 0 || m > l || x < -1.0 || x > 1.0) return 0.0;

    // 未归一化的 P_l^m(x),标准递推
    double pmm = 1.0; // P_m^m
    if (m > 0) {
        double somx2 = std::sqrt(std::max(0.0, (1.0 - x) * (1.0 + x)));
        double fact = 1.0;
        for (int i = 1; i <= m; ++i) {
            pmm *= -fact * somx2; // (-1)^m (2m-1)!! (1-x^2)^{m/2}
            fact += 2.0;
        }
    }
    double pll = pmm;
    if (l > m) {
        double pmmp1 = x * (2.0 * m + 1.0) * pmm; // P_{m+1}^m
        if (l > m + 1) {
            for (int k = m + 2; k <= l; ++k) {
                double pk = ((2.0 * k - 1.0) * x * pmmp1 - (k + m - 1.0) * pmm) / (k - m);
                pmm = pmmp1;
                pmmp1 = pk;
            }
            pll = pmmp1;
        } else {
            pll = pmmp1;
        }
    }

    // 球谐归一化:sqrt((2l+1)/(4π) · (l-m)!/(l+m)!)
    double fr = 1.0;
    for (int i = l - m + 1; i <= l + m; ++i) fr /= i;
    const double PI_ = 3.14159265358979323846;
    return pll * std::sqrt((2.0 * l + 1.0) / (4.0 * PI_) * fr);
}

#endif
