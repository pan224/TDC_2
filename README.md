# TDC (Time-to-Digital Converter) 以太网集成系统

## 项目概述

本项目是一个基于 FPGA 的高精度时间数字转换器（TDC），采用 Xilinx Kintex-7 (xc7k325t-ffg900-2) 实现。系统集成了双通道 TDC 测量核心与千兆以太网通信功能，可实现亚纳秒级别的时间测量精度。

### 主要特性

- **测量精度**: 约 17.5ps 分辨率（基于 96-tap 延迟线 + 4 相位插值）
- **时钟频率**: 260MHz TDC 时钟，200MHz 系统时钟
- **双通道**: 同时测量 UP 和 DOWN 两路信号
- **自校准**: 基于环形振荡器的直方图自动校准
- **以太网接口**: 千兆以太网数据传输，支持上位机控制
- **扫描测试**: 支持相位扫描测试模式，用于系统验证和DNL/INL分析

---

## 系统架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         test_tdc_eth (顶层模块)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐     ┌─────────────────────────────────────────────┐    │
│  │ global_clock_   │     │           tdc_eth_integrated                 │    │
│  │ reset           │     │  ┌─────────────┐  ┌─────────────────────┐   │    │
│  │ ├─ IBUFDS       │     │  │ tdc_clock_  │  │     channel_up      │   │    │
│  │ ├─ clk_wiz_200M │────▶│  │ manager     │  │  ├─ dl_sync          │   │    │
│  │ └─ globalresetter     │  │ (260MHz+    │  │  │  ├─ delay_line×4  │   │    │
│  └─────────────────┘     │  │  4相位)     │  │  │  └─ priority_enc  │   │    │
│                          │  └─────────────┘  │  └─ lut (校准LUT)    │   │    │
│  ┌─────────────────┐     │                   ├─────────────────────┤   │    │
│  │   gig_eth       │     │  ┌─────────────┐  │     channel_down    │   │    │
│  │ (千兆以太网MAC) │◀───▶│  │ eth_comm_   │  │  (同上结构)         │   │    │
│  │ ├─ RGMII接口    │     │  │ ctrl_tdc    │  └─────────────────────┘   │    │
│  │ └─ FIFO桥接     │     │  │ (异步FIFO)  │  ┌─────────────────────┐   │    │
│  └─────────────────┘     │  └─────────────┘  │   tdc_scan_ctrl     │   │    │
│                          │                   │  (扫描测试控制)      │   │    │
│                          └───────────────────┴─────────────────────┘    │    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 模块详细说明

### 1. 顶层模块 (test_tdc_eth.v)

顶层集成模块，连接所有子系统。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| SYS_CLK_P/N | Input | 1 | 200MHz 差分系统时钟 |
| CPU_RESET | Input | 1 | 系统复位（高有效） |
| SGMIICLK_Q0_P/N | Input | 1 | 125MHz SGMII 参考时钟 |
| PHY_RESET_N | Output | 1 | PHY 复位（低有效） |
| MDIO | Inout | 1 | PHY 管理数据接口 |
| MDC | Output | 1 | PHY 管理时钟 |
| RGMII_TXD[3:0] | Output | 4 | RGMII 发送数据 |
| RGMII_TX_CTL | Output | 1 | RGMII 发送控制 |
| RGMII_TXC | Output | 1 | RGMII 发送时钟 |
| RGMII_RXD[3:0] | Input | 4 | RGMII 接收数据 |
| RGMII_RX_CTL | Input | 1 | RGMII 接收控制 |
| RGMII_RXC | Input | 1 | RGMII 接收时钟 |

---

### 2. TDC 集成模块 (tdc_eth_integrated.v)

TDC 核心与以太网接口的集成模块。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| sys_clk_200MHz | Input | 1 | 200MHz 系统时钟 |
| sys_reset | Input | 1 | 系统复位 |
| signal_up | Input | 1 | UP 通道输入信号 |
| signal_down | Input | 1 | DOWN 通道输入信号 |
| tdc_reset_trigger | Input | 1 | TDC 复位触发（时间基准） |
| scan_test_en | Input | 1 | 扫描测试使能 |
| gig_eth_tx_fifo_* | - | - | 以太网发送 FIFO 接口 |
| gig_eth_rx_fifo_* | - | - | 以太网接收 FIFO 接口 |
| tdc_ready_out | Output | 1 | TDC 就绪状态 |

