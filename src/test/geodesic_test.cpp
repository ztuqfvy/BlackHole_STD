// 施瓦西黑洞测地线测试。
// 原版通过嵌入 Python 的 matplotlib 绘图;mcpp 构建改用 SVGPlot 输出
// SVG 文件(跨平台、无 Python 依赖),曲线为 r_phi = 3.3..4.1 的零测地线。
#include "svg_plot.h"
#include "geodesic.h"
#include <vector>
#include <Eigen>
#include <memory>
#include <iostream>

typedef std::shared_ptr<std::vector<double>> sv;
int main()
{
    std::cout << 1 <<std::endl;
    Geodesic BH(1);
    sv r(new std::vector<double>), phi(new std::vector<double>);
    BH.reset(r, phi);

    SVGPlot plt;
    for (int i = 0; i < 5; ++i){
        BH.compute(0, 3.3 + i * 0.2, 0, 0.01);
        plt.plot(*(BH.to_x(10)),*(BH.to_y(10)));
    }
    if (plt.save("geodesic_test.svg"))
        std::cout << "已输出 geodesic_test.svg(浏览器打开查看,等比坐标)" << std::endl;
    else
        std::cerr << "SVG 输出失败" << std::endl;
}
