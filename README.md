# TDC_2: 高精度时间数字转换器（TDC）以太网集成系统

## 项目简介

本项目为基于FPGA的高精度TDC（Time-to-Digital Converter，时间数字转换器）系统，集成了以太网通信功能。系统可实现亚纳秒级时间测量，并通过千兆以太网实时传输测量数据，适用于激光雷达、粒子物理、精密测距等高精度时间测量场景。

---

## 主要特性

- **双通道TDC测量**：支持UP/DOWN两个信号的绝对时间测量
- **亚纳秒级分辨率**：采用260MHz主时钟+多相位+延迟链技术
- **以太网通信**：测量数据通过千兆以太网实时上传
- **模块化设计**：时钟管理、复位同步、校准控制、信号多路复用、时间戳捕获等功能独立模块化
- **可扩展性强**：便于后续功能扩展和维护

---

## 目录结构

```
TDC_2/
├── TDC_2.srcs/
│   ├── sources_1/
│   │   ├── new/                # Verilog源代码、头文件、文档
│   │   └── ip/                 # IP核配置（.xci）
│   └── constrs_1/
│       └── new/                # 约束文件（.xdc）
├── scripts/                    # Python测试脚本
├── tdc_results/                # 测试结果
├── .gitignore                  # Git忽略配置
├── README.md                   # 项目说明（本文件）
└── ...
```

---

## 主要模块说明

- `tdc_eth_integrated.v`      顶层集成模块
- `tdc_clock_manager.v`       时钟管理（260MHz主时钟+多相位）
- `tdc_reset_sync.v`          复位同步（200/260MHz域）
- `tdc_calib_ctrl.v`          校准控制（自动/手动校准、环形振荡器）
- `tdc_signal_mux.v`          信号多路复用（测量/校准/测试）
- `tdc_timestamp_capture.v`   时间戳捕获（粗计数、事件ID、边沿检测）
- `tdc_cdc_sync.v`            跨时钟域同步（200↔260MHz）
- `channel.v`                 TDC测量通道（UP/DOWN）
- `eth_comm_ctrl_tdc.v`       以太网通信控制
- `tdc_scan_ctrl.v`           扫描测试控制
- `tdc_pkg.vh`                全局参数/常量定义

---

## 约束与IP核

- `tdc_eth_constraints.xdc`   时序、管脚、时钟、False Path等约束
- `*.xci`                     IP核配置文件（可自动生成实现文件）

---

## 脚本与测试

- `scripts/tdc_scan.py`       Python自动化测试脚本
- `tdc_results/*.txt`         测试结果数据

---

## 快速上手

1. **克隆仓库**
   ```bash
   git clone https://github.com/pan224/TDC_2.git
   ```
2. **打开Vivado工程**
   - 在Vivado中新建工程，导入 `TDC_2.srcs/sources_1/new/` 下所有 `.v`/`.vh` 文件
   - 导入 `TDC_2.srcs/constrs_1/new/tdc_eth_constraints.xdc` 约束
   - 添加 `ip/` 下所有 `.xci` 文件，右键“生成输出产品”
3. **综合/实现/生成比特流**
4. **下载到FPGA，连接以太网测试**
5. **使用 `scripts/tdc_scan.py` 进行自动化测试**

---

## 贡献与维护

- 欢迎提交 issue 和 PR 进行功能完善、bug修复和文档补充
- 代码风格建议：模块化、注释清晰、接口规范

---

## 参考与致谢

- Xilinx 官方文档 UG912/UG906
- 相关TDC/以太网设计开源项目

---

## License

本项目采用 MIT License，详见 LICENSE 文件。