#### 内部结构

```
tdc_eth_integrated
├── tdc_clock_manager     # 时钟生成（260MHz + 4相位）
├── tdc_reset_sync        # 复位同步
├── channel_up            # UP 通道测量
├── channel_down          # DOWN 通道测量
├── tdc_calib_ctrl        # 校准控制
├── tdc_signal_mux        # 信号多路复用
├── tdc_timestamp_capture # 时间戳捕获
├── tdc_cdc_sync          # 跨时钟域同步
├── tdc_scan_ctrl         # 扫描测试控制
└── eth_comm_ctrl_tdc     # 以太网通信控制
```

---

### 3. 时钟管理模块 (tdc_clock_manager.v)

生成 TDC 所需的高频时钟和 4 相位采样时钟。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| sys_clk_200MHz | Input | 1 | 200MHz 输入时钟 |
| clk_260MHz | Output | 1 | 260MHz 主时钟 |
| clk_260MHz_p0 | Output | 1 | 260MHz 0° 相位 |
| clk_260MHz_p90 | Output | 1 | 260MHz 90° 相位 |
| clk_260MHz_p180 | Output | 1 | 260MHz 180° 相位 |
| clk_260MHz_p270 | Output | 1 | 260MHz 270° 相位 |

#### 时钟关系
- 260MHz 时钟周期: 3.846ns
- 4 相位时钟相差 90°（~962ps）
- 用于 4x 插值提高时间分辨率

---

### 4. 测量通道模块 (channel.v)

单通道完整数据处理流程，包含延迟线采样和校准查找。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| CLK_P0/P90/P180/P270 | Input | 1 | 4 相位采样时钟 |
| RST | Input | 1 | 复位 |
| clk_period | Input | 13 | 时钟周期（皮秒） |
| sensor | Input | 1 | 输入信号 |
| calib_en | Input | 1 | 校准使能 |
| ready | Output | 1 | 通道就绪 |
| valid | Output | 1 | 输出有效 |
| time_out | Output | 13 | 时间输出（皮秒） |

#### 数据流

```
sensor ──▶ dl_sync ──▶ priority_encoder ──▶ lut ──▶ time_out
              │              │                │
              ▼              ▼                ▼
          4相位采样      96-tap编码      校准查表
```

---

### 5. 延迟线同步模块 (dl_sync.v)

管理 4 相位延迟线采样并选择最优结果。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| CLK_P0/P90/P180/P270 | Input | 1 | 4 相位时钟 |
| RST | Input | 1 | 复位 |
| sensor | Input | 1 | 传感器信号 |
| calib_en | Input | 1 | 校准使能 |
| bin | Output | 9 | 编码输出 |
| valid | Output | 1 | 有效标志 |
| calib_flag | Output | 1 | 校准标志 |

#### 工作原理

- 使用 4 个相位偏移 90° 的时钟采样延迟线
- 选择变化边沿处于安全采样窗口的相位
- 输出 9 位编码值（0-511），对应时间 0-3846ps

---

### 6. 延迟线模块 (delay_line.v)

基于 CARRY4 原语的抽头延迟线实现。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| CLK_P0/P90/P180/P270 | Input | 1 | 相位时钟 |
| sensor | Input | 1 | 输入信号 |
| bins | Output | 96 | 延迟线抽头输出 |

#### 实现细节

- 使用 24 个 CARRY4 原语级联
- 每个 CARRY4 提供 4 个抽头，共 96 个抽头
- 典型抽头延迟约 17.5ps
- 使用 FDCE 触发器进行采样

```
sensor ──▶ FDCE ──▶ CARRY4[0] ──▶ CARRY4[1] ──▶ ... ──▶ CARRY4[23]
             │         │            │                      │
             ▼         ▼            ▼                      ▼
           tap[0]   tap[1-4]    tap[5-8]    ...        tap[93-96]
```

---

### 7. 优先编码器模块 (priority_encoder.v)

将 96 位温度计码转换为二进制编码。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| CLK | Input | 1 | 采样时钟 |
| RST | Input | 1 | 复位 |
| bins | Input | 96 | 温度计码输入 |
| bin | Output | 9 | 二进制编码输出 |
| valid | Output | 1 | 有效标志 |

#### 编码算法

1. 检测温度计码的 1→0 跳变位置
2. 使用流水线结构优化时序
3. 输出 9 位编码（log2(512) = 9）

---

### 8. 查找表校准模块 (lut.v)

通过直方图统计实现延迟线非线性校准。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| CLK | Input | 1 | 时钟 |
| RST | Input | 1 | 复位 |
| valid_in | Input | 1 | 输入有效 |
| calib_flag | Input | 1 | 校准标志 |
| bin_in | Input | 9 | 编码输入 |
| data_out | Output | 18 | 校准后数据 |
| init | Output | 1 | 初始化完成 |

#### 校准原理

```
状态机流程:
CLEAR ──▶ RUN ──▶ CONFIG ──▶ RUN
  │         │        │
  ▼         ▼        ▼
清零BRAM  统计直方图  计算累积分布
```

1. **直方图统计**: 使用环形振荡器产生随机信号，统计各 bin 的命中次数
2. **累积分布计算**: 将直方图转换为累积分布函数
3. **查表输出**: 测量时查表获得线性化的时间值

---

### 9. 环形振荡器模块 (ro.v)

用于 TDC 自校准的随机信号源。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| en | Input | 1 | 使能信号 |
| ro_clk | Output | 1 | 振荡器输出 |

#### 实现

- 使用 LUT 级联形成反相器链
- 链长度为奇数（默认 17 级）
- 振荡频率取决于 LUT 延迟

---

### 10. 以太网通信控制模块 (eth_comm_ctrl_tdc.v)

处理双通道数据的以太网传输和命令解析。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| clk_200MHz | Input | 1 | 以太网时钟域 |
| clk_260MHz | Input | 1 | TDC 时钟域 |
| rst_200MHz/rst_260MHz | Input | 1 | 复位 |
| up_valid | Input | 1 | UP 通道有效 |
| up_fine | Input | 13 | UP 精细时间 |
| up_coarse | Input | 16 | UP 粗计数 |
| up_id | Input | 8 | UP 测量 ID |
| down_* | Input | - | DOWN 通道信号（同上） |
| gig_eth_tx_fifo_* | - | - | TX FIFO 接口 |
| gig_eth_rx_fifo_* | - | - | RX FIFO 接口 |
| manual_calib_trigger | Output | 1 | 手动校准触发 |
| scan_cmd_trigger | Output | 1 | 扫描命令触发 |
| scan_cmd_param | Output | 11 | 扫描参数 |

#### 数据包格式

**发送数据包（32位）**:
```
[31:30] = 数据类型 (00=UP, 01=DOWN, 10=INFO, 11=CMD)
[29:22] = 测量ID (8位)
[21:9]  = 精细时间 [12:0]
[8:0]   = 粗计数低9位
```

**接收命令格式**:
```
命令字 0xDEAD: 启动手动校准
命令字 0xBEEF + 参数: 扫描测试命令
```

---

### 11. 扫描测试控制模块 (tdc_scan_ctrl.v)

实现相位扫描测试功能。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| clk_260MHz | Input | 1 | 260MHz 时钟 |
| sys_reset | Input | 1 | 复位 |
| scan_cmd_trigger | Input | 1 | 扫描命令触发 |
| scan_cmd_param | Input | 11 | 命令参数 |
| scan_running | Output | 1 | 扫描运行标志 |
| scan_status | Output | 8 | 扫描状态 |
| test_pulse_up | Output | 1 | UP 测试脉冲 |
| test_pulse_down | Output | 1 | DOWN 测试脉冲 |
| tdc_reset_trigger | Output | 1 | TDC 复位触发 |

#### 命令参数格式

```
scan_cmd_param[10:0]:
  [10]   : 扫描模式 (0=单步, 1=全扫描)
  [9:8]  : 通道选择 (00=无, 10=UP, 01=DOWN, 11=UP+DOWN)
  [7:0]  : 相位参数 (0-255)
```

---

### 12. 动态相位脉冲生成器 (dynamic_phase_pulse_gen.v)

使用 MMCM 动态相位调整生成可控延迟脉冲。

#### 接口定义

| 信号名 | 方向 | 宽度 | 说明 |
|--------|------|------|------|
| clk_ref | Input | 1 | 260MHz 参考时钟 |
| reset | Input | 1 | 复位 |
| target_phase | Input | 8 | 目标相位步数 (0-255) |
| phase_load | Input | 1 | 加载新相位 |
| trigger | Input | 1 | 触发信号 |
| pulse_out | Output | 1 | 输出脉冲 |
| phase_ready | Output | 1 | 相位调整完成 |

#### 工作原理

1. 使用 MMCM 的动态相位调整功能
2. 每步相位约 13.9ps（1/56 周期）
3. 256 步可覆盖约 3.5ns 范围

---

## 上位机程序

### Python 控制脚本 (tdc_control.py)

```python
#!/usr/bin/env python3
"""
TDC 以太网控制程序
用于与 FPGA TDC 系统通信，发送命令并接收测量数据
"""

import socket
import struct
import time
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime

class TDCController:
    """TDC 控制器类"""
    
    def __init__(self, fpga_ip="192.168.1.10", port=1234):
        """
        初始化 TDC 控制器
        
        Args:
            fpga_ip: FPGA IP 地址
            port: UDP 端口号
        """
        self.fpga_ip = fpga_ip
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(1.0)
        
    def connect(self):
        """建立连接"""
        self.sock.bind(('', self.port))
        print(f"已绑定到端口 {self.port}")
        
    def send_command(self, cmd_word, param=0):
        """
        发送命令到 FPGA
        
        Args:
            cmd_word: 命令字 (0xDEAD=校准, 0xBEEF=扫描)
            param: 命令参数
        """
        # 构造命令包
        packet = struct.pack('>HH', cmd_word, param)
        self.sock.sendto(packet, (self.fpga_ip, self.port))
        
    def start_calibration(self):
        """启动手动校准"""
        self.send_command(0xDEAD)
        print("已发送校准命令")
        
    def start_scan(self, mode='full', channel='both', phase=0):
        """
        启动扫描测试
        
        Args:
            mode: 'single' 或 'full'
            channel: 'up', 'down', 或 'both'
            phase: 相位参数 (0-255)
        """
        # 构造参数
        param = phase & 0xFF
        
        if channel == 'up':
            param |= 0x200  # bit[9:8] = 10
        elif channel == 'down':
            param |= 0x100  # bit[9:8] = 01
        elif channel == 'both':
            param |= 0x300  # bit[9:8] = 11
            
        if mode == 'full':
            param |= 0x400  # bit[10] = 1
            
        self.send_command(0xBEEF, param)
        print(f"已发送扫描命令: mode={mode}, channel={channel}, phase={phase}")
        
    def receive_data(self, count=1000):
        """
        接收测量数据
        
        Args:
            count: 期望接收的数据点数
            
        Returns:
            list: 解析后的测量数据
        """
        data_list = []
        
        for _ in range(count):
            try:
                packet, addr = self.sock.recvfrom(4)
                raw = struct.unpack('>I', packet)[0]
                
                # 解析数据包
                data_type = (raw >> 30) & 0x03
                meas_id = (raw >> 22) & 0xFF
                fine = (raw >> 9) & 0x1FFF
                coarse_low = raw & 0x1FF
                
                data_list.append({
                    'type': 'UP' if data_type == 0 else 'DOWN',
                    'id': meas_id,
                    'fine': fine,
                    'coarse': coarse_low,
                    'raw': hex(raw)
                })
                
            except socket.timeout:
                break
                
        return data_list
        
    def run_full_scan(self, save_file=None):
        """
        执行完整的相位扫描测试
        
        Args:
            save_file: 保存文件路径
            
        Returns:
            dict: 扫描结果
        """
        results = {'up': [], 'down': []}
        
        print("开始全相位扫描测试...")
        self.start_scan(mode='full', channel='both')
        
        # 接收数据
        time.sleep(0.5)  # 等待扫描开始
        data = self.receive_data(count=512)  # 256 UP + 256 DOWN
        
        # 分类数据
        for d in data:
            if d['type'] == 'UP':
                results['up'].append(d)
            else:
                results['down'].append(d)
                
        print(f"接收到 {len(results['up'])} 个 UP 数据, {len(results['down'])} 个 DOWN 数据")
        
        # 保存数据
        if save_file:
            self.save_scan_data(results, save_file)
            
        return results
        
    def save_scan_data(self, results, filename):
        """保存扫描数据到文件"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filepath = f"{filename}_{timestamp}.txt"
        
        with open(filepath, 'w') as f:
            f.write(f"# TDC 扫描数据\n")
            f.write(f"# 生成时间: {datetime.now()}\n")
            f.write(f"# Index, Type, ID, Fine, Coarse, Raw_Hex\n")
            
            idx = 0
            for d in results['up']:
                f.write(f"{idx},UP,{d['id']},{d['fine']},{d['coarse']},{d['raw']}\n")
                idx += 1
            for d in results['down']:
                f.write(f"{idx},DOWN,{d['id']},{d['fine']},{d['coarse']},{d['raw']}\n")
                idx += 1
                
        print(f"数据已保存到 {filepath}")
        
    def plot_scan_results(self, results):
        """绘制扫描结果"""
        fig, axes = plt.subplots(2, 2, figsize=(12, 10))
        
        # UP 通道 Fine Time
        up_fine = [d['fine'] for d in results['up']]
        axes[0, 0].plot(up_fine, 'b-')
        axes[0, 0].set_title('UP Channel - Fine Time')
        axes[0, 0].set_xlabel('Phase Index')
        axes[0, 0].set_ylabel('Fine Time (ps)')
        
        # DOWN 通道 Fine Time
        down_fine = [d['fine'] for d in results['down']]
        axes[0, 1].plot(down_fine, 'r-')
        axes[0, 1].set_title('DOWN Channel - Fine Time')
        axes[0, 1].set_xlabel('Phase Index')
        axes[0, 1].set_ylabel('Fine Time (ps)')
        
        # 对比图
        axes[1, 0].plot(up_fine, 'b-', label='UP')
        axes[1, 0].plot(down_fine, 'r-', label='DOWN')
        axes[1, 0].set_title('Fine Time Comparison')
        axes[1, 0].set_xlabel('Phase Index')
        axes[1, 0].set_ylabel('Fine Time (ps)')
        axes[1, 0].legend()
        
        # DNL 分析
        if len(up_fine) > 1:
            diff = np.diff(up_fine)
            lsb = np.mean(np.abs(diff))
            dnl = diff / lsb - 1
            axes[1, 1].plot(dnl, 'g-')
            axes[1, 1].set_title(f'DNL Analysis (LSB={lsb:.2f}ps)')
            axes[1, 1].set_xlabel('Phase Index')
            axes[1, 1].set_ylabel('DNL (LSB)')
            axes[1, 1].axhline(y=0.5, color='r', linestyle='--')
            axes[1, 1].axhline(y=-0.5, color='r', linestyle='--')
        
        plt.tight_layout()
        plt.savefig('tdc_scan_results.png', dpi=150)
        plt.show()
        
    def close(self):
        """关闭连接"""
        self.sock.close()


# 使用示例
if __name__ == "__main__":
    tdc = TDCController(fpga_ip="192.168.1.10", port=1234)
    
    try:
        tdc.connect()
        
        # 执行校准
        tdc.start_calibration()
        time.sleep(2)
        
        # 执行扫描测试
        results = tdc.run_full_scan(save_file="tdc_scan")
        
        # 绘制结果
        tdc.plot_scan_results(results)
        
    finally:
        tdc.close()
```

---

## 测试数据

### 扫描测试结果 (2025-12-10 21:35:44)

以下是完整的相位扫描测试数据，包含 UP 和 DOWN 两个通道共 450 个测量点：

#### 数据格式说明

```
Index: 数据索引
Type: 通道类型 (UP/DOWN)
ID: 测量ID (0-255)
Fine: 精细时间 (皮秒)
Flag: 通道标志 (1=UP, 0=DOWN)
Coarse: 粗计数值 (时钟周期数)
Raw_Hex: 原始数据（十六进制）
```

#### 原始数据

```csv
# TDC 扫描数据
# 生成时间: 2025-12-10 21:35:44
# Index, Type, ID, Fine, Flag, Coarse, Raw_Hex
# Flag: UP通道标志=1, DOWN通道标志=0
# Coarse: 粗计数低8位 (包含粗计数和其他信息)
0,UP,0,3566,1,117,0x001BDD75
1,DOWN,0,3446,0,139,0x401AEC8B
2,UP,1,3529,1,117,0x005B9375
3,DOWN,1,3418,0,139,0x405AB48B
4,UP,2,3546,1,117,0x009BB575
5,DOWN,2,3459,0,139,0x409B068B
6,UP,3,3546,1,117,0x00DBB575
7,DOWN,3,3418,0,139,0x40DAB48B
8,UP,4,3499,1,117,0x011B5775
9,DOWN,4,3390,0,139,0x411A7C8B
10,UP,5,3499,1,117,0x015B5775
11,DOWN,5,3390,0,139,0x415A7C8B
12,UP,6,3478,1,117,0x019B2D75
13,DOWN,6,3365,0,139,0x419A4A8B
14,UP,7,3462,1,117,0x01DB0D75
15,DOWN,7,3348,0,139,0x41DA288B
16,UP,8,3447,1,117,0x021AEF75
17,DOWN,8,3337,0,139,0x421A128B
18,UP,9,3454,1,117,0x025AFD75
19,DOWN,9,3337,0,139,0x425A128B
20,UP,10,3425,1,117,0x029AC375
21,DOWN,10,3329,0,139,0x429A028B
22,UP,11,3397,1,117,0x02DA8B75
23,DOWN,11,3298,0,139,0x42D9C48B
24,UP,12,3397,1,117,0x031A8B75
25,DOWN,12,3268,0,139,0x4319888B
26,UP,13,3378,1,117,0x035A6575
27,DOWN,13,3268,0,139,0x4359888B
28,UP,14,3354,1,117,0x039A3575
29,DOWN,14,3237,0,139,0x43994A8B
30,UP,15,3301,1,117,0x03D9CB75
31,DOWN,15,3190,0,139,0x43D8EC8B
32,UP,16,3311,1,117,0x0419DF75
33,DOWN,16,3213,0,139,0x44191A8B
34,UP,17,3288,1,117,0x0459B175
35,DOWN,17,3174,0,139,0x4458CC8B
36,UP,18,3261,1,117,0x04997B75
37,DOWN,18,3159,0,139,0x4498AE8B
38,UP,19,3261,1,117,0x04D97B75
39,DOWN,19,3130,0,139,0x44D8748B
40,UP,20,3240,1,117,0x05195175
41,DOWN,20,3130,0,139,0x4518748B
42,UP,21,3214,1,117,0x05591D75
43,DOWN,21,3098,0,139,0x4558348B
44,UP,22,3189,1,117,0x0598EB75
45,DOWN,22,3083,0,139,0x4598168B
46,UP,23,3189,1,117,0x05D8EB75
47,DOWN,23,3083,0,139,0x45D8168B
48,UP,24,3189,1,117,0x0618EB75
49,DOWN,24,3059,0,139,0x4617E68B
50,UP,25,3152,1,116,0x0658A174
51,DOWN,25,3045,0,139,0x4657CA8B
52,UP,26,3152,1,116,0x0698A174
53,DOWN,26,3001,0,138,0x4697728A
54,UP,27,3117,1,116,0x06D85B74
55,DOWN,27,3001,0,138,0x46D7728A
56,UP,28,3080,1,116,0x07181174
57,DOWN,28,2965,0,138,0x47172A8A
58,UP,29,3043,1,116,0x0757C774
59,DOWN,29,2935,0,138,0x4756EE8A
60,UP,30,3043,1,116,0x0797C774
61,DOWN,30,2942,0,138,0x4796FC8A
```

**[完整数据见 tdc_results/tdc_scan_both_20251210_213544.txt]**

### 测试结果分析

根据扫描数据分析：

| 参数 | UP 通道 | DOWN 通道 | 单位 |
|------|---------|-----------|------|
| Fine Time 范围 | 9 ~ 3848 | 28 ~ 3850 | ps |
| Coarse 跳变点 | Phase 25, 208 | Phase 53, 201 | - |
| DNL RMS | 2.076 | - | LSB |
| INL RMS | 45.925 | - | LSB |

#### 关键观察

1. **线性度**: Fine Time 随相位索引线性递减，符合预期的相位扫描特性
2. **粗计数跳变**: 在 Fine Time 接近边界时发生粗计数跳变（±1）
3. **通道一致性**: UP 和 DOWN 通道呈现相似的线性趋势，存在固定偏移
4. **DNL 分析**: DNL 在 ±3 LSB 范围内波动，部分 bin 存在非线性

---

## 构建说明

### 环境要求

- Vivado 2020.1 或更高版本
- Python 3.8+ (上位机程序)
- Xilinx Kintex-7 开发板

### 综合与实现

```tcl
# 在 Vivado Tcl Console 中运行
open_project TDC_2.xpr
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

### 下载比特流

```tcl
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {TDC_2.runs/impl_1/test_tdc_eth.bit} [current_hw_device]
program_hw_device
```

---

## 文件结构

```
TDC_2/
├── TDC_2.xpr                    # Vivado 项目文件
├── README.md                     # 本文档
├── TDC_2.srcs/
│   ├── sources_1/
│   │   ├── new/
│   │   │   ├── test_tdc_eth.v           # 顶层模块
│   │   │   ├── tdc_eth_integrated.v     # TDC 集成模块
│   │   │   ├── tdc_clock_manager.v      # 时钟管理
│   │   │   ├── tdc_reset_sync.v         # 复位同步
│   │   │   ├── channel.v                # 测量通道
│   │   │   ├── dl_sync.v                # 延迟线同步
│   │   │   ├── delay_line.v             # 延迟线
│   │   │   ├── priority_encoder.v       # 优先编码器
│   │   │   ├── lut.v                    # 查找表校准
│   │   │   ├── ro.v                     # 环形振荡器
│   │   │   ├── eth_comm_ctrl_tdc.v      # 以太网通信
│   │   │   ├── tdc_scan_ctrl.v          # 扫描控制
│   │   │   ├── dynamic_phase_pulse_gen.v # 动态相位脉冲
│   │   │   ├── tdc_calib_ctrl.v         # 校准控制
│   │   │   ├── tdc_signal_mux.v         # 信号多路复用
│   │   │   ├── tdc_timestamp_capture.v  # 时间戳捕获
│   │   │   ├── tdc_cdc_sync.v           # CDC 同步
│   │   │   └── tdc_pkg.vh               # 参数定义
│   │   └── ip/                          # IP 核
│   └── constrs_1/
│       └── new/
│           └── tdc_eth_constraints.xdc  # 时序约束
├── tdc_results/                         # 测试结果
│   └── tdc_scan_both_20251210_213544.txt
└── python/                              # 上位机程序
    └── tdc_control.py
```

---

## 许可证

MIT License

## 作者

pan224

## 更新日志

- **2025-12-10**: 完成模块化重构，添加完整文档和测试数据
- **2025-12-09**: 修复时序违规，优化 CDC 路径
- **2025-12-08**: 实现扫描测试功能
