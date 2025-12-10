#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TDC 扫描测试程序
支持多种测试模式：单步测试、全扫描
命令协议:
  [31]     : 1=校准, 0=扫描测试
  [30]     : 扫描模式 (0=单步, 1=全扫描)
  [29:28]  : 通道选择 (00=无, 01=UP, 10=DOWN, 11=UP+DOWN)
  [27:20]  : 相位参数 (0-255)
  [19:0]   : 保留
"""

import socket
import struct
import time
import os
from datetime import datetime

try:
    import numpy as np
    import matplotlib.pyplot as plt
    plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'Arial Unicode MS']
    plt.rcParams['axes.unicode_minus'] = False
    PLOT_AVAILABLE = True
except ImportError:
    PLOT_AVAILABLE = False
    print("[WARN] numpy/matplotlib 未安装,数据可视化功能不可用")


class TDCScanner:
    """TDC 扫描控制器"""
    
    # 命令类型 ([31]位)
    CMD_SCAN = 0      # 0 = 扫描测试
    CMD_CALIB = 1     # 1 = 校准
    
    # 扫描模式 ([30]位)
    SCAN_SINGLE = 0   # 单步模式
    SCAN_FULL = 1     # 全扫描模式
    
    # 通道选择 ([29:28]位)
    CH_NONE = 0b00    # 无通道
    CH_DOWN = 0b01    # DOWN 通道
    CH_UP = 0b10      # UP 通道
    CH_BOTH = 0b11    # UP+DOWN 通道
    
    # 数据类型（接收数据的 [31:30] 位）
    TYPE_UP = 0b00
    TYPE_DOWN = 0b01
    TYPE_INFO = 0b10
    TYPE_CMD = 0b11
    
    def __init__(self, host='192.168.2.100', port=1024):
        self.host = host
        self.port = port
        self.sock = None
        self.connected = False
        
    def connect(self, timeout=5.0):
        """连接到FPGA"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(timeout)
            self.sock.connect((self.host, self.port))
            self.connected = True
            print(f"[INFO] 已连接到 {self.host}:{self.port}")
            
            # 清空接收缓冲区（丢弃旧数据）
            print("[INFO] 清空接收缓冲区...")
            self._clear_rx_buffer()
            
            return True
        except socket.error as e:
            print(f"[ERROR] 连接失败: {e}")
            return False
    
    def _clear_rx_buffer(self):
        """清空接收缓冲区"""
        self.sock.setblocking(False)
        discarded = 0
        try:
            while True:
                data = self.sock.recv(4096)
                if not data:
                    break
                discarded += len(data)
        except:
            pass
        finally:
            self.sock.setblocking(True)
        
        if discarded > 0:
            print(f"[INFO] 已丢弃 {discarded} 字节旧数据")
    
    def disconnect(self):
        """断开连接"""
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except:
                pass
            self.sock.close()
            self.connected = False
            print("[INFO] 连接已断开")
    
    def send_command(self, cmd_type, scan_mode=0, channel=0b11, phase=0):
        """
        发送命令到FPGA
        
        Args:
            cmd_type: 命令类型 (0=扫描, 1=校准)
            scan_mode: 扫描模式 (0=单步, 1=全扫描)
            channel: 通道选择 (0b00=无, 0b01=DOWN, 0b10=UP, 0b11=BOTH)
            phase: 相位参数 (0-255)
        
        Returns:
            bool: 是否发送成功
        """
        if not self.connected:
            print("[ERROR] 未连接到设备")
            return False
        
        # 构建命令:
        # [31]     = cmd_type (0=扫描, 1=校准)
        # [30]     = scan_mode (0=单步, 1=全扫描)
        # [29:28]  = channel (通道选择)
        # [27:20]  = phase (相位参数)
        # [19:0]   = 保留
        cmd_data = ((cmd_type & 0x1) << 31) | \
                   ((scan_mode & 0x1) << 30) | \
                   ((channel & 0x3) << 28) | \
                   ((phase & 0xFF) << 20)
        
        # 详细显示命令结构
        cmd_type_str = '校准' if cmd_type else '扫描'
        scan_mode_str = '全扫描' if scan_mode else '单步'
        channel_names = ['无', 'DOWN', 'UP', 'BOTH']
        
        print(f"[TX] 命令详情:")
        print(f"     完整命令: 0x{cmd_data:08X}")
        print(f"     [31]    Type: {cmd_type} ({cmd_type_str})")
        print(f"     [30]    Mode: {scan_mode} ({scan_mode_str})")
        print(f"     [29:28] Channel: 0b{channel:02b} ({channel_names[channel]})")
        print(f"     [27:20] Phase: {phase}")
        
        try:
            data = struct.pack('>I', cmd_data)
            self.sock.sendall(data)
            print(f"[TX] 发送成功")
            
            # 确保数据发送完毕
            time.sleep(0.1)
            return True
        except Exception as e:
            print(f"[ERROR] 发送失败: {e}")
            return False
    
    def receive_data(self, expected_count, timeout=3.0):
        """
        接收指定数量的数据
        
        Args:
            expected_count: 期望接收的数据包数量
            timeout: 超时时间(秒)
        
        Returns:
            list: 接收到的数据列表 [(type, id, fine, coarse), ...]
        """
        if not self.connected:
            print("[ERROR] 未连接到设备")
            return []
        
        data_list = []
        start_time = time.time()
        
        print(f"[INFO] 等待接收 {expected_count} 个数据包...")
        
        # 设置接收超时
        self.sock.settimeout(1.0)  # 增加超时时间
        
        while len(data_list) < expected_count:
            # 检查超时
            if time.time() - start_time > timeout:
                print(f"[WARN] 接收超时,仅收到 {len(data_list)}/{expected_count} 个数据包")
                break
            
            try:
                raw_data = self.sock.recv(4)
                
                if len(raw_data) == 4:
                    value = struct.unpack('>I', raw_data)[0]
                    
                    # 解析数据包
                    # [31:30] = 类型 (00=UP, 01=DOWN, 10=INFO, 11=CMD)
                    # [29:22] = ID (相位索引)
                    # [21:9]  = 精细时间 (13-bit)
                    # [8]     = 通道标志 (1=UP通道, 0=DOWN通道)
                    # [7:0]   = 粗计数低8位
                    data_type = (value >> 30) & 0x3
                    data_id = (value >> 22) & 0xFF
                    fine_time = (value >> 9) & 0x1FFF
                    channel_flag = (value >> 8) & 0x1    # 提取bit[8]的flag
                    coarse_time = value & 0xFF           # 粗计数低8位
                    
                    # 过滤命令类型的回显数据
                    if data_type == 0b11:  # CMD 类型
                        print(f"[RX] 忽略命令回显: 0x{value:08X}")
                        continue
                    
                    data_list.append({
                        'type': data_type,
                        'id': data_id,
                        'fine': fine_time,
                        'coarse': coarse_time,
                        'flag': channel_flag,    # 添加flag字段
                        'raw': value
                    })
                    
                    # 实时显示前几个数据包用于调试
                    if len(data_list) <= 10:  # 增加显示数量
                        type_str = ['UP', 'DOWN', 'INFO', 'CMD'][data_type]
                        flag_info = f", Flag={channel_flag}, Coarse={coarse_time}"
                        print(f"[RX] 数据包#{len(data_list)}: Type={type_str}, ID={data_id}, Fine={fine_time}{flag_info}, Raw=0x{value:08X}")
                    
                    # 进度显示
                    elif len(data_list) % 50 == 0 or len(data_list) == expected_count:
                        print(f"[RX] 进度: {len(data_list)}/{expected_count}")
                
                elif len(raw_data) == 0:
                    print("[WARN] 连接断开")
                    break
                    
            except socket.timeout:
                continue
            except Exception as e:
                print(f"[ERROR] 接收错误: {e}")
                break
        
        print(f"[INFO] 接收完成,共 {len(data_list)} 个数据包")
        return data_list
    
    def start_scan(self, scan_mode=1, phase=224, channel=0b11):
        """
        启动扫描测试
        
        Args:
            scan_mode: 扫描模式
                      0 = 单步测试（指定相位）
                      1 = 全扫描（0到phase的所有相位）
            phase: 相位参数 (0-255, 推荐0-224)
                   单步模式: 测试指定相位
                   全扫描模式: 从0扫描到此相位值
                   注: 225步(17.17ps/step)可覆盖完整3864ps周期
            channel: 通道选择
                    0b00 = 无
                    0b01 = DOWN only
                    0b10 = UP only
                    0b11 = BOTH (默认)
        
        Returns:
            bool: 是否成功启动
        """
        mode_str = '全扫描' if scan_mode else '单步'
        ch_names = ['无', 'DOWN', 'UP', 'BOTH']
        print(f"[CMD] 启动扫描测试 (模式={mode_str}, 相位={phase}, 通道={ch_names[channel]})")
        return self.send_command(
            cmd_type=self.CMD_SCAN,
            scan_mode=scan_mode,
            channel=channel,
            phase=phase
        )
    
    def start_calibration(self):
        """启动手动校准"""
        print("[CMD] 启动手动校准")
        return self.send_command(
            cmd_type=self.CMD_CALIB,
            scan_mode=0,
            channel=0,
            phase=0
        )


class TDCDataProcessor:
    """TDC 数据处理器"""
    
    def __init__(self, data_list):
        """
        Args:
            data_list: 接收到的数据列表
        """
        self.data_list = data_list
        
        # 时间常数 (260MHz系统)
        self.CLK_PERIOD = 3864  # ps (1/260MHz)
        self.TDC_BIN = 1        # fine值已经是ps单位，不需要转换
        self.PHASE_STEP = 17.17 # ps/step (VCO=1040MHz, 1/1040M/56=17.17ps)
        
        # 分离UP和DOWN通道
        self.up_data = [d for d in data_list if d['type'] == 0b00]
        self.down_data = [d for d in data_list if d['type'] == 0b01]
        
    def process(self):
        """处理和分析数据"""
        print("\n" + "="*70)
        print("TDC 数据分析")
        print("="*70)
        
        print(f"总数据包: {len(self.data_list)}")
        print(f"UP 通道: {len(self.up_data)} 个")
        print(f"DOWN 通道: {len(self.down_data)} 个")
        
        if len(self.up_data) == 0 and len(self.down_data) == 0:
            print("[WARN] 没有有效数据")
            return
        
        # 分析UP通道
        if len(self.up_data) > 0:
            self._analyze_channel(self.up_data, "UP")
        
        # 分析DOWN通道
        if len(self.down_data) > 0:
            self._analyze_channel(self.down_data, "DOWN")
        
        # 如果是扫描模式(225+个相位),分析延迟曲线
        if len(self.up_data) >= 225:
            self._analyze_scan_curve()
        
        # 如果有足够的数据，进行TDC性能分析
        if len(self.up_data) >= 10:
            self.analyze_tdc_performance()
        
        print("="*70 + "\n")
    
    def _analyze_channel(self, channel_data, channel_name):
        """分析单个通道的数据"""
        print(f"\n{channel_name} 通道分析:")
        print("-" * 50)
        
        if not PLOT_AVAILABLE:
            # 基本统计
            fine_vals = [d['fine'] for d in channel_data]
            coarse_vals = [d['coarse'] for d in channel_data]
            
            print(f"  样本数: {len(channel_data)}")
            print(f"  Fine 范围: {min(fine_vals)} - {max(fine_vals)}")
            print(f"  Coarse 范围: {min(coarse_vals)} - {max(coarse_vals)}")
            return
        
        # 使用numpy进行分析
        fine = np.array([d['fine'] for d in channel_data])
        coarse = np.array([d['coarse'] for d in channel_data])
        ids = np.array([d['id'] for d in channel_data])
        
        # 计算时间
        fine_time = fine * self.TDC_BIN  # ps (fine值已经是ps，乘以1保持不变)
        coarse_time = coarse * self.CLK_PERIOD  # ps
        total_time = coarse_time + fine_time
        
        print(f"  样本数: {len(channel_data)}")
        print(f"  ID 范围: {ids.min()} - {ids.max()}")
        print(f"  Fine 范围: {fine.min()} - {fine.max()}")
        print(f"  Coarse 范围: {coarse.min()} - {coarse.max()}")
        print(f"  Fine 时间: {fine_time.min():.1f} - {fine_time.max():.1f} ps")
        print(f"  Total 时间: {total_time.min():.1f} - {total_time.max():.1f} ps")
        
        if len(channel_data) > 1:
            print(f"  Fine 标准差: {fine.std():.2f}")
            print(f"  Time 标准差: {total_time.std():.2f} ps")
    
    def _analyze_scan_curve(self):
        """分析扫描曲线 - 考虑固定布线延迟导致的偏移和环绕"""
        if not PLOT_AVAILABLE:
            return
        
        print(f"\n扫描模式分析 ({len(self.up_data)}个相位):")
        print("-" * 50)
        print(f"提示: 225步(17.17ps/step)可覆盖完整3864ps周期")
        
        # 提取fine time (fine值已经是ps)
        fine = np.array([d['fine'] for d in self.up_data])
        ids = np.array([d['id'] for d in self.up_data])
        
        # 实际测量的fine time (单位: ps)
        actual_fine_time = fine  # 已经是ps，不需要转换
        
        # 理论关系（无布线延迟）: 
        # Phase_Delay = Phase × PHASE_STEP
        # Fine_Time = CLK_PERIOD - Phase_Delay (单调递减)
        #
        # 实际关系（有固定布线延迟D）:
        # Actual_Delay = Phase × PHASE_STEP + D
        # Fine_Time = (Actual_Delay) mod CLK_PERIOD
        # 当 Actual_Delay > CLK_PERIOD 时发生环绕
        
        phase_indices = ids
        theoretical_fine_no_delay = self.CLK_PERIOD - self.PHASE_STEP * phase_indices
        
        # 检测环绕点（曲线跳变的位置）
        diffs = np.diff(actual_fine_time)
        jump_threshold = self.CLK_PERIOD / 2  # 超过半个周期的跳变
        wrap_points = np.where(np.abs(diffs) > jump_threshold)[0]
        
        print(f"  相位范围: {phase_indices.min()} - {phase_indices.max()}")
        print(f"  Fine time 范围: {actual_fine_time.min():.1f} - {actual_fine_time.max():.1f} ps")
        print(f"  Fine time 变化幅度: {actual_fine_time.max() - actual_fine_time.min():.1f} ps")
        print(f"  理论关系（无延迟）: Fine = {self.CLK_PERIOD:.0f} - Phase × {self.PHASE_STEP:.2f}")
        
        # 估计布线延迟
        if len(wrap_points) > 0:
            print(f"  \n检测到 {len(wrap_points)} 个环绕点（固定布线延迟导致）")
            for i, wp in enumerate(wrap_points):
                wrap_phase = phase_indices[wp]
                # 在环绕点，Phase × PHASE_STEP + Delay ≈ CLK_PERIOD
                estimated_delay = self.CLK_PERIOD - wrap_phase * self.PHASE_STEP
                print(f"    环绕点{i+1}: Phase {phase_indices[wp]} → {phase_indices[wp+1]}")
                print(f"              估计布线延迟 ≈ {estimated_delay:.1f} ps")
        
        # 计算线性度（使用理论递减斜率）
        if len(phase_indices) > 2:
            # 对fine time进行线性拟合
            coeffs = np.polyfit(phase_indices, actual_fine_time, 1)
            fit_line = np.polyval(coeffs, phase_indices)
            residuals = actual_fine_time - fit_line
            
            print(f"  实际斜率: {coeffs[0]:.3f} ps/phase (理论: {-self.PHASE_STEP:.2f})")
            print(f"  斜率误差: {abs(coeffs[0] + self.PHASE_STEP):.3f} ps/phase")
            print(f"  RMS 误差: {np.sqrt(np.mean(residuals**2)):.2f} ps")
            print(f"  最大偏差: {np.max(np.abs(residuals)):.2f} ps")
    
    def analyze_tdc_performance(self):
        """
        TDC性能分析：测量范围、精度、DNL/INL、噪声
        适用于存在布线延迟导致的非理想测量曲线
        """
        if not PLOT_AVAILABLE:
            print("[WARN] numpy不可用，无法进行性能分析")
            return None
        
        if len(self.up_data) < 10:
            print("[WARN] 数据量不足，无法进行性能分析")
            return None
        
        print("\n" + "="*70)
        print("TDC 性能分析")
        print("="*70)
        print("说明: 测量值 = (相位延迟 + 固定布线延迟) mod 时钟周期")
        print("      固定布线延迟导致曲线整体偏移，超过周期时发生环绕")
        print("="*70)
        
        # 使用UP通道数据进行分析
        fine_values = np.array([d['fine'] for d in self.up_data])
        phase_ids = np.array([d['id'] for d in self.up_data])
        
        performance = {}
        
        # 1. 测量范围分析
        print("\n[1] 测量范围分析:")
        print("-" * 50)
        measured_range = fine_values.max() - fine_values.min()
        print(f"  最小值: {fine_values.min():.2f} ps")
        print(f"  最大值: {fine_values.max():.2f} ps")
        print(f"  测量范围: {measured_range:.2f} ps")
        print(f"  理论范围: {self.CLK_PERIOD:.2f} ps (时钟周期)")
        print(f"  范围覆盖率: {(measured_range/self.CLK_PERIOD)*100:.1f}%")
        print(f"  注: 布线延迟导致整体偏移，但不影响测量范围")
        
        performance['range'] = {
            'min': float(fine_values.min()),
            'max': float(fine_values.max()),
            'span': float(measured_range),
            'coverage': float((measured_range/self.CLK_PERIOD)*100)
        }
        
        # 2. 分辨率和精度分析（使用差分方法，考虑单调递减）
        print("\n[2] 分辨率和精度分析:")
        print("-" * 50)
        
        # 对相位进行排序，计算相邻相位的时间差
        sorted_indices = np.argsort(phase_ids)
        sorted_phases = phase_ids[sorted_indices]
        sorted_times = fine_values[sorted_indices]
        
        # 计算相邻测量点的时间差（理论上应该递减，所以取绝对值）
        time_diffs = np.diff(sorted_times)
        
        # 过滤环绕跳变点（超过半个周期的突变）
        jump_mask = np.abs(time_diffs) < self.CLK_PERIOD/2
        valid_diffs = time_diffs[jump_mask]
        
        if len(valid_diffs) > 0:
            avg_resolution = np.abs(valid_diffs).mean()
            resolution_std = np.abs(valid_diffs).std()
            
            # 检查是递增还是递减
            decreasing_ratio = np.sum(valid_diffs < 0) / len(valid_diffs)
            
            print(f"  平均步进: {avg_resolution:.3f} ps")
            print(f"  步进标准差: {resolution_std:.3f} ps")
            print(f"  理论步进: {self.PHASE_STEP:.3f} ps")
            print(f"  步进误差: {abs(avg_resolution - self.PHASE_STEP):.3f} ps")
            print(f"  递减比例: {decreasing_ratio*100:.1f}% (理论100%为单调递减)")
            
            performance['resolution'] = {
                'avg_step': float(avg_resolution),
                'std_step': float(resolution_std),
                'theoretical_step': float(self.PHASE_STEP),
                'decreasing_ratio': float(decreasing_ratio)
            }
        
        # 3. LSB（最小有效位）分析
        print("\n[3] LSB 分析:")
        print("-" * 50)
        
        # 统计所有不同的fine值
        unique_values = np.unique(fine_values)
        if len(unique_values) > 1:
            # 计算最小间隔作为LSB估计
            value_diffs = np.diff(np.sort(unique_values))
            lsb_estimate = value_diffs[value_diffs > 0].min()
            print(f"  检测到的唯一值数量: {len(unique_values)}")
            print(f"  估计LSB: {lsb_estimate:.3f} ps")
            print(f"  理论量化等级: {int(self.CLK_PERIOD / lsb_estimate)}")
            
            performance['lsb'] = {
                'unique_values': int(len(unique_values)),
                'estimated_lsb': float(lsb_estimate),
                'quantization_levels': int(self.CLK_PERIOD / lsb_estimate)
            }
        
        # 4. DNL (Differential Non-Linearity) 分析
        print("\n[4] DNL (差分非线性) 分析:")
        print("-" * 50)
        
        if len(valid_diffs) > 0:
            # DNL = (实际步进 - 理想步进) / 理想步进
            ideal_step = avg_resolution
            dnl = (valid_diffs - ideal_step) / ideal_step
            dnl_lsb = dnl  # 单位：LSB
            
            print(f"  DNL 最大值: {dnl_lsb.max():.3f} LSB")
            print(f"  DNL 最小值: {dnl_lsb.min():.3f} LSB")
            print(f"  DNL RMS: {np.sqrt(np.mean(dnl_lsb**2)):.3f} LSB")
            print(f"  DNL 标准差: {dnl_lsb.std():.3f} LSB")
            
            performance['dnl'] = {
                'max': float(dnl_lsb.max()),
                'min': float(dnl_lsb.min()),
                'rms': float(np.sqrt(np.mean(dnl_lsb**2))),
                'std': float(dnl_lsb.std())
            }
        
        # 5. INL (Integral Non-Linearity) 分析
        print("\n[5] INL (积分非线性) 分析:")
        print("-" * 50)
        
        # 检测环绕点，分段处理
        if len(sorted_times) > 2:
            time_jumps = np.diff(sorted_times)
            wrap_indices = np.where(np.abs(time_jumps) > self.CLK_PERIOD/2)[0]
            
            if len(wrap_indices) == 0:
                # 无环绕，直接线性拟合
                coeffs = np.polyfit(sorted_phases, sorted_times, 1)
                ideal_line = np.polyval(coeffs, sorted_phases)
                inl = sorted_times - ideal_line
                
                print(f"  拟合模式: 单段线性 (无环绕)")
                print(f"  估计布线延迟: {self.CLK_PERIOD - coeffs[1]:.1f} ps (从截距计算)")
            else:
                # 有环绕，将环绕后的数据"展开"拼接成连续曲线
                print(f"  拟合模式: 展开环绕 (检测到{len(wrap_indices)}个环绕点)")
                
                # 估计布线延迟：在环绕点，Phase × PHASE_STEP + Delay ≈ CLK_PERIOD
                wrap_phase = sorted_phases[wrap_indices[0]]
                estimated_delay = self.CLK_PERIOD - wrap_phase * self.PHASE_STEP
                print(f"  估计布线延迟: {estimated_delay:.1f} ps")
                print(f"  环绕点位置: Phase {wrap_phase}")
                
                # 将环绕后的数据"展开"：加上时钟周期，使曲线连续
                unwrapped_times = sorted_times.copy()
                for i in range(len(wrap_indices)):
                    wrap_idx = wrap_indices[i]
                    # 环绕后的所有点都加上一个周期（或多个周期）
                    if i == 0:
                        # 第一个环绕点后，加上一个周期
                        unwrapped_times[wrap_idx+1:] += self.CLK_PERIOD
                    else:
                        # 如果有多个环绕点，累加周期数
                        unwrapped_times[wrap_idx+1:] += self.CLK_PERIOD
                
                print(f"  展开前范围: {sorted_times.min():.1f} - {sorted_times.max():.1f} ps")
                print(f"  展开后范围: {unwrapped_times.min():.1f} - {unwrapped_times.max():.1f} ps")
                
                # 对展开后的连续数据进行线性拟合
                coeffs = np.polyfit(sorted_phases, unwrapped_times, 1)
                ideal_line = np.polyval(coeffs, sorted_phases)
                
                # 计算INL（展开后的数据相对理想线的偏差）
                inl = unwrapped_times - ideal_line
                
                print(f"  数据点总数: {len(sorted_phases)}")
            
            inl_lsb = inl / avg_resolution if len(valid_diffs) > 0 else inl
            
            print(f"  拟合斜率: {coeffs[0]:.3f} ps/phase (理论: {-self.PHASE_STEP:.2f})")
            print(f"  INL 最大值: {inl_lsb.max():.3f} LSB ({inl.max():.2f} ps)")
            print(f"  INL 最小值: {inl_lsb.min():.3f} LSB ({inl.min():.2f} ps)")
            print(f"  INL RMS: {np.sqrt(np.mean(inl_lsb**2)):.3f} LSB ({np.sqrt(np.mean(inl**2)):.2f} ps)")
            print(f"  INL 峰峰值: {inl_lsb.max() - inl_lsb.min():.3f} LSB ({inl.max() - inl.min():.2f} ps)")
            
            performance['inl'] = {
                'max_lsb': float(inl_lsb.max()),
                'min_lsb': float(inl_lsb.min()),
                'rms_lsb': float(np.sqrt(np.mean(inl_lsb**2))),
                'peak_to_peak_lsb': float(inl_lsb.max() - inl_lsb.min()),
                'max_ps': float(inl.max()),
                'min_ps': float(inl.min()),
                'rms_ps': float(np.sqrt(np.mean(inl**2))),
                'peak_to_peak_ps': float(inl.max() - inl.min()),
                'wrap_points': int(len(wrap_indices))
            }
        
        # 6. 噪声分析（多次测量同一相位）
        print("\n[6] 噪声分析:")
        print("-" * 50)
        
        # 统计每个相位的测量次数和标准差
        phase_noise = {}
        for phase_id in np.unique(phase_ids):
            measurements = fine_values[phase_ids == phase_id]
            if len(measurements) > 1:
                phase_noise[phase_id] = {
                    'count': len(measurements),
                    'mean': measurements.mean(),
                    'std': measurements.std(),
                    'range': measurements.max() - measurements.min()
                }
        
        if phase_noise:
            all_stds = [v['std'] for v in phase_noise.values()]
            avg_noise = np.mean(all_stds)
            print(f"  重复测量的相位数: {len(phase_noise)}")
            print(f"  平均噪声标准差: {avg_noise:.3f} ps")
            print(f"  最大噪声标准差: {max(all_stds):.3f} ps")
            
            performance['noise'] = {
                'repeated_phases': len(phase_noise),
                'avg_std': float(avg_noise),
                'max_std': float(max(all_stds))
            }
        else:
            print("  无重复测量数据，建议多次测量同一相位以评估噪声")
            performance['noise'] = {'note': 'No repeated measurements'}
        
        # 7. 单调性检查（理论应单调递减）
        print("\n[7] 单调性分析:")
        print("-" * 50)
        
        # 过滤环绕跳变后统计
        valid_transitions = time_diffs[jump_mask]
        monotonic_increases = np.sum(valid_transitions > 0)
        monotonic_decreases = np.sum(valid_transitions < 0)
        total_valid = len(valid_transitions)
        
        print(f"  有效转换数: {total_valid} (已过滤{len(time_diffs)-total_valid}个环绕点)")
        print(f"  递减转换: {monotonic_decreases} ({(monotonic_decreases/total_valid)*100:.1f}%)")
        print(f"  递增转换: {monotonic_increases} ({(monotonic_increases/total_valid)*100:.1f}%)")
        
        # 理论上应该是单调递减
        if monotonic_decreases > monotonic_increases:
            monotonicity_quality = (monotonic_decreases/total_valid)*100
            print(f"  结论: 主要呈递减趋势 ✓ (单调性{monotonicity_quality:.1f}%)")
        else:
            print(f"  结论: ⚠ 递增比例异常，检查测量配置")
        
        performance['monotonicity'] = {
            'increases': int(monotonic_increases),
            'decreases': int(monotonic_decreases),
            'total': int(total_valid),
            'wrap_filtered': int(len(time_diffs)-total_valid)
        }
        
        print("\n" + "="*70 + "\n")
        
        return performance
    
    def save_to_file(self, filename=None, output_dir='tdc_results'):
        """保存数据到文件"""
        # 创建输出目录
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            print(f"[INFO] 创建输出目录: {output_dir}")
        
        if filename is None:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"tdc_scan_{timestamp}.txt"
        
        # 组合完整路径
        filepath = os.path.join(output_dir, filename)
        
        try:
            with open(filepath, 'w') as f:
                f.write("# TDC 扫描数据\n")
                f.write(f"# 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write("# Index, Type, ID, Fine, Flag, Coarse, Raw_Hex\n")
                f.write("# Flag: UP通道标志=1, DOWN通道标志=0\n")
                f.write("# Coarse: 粗计数低8位 (完整粗计数需结合其他信息)\n")
                
                for i, d in enumerate(self.data_list):
                    type_str = "UP" if d['type'] == 0b00 else ("DOWN" if d['type'] == 0b01 else "INFO")
                    flag = d.get('flag', 0)  # 兼容旧数据
                    f.write(f"{i},{type_str},{d['id']},{d['fine']},{flag},{d['coarse']},0x{d['raw']:08X}\n")
            
            print(f"[INFO] 数据已保存到: {filepath}")
            return filepath
        except Exception as e:
            print(f"[ERROR] 保存失败: {e}")
            return None
    
    def plot(self, save_file=None):
        """绘制数据图表，包括性能分析图"""
        if not PLOT_AVAILABLE:
            print("[WARN] matplotlib 不可用,无法绘图")
            return
        
        if len(self.data_list) == 0:
            print("[WARN] 没有数据可绘制")
            return
        
        # 判断是否有足够数据进行性能分析
        show_performance = len(self.up_data) >= 10
        
        # 创建图表 - 根据数据量选择布局
        if show_performance:
            fig, axes = plt.subplots(4, 2, figsize=(14, 20))
        else:
            fig, axes = plt.subplots(3, 2, figsize=(14, 15))
        
        fig.suptitle('TDC 扫描数据分析\n(测量值 = 相位延迟 + 固定布线延迟)', 
                    fontsize=16, fontweight='bold')
        
        # 子图1: UP通道 Fine Time
        if len(self.up_data) > 0:
            up_ids = [d['id'] for d in self.up_data]
            up_fine = np.array([d['fine'] for d in self.up_data])  # 已经是ps
            
            axes[0, 0].plot(up_ids, up_fine, 'b.-', markersize=3, linewidth=1)
            axes[0, 0].set_xlabel('相位索引 (Phase ID)')
            axes[0, 0].set_ylabel('Fine Time (ps)')
            axes[0, 0].set_title('UP 通道 - Fine Time\n(理论: 递减曲线 + 固定偏移)')
            axes[0, 0].grid(True, alpha=0.3)
        
        # 子图2: DOWN通道 Fine Time
        if len(self.down_data) > 0:
            down_ids = [d['id'] for d in self.down_data]
            down_fine = np.array([d['fine'] for d in self.down_data])  # 已经是ps
            
            axes[0, 1].plot(down_ids, down_fine, 'r.-', markersize=3, linewidth=1)
            axes[0, 1].set_xlabel('相位索引 (Phase ID)')
            axes[0, 1].set_ylabel('Fine Time (ps)')
            axes[0, 1].set_title('DOWN 通道 - Fine Time\n(理论: 递减曲线 + 固定偏移)')
            axes[0, 1].grid(True, alpha=0.3)
        
        # 子图3: UP通道 Coarse Time
        if len(self.up_data) > 0:
            up_ids = [d['id'] for d in self.up_data]
            up_coarse = np.array([d['coarse'] for d in self.up_data])
            
            axes[1, 0].plot(up_ids, up_coarse, 'b.-', markersize=3, linewidth=1)
            axes[1, 0].set_xlabel('相位索引 (Phase ID)')
            axes[1, 0].set_ylabel('Coarse Count (低8位)')
            axes[1, 0].set_title('UP 通道 - Coarse Count')
            axes[1, 0].grid(True, alpha=0.3)
        
        # 子图4: DOWN通道 Coarse Time
        if len(self.down_data) > 0:
            down_ids = [d['id'] for d in self.down_data]
            down_coarse = np.array([d['coarse'] for d in self.down_data])
            
            axes[1, 1].plot(down_ids, down_coarse, 'r.-', markersize=3, linewidth=1)
            axes[1, 1].set_xlabel('相位索引 (Phase ID)')
            axes[1, 1].set_ylabel('Coarse Count (低8位)')
            axes[1, 1].set_title('DOWN 通道 - Coarse Count')
            axes[1, 1].grid(True, alpha=0.3)
        
        # 子图5: Fine Time 分布
        if len(self.up_data) > 0:
            up_fine = np.array([d['fine'] for d in self.up_data])
            axes[2, 0].hist(up_fine, bins=50, alpha=0.7, color='blue', edgecolor='black', label='UP')
        
        if len(self.down_data) > 0:
            down_fine = np.array([d['fine'] for d in self.down_data])
            axes[2, 0].hist(down_fine, bins=50, alpha=0.7, color='red', edgecolor='black', label='DOWN')
        
        axes[2, 0].set_xlabel('Fine Count')
        axes[2, 0].set_ylabel('频数')
        axes[2, 0].set_title('Fine Count 分布')
        axes[2, 0].legend()
        axes[2, 0].grid(True, alpha=0.3)
        
        # 子图6: 扫描曲线对比
        if len(self.up_data) > 0 and len(self.down_data) > 0:
            up_ids = np.array([d['id'] for d in self.up_data])
            up_fine = np.array([d['fine'] for d in self.up_data])  # 已经是ps
            
            down_ids = np.array([d['id'] for d in self.down_data])
            down_fine = np.array([d['fine'] for d in self.down_data])  # 已经是ps
            
            axes[2, 1].plot(up_ids, up_fine, 'b.-', markersize=2, linewidth=1, label='UP', alpha=0.7)
            axes[2, 1].plot(down_ids, down_fine, 'r.-', markersize=2, linewidth=1, label='DOWN', alpha=0.7)
            axes[2, 1].set_xlabel('相位索引 (Phase ID)')
            axes[2, 1].set_ylabel('Fine Time (ps)')
            axes[2, 1].set_title('Fine Time 扫描曲线对比')
            axes[2, 1].legend()
            axes[2, 1].grid(True, alpha=0.3)
        elif len(self.up_data) > 0:
            # 只有UP通道数据
            up_ids = np.array([d['id'] for d in self.up_data])
            up_fine = np.array([d['fine'] for d in self.up_data])  # 已经是ps
            axes[2, 1].plot(up_ids, up_fine, 'b.-', markersize=2, linewidth=1, label='UP', alpha=0.7)
            axes[2, 1].set_xlabel('相位索引 (Phase ID)')
            axes[2, 1].set_ylabel('Fine Time (ps)')
            axes[2, 1].set_title('Fine Time 扫描曲线 (UP通道)')
            axes[2, 1].legend()
            axes[2, 1].grid(True, alpha=0.3)
        elif len(self.down_data) > 0:
            # 只有DOWN通道数据
            down_ids = np.array([d['id'] for d in self.down_data])
            down_fine = np.array([d['fine'] for d in self.down_data])  # 已经是ps
            axes[2, 1].plot(down_ids, down_fine, 'r.-', markersize=2, linewidth=1, label='DOWN', alpha=0.7)
            axes[2, 1].set_xlabel('相位索引 (Phase ID)')
            axes[2, 1].set_ylabel('Fine Time (ps)')
            axes[2, 1].set_title('Fine Time 扫描曲线 (DOWN通道)')
            axes[2, 1].legend()
            axes[2, 1].grid(True, alpha=0.3)
        else:
            axes[2, 1].text(0.5, 0.5, '无数据',
                          ha='center', va='center', transform=axes[2, 1].transAxes, fontsize=12)
        
        # 如果有足够数据，绘制DNL和INL图
        if show_performance and len(self.up_data) >= 10:
            up_fine = np.array([d['fine'] for d in self.up_data])
            up_ids = np.array([d['id'] for d in self.up_data])
            
            # 排序
            sorted_indices = np.argsort(up_ids)
            sorted_phases = up_ids[sorted_indices]
            sorted_times = up_fine[sorted_indices]
            
            # 子图7: DNL
            if len(sorted_times) > 1:
                time_diffs = np.diff(sorted_times)
                valid_mask = np.abs(time_diffs) < self.CLK_PERIOD/2
                valid_diffs = time_diffs[valid_mask]
                valid_phases = sorted_phases[:-1][valid_mask]
                
                if len(valid_diffs) > 0:
                    ideal_step = np.abs(valid_diffs).mean()
                    dnl = (valid_diffs - ideal_step) / ideal_step
                    
                    axes[3, 0].plot(valid_phases, dnl, 'g.-', markersize=2, linewidth=1)
                    axes[3, 0].axhline(y=0, color='r', linestyle='--', linewidth=1, alpha=0.5)
                    axes[3, 0].set_xlabel('相位索引 (Phase ID)')
                    axes[3, 0].set_ylabel('DNL (LSB)')
                    axes[3, 0].set_title(f'DNL 分析 (RMS={np.sqrt(np.mean(dnl**2)):.3f} LSB)')
                    axes[3, 0].grid(True, alpha=0.3)
            
            # 子图8: INL
            if len(sorted_times) > 2:
                coeffs = np.polyfit(sorted_phases, sorted_times, 1)
                ideal_line = np.polyval(coeffs, sorted_phases)
                inl = sorted_times - ideal_line
                
                if len(valid_diffs) > 0:
                    inl_lsb = inl / ideal_step
                    
                    axes[3, 1].plot(sorted_phases, inl_lsb, 'm.-', markersize=2, linewidth=1)
                    axes[3, 1].axhline(y=0, color='r', linestyle='--', linewidth=1, alpha=0.5)
                    axes[3, 1].set_xlabel('相位索引 (Phase ID)')
                    axes[3, 1].set_ylabel('INL (LSB)')
                    axes[3, 1].set_title(f'INL 分析 (RMS={np.sqrt(np.mean(inl_lsb**2)):.3f} LSB)')
                    axes[3, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        
        # 保存或显示
        if save_file:
            plt.savefig(save_file, dpi=300, bbox_inches='tight')
            print(f"[INFO] 图表已保存到: {save_file}")
        else:
            plt.show()


def show_menu():
    """显示主菜单"""
    print("\n" + "="*70)
    print("TDC 扫描测试程序 - 交互式菜单")
    print("="*70)
    print("\n请选择操作:")
    print("  1. 全扫描 (0-224, 双通道) [推荐:225步覆盖完整周期]")
    print("  2. 全扫描 (指定结束相位)")
    print("  3. 单步测试 (指定相位)")
    print("  4. 单通道测试 (UP only)")
    print("  5. 单通道测试 (DOWN only)")
    print("  6. 连续单步扫描 (0-224, 模拟全扫描)")
    print("  7. 校准 TDC")
    print("  8. TDC性能分析 (需要先进行扫描测试)")
    print("  0. 退出程序")
    print("="*70)


def get_user_input(prompt, default=None, value_type=int, valid_range=None):
    """获取用户输入并验证"""
    while True:
        try:
            if default is not None:
                user_input = input(f"{prompt} [默认={default}]: ").strip()
                if not user_input:
                    return default
            else:
                user_input = input(f"{prompt}: ").strip()
            
            value = value_type(user_input)
            
            if valid_range:
                min_val, max_val = valid_range
                if not (min_val <= value <= max_val):
                    print(f"[错误] 输入超出范围 ({min_val}-{max_val})，请重新输入")
                    continue
            
            return value
        except ValueError:
            print(f"[错误] 无效输入，请输入{value_type.__name__}类型的值")
        except KeyboardInterrupt:
            print("\n[INFO] 用户取消输入")
            return None


def execute_continuous_single_scan(scanner, start_phase, end_phase, channel):
    """执行连续单步扫描 - 通过发送多个单步命令实现全扫描"""
    ch_names = ['无', 'DOWN', 'UP', 'BOTH']
    
    samples = end_phase - start_phase + 1
    if channel == 0b11:
        expected_total = samples * 2
    else:
        expected_total = samples
    
    print(f"\n" + "="*70)
    print("连续单步扫描配置:")
    print(f"  模式: 连续单步 (逐个发送单步命令)")
    print(f"  扫描范围: {start_phase} 到 {end_phase}")
    print(f"  通道: {ch_names[channel]}")
    print(f"  总命令数: {samples} 条")
    print(f"  期望数据: {expected_total} 个")
    print("="*70)
    
    # 确认执行
    confirm = input("\n是否开始测试? (y/n) [y]: ").strip().lower()
    if confirm and confirm not in ['y', 'yes']:
        print("[INFO] 测试已取消")
        return False
    
    try:
        all_data = []
        print(f"\n[INFO] 开始连续单步扫描...")
        
        for phase in range(start_phase, end_phase + 1):
            # 显示进度
            if phase % 10 == 0 or phase == start_phase:
                print(f"\n[进度] 相位 {phase}/{end_phase}")
            
            # 发送单步命令
            if not scanner.start_scan(scan_mode=0, phase=phase, channel=channel):
                print(f"[ERROR] 相位 {phase} 命令发送失败")
                continue
            
            # 等待接收数据
            expected_count = 2 if channel == 0b11 else 1
            data = scanner.receive_data(expected_count=expected_count, timeout=5.0)
            
            if len(data) == 0:
                print(f"[WARN] 相位 {phase} 未收到数据")
                continue
            
            all_data.extend(data)
            
            # 短暂延迟避免命令太快
            time.sleep(0.05)
        
        print(f"\n[INFO] 扫描完成! 共收到 {len(all_data)}/{expected_total} 个数据")
        
        if len(all_data) == 0:
            print("[ERROR] 没有接收到任何数据")
            return False
        
        # 处理数据
        print(f"\n[INFO] 处理数据...")
        processor = TDCDataProcessor(all_data)
        processor.process()
        
        # 保存数据到tdc_results文件夹
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        ch_suffix = ch_names[channel].lower()
        data_filename = f"tdc_continuous_{ch_suffix}_{timestamp}.txt"
        data_file = processor.save_to_file(data_filename)
        
        # 绘制图表并保存到同一文件夹
        if PLOT_AVAILABLE and len(all_data) > 10:
            plot_filename = data_filename.replace('.txt', '.png')
            plot_file = os.path.join('tdc_results', plot_filename)
            processor.plot(save_file=plot_file)
        
        print("\n[INFO] 测试完成!")
        return True
        
    except Exception as e:
        print(f"\n[ERROR] 发生错误: {e}")
        import traceback
        traceback.print_exc()
        return False


def execute_scan(scanner, scan_mode, phase, channel):
    """执行扫描测试"""
    mode_names = {0: '单步测试', 1: '全扫描'}
    ch_names = ['无', 'DOWN', 'UP', 'BOTH']
    
    # 计算期望数据量
    if scan_mode == 0:  # 单步
        expected_data_count = 2 if channel == 0b11 else 1
    else:  # 全扫描
        samples = phase + 1
        if channel == 0b11:
            expected_data_count = samples * 2
        else:
            expected_data_count = samples
    
    print(f"\n" + "="*70)
    print("测试配置:")
    print(f"  模式: {mode_names[scan_mode]}")
    if scan_mode == 0:
        print(f"  测试相位: {phase}")
    else:
        print(f"  扫描范围: 0 到 {phase}")
    print(f"  通道: {ch_names[channel]}")
    print(f"  期望数据: {expected_data_count} 个")
    print("="*70)
    
    # 确认执行
    confirm = input("\n是否开始测试? (y/n) [y]: ").strip().lower()
    if confirm and confirm not in ['y', 'yes']:
        print("[INFO] 测试已取消")
        return False
    
    try:
        # 启动测试
        print(f"\n[1/3] 启动测试...")
        if not scanner.start_scan(scan_mode=scan_mode, phase=phase, channel=channel):
            print("[ERROR] 启动测试失败")
            return False
        
        # 接收数据
        print(f"\n[2/3] 接收数据...")
        data = scanner.receive_data(expected_count=expected_data_count, timeout=3.0)
        
        if len(data) == 0:
            print("[ERROR] 没有接收到数据")
            print("[提示] 检查:")
            print("  1. ILA 中 tdc_ready 是否为 1")
            print("  2. ILA 中 scan_running 是否为 1")
            print("  3. ILA 中 gig_eth_tx_fifo_wren 是否有脉冲")
            return False
        
        # 处理数据
        print(f"\n[3/3] 处理数据...")
        processor = TDCDataProcessor(data)
        processor.process()
        
        # 保存数据到tdc_results文件夹
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        mode_suffix = 'single' if scan_mode == 0 else 'scan'
        ch_suffix = ch_names[channel].lower()
        data_filename = f"tdc_{mode_suffix}_{ch_suffix}_{timestamp}.txt"
        data_file = processor.save_to_file(data_filename)
        
        # 绘制图表并保存到同一文件夹
        if PLOT_AVAILABLE and len(data) > 10:
            plot_filename = data_filename.replace('.txt', '.png')
            plot_file = os.path.join('tdc_results', plot_filename)
            processor.plot(save_file=plot_file)
        
        print("\n[INFO] 测试完成!")
        return True
        
    except Exception as e:
        print(f"\n[ERROR] 发生错误: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """主程序"""
    import sys
    
    print("="*70)
    print("TDC 扫描测试程序")
    print("="*70)
    
    # 创建扫描器
    scanner = TDCScanner(host='192.168.2.100', port=1024)
    
    # 连接到FPGA
    if not scanner.connect():
        print("[ERROR] 无法连接到FPGA")
        return 1
    
    try:
        # 主循环
        while True:
            show_menu()
            
            choice = get_user_input("请输入选项", default=1, value_type=int, valid_range=(0, 8))
            if choice is None:
                continue
            
            if choice == 0:
                print("\n[INFO] 退出程序")
                break
            
            elif choice == 1:
                # 全扫描 0-224, 双通道 (225步覆盖完整周期)
                execute_scan(scanner, scan_mode=1, phase=224, channel=0b11)
            
            elif choice == 2:
                # 全扫描，指定结束相位
                print("\n提示: 225步(0-224)可覆盖完整3864ps周期")
                phase = get_user_input("请输入结束相位 (0-255, 推荐224)", default=224, 
                                      value_type=int, valid_range=(0, 255))
                if phase is not None:
                    execute_scan(scanner, scan_mode=1, phase=phase, channel=0b11)
            
            elif choice == 3:
                # 单步测试
                phase = get_user_input("请输入测试相位 (0-255)", default=0, 
                                      value_type=int, valid_range=(0, 255))
                if phase is not None:
                    execute_scan(scanner, scan_mode=0, phase=phase, channel=0b11)
            
            elif choice == 4:
                # UP通道测试
                print("\n选择测试模式:")
                print("  1. 单步测试")
                print("  2. 全扫描")
                mode_choice = get_user_input("请选择", default=2, value_type=int, valid_range=(1, 2))
                if mode_choice is None:
                    continue
                
                if mode_choice == 1:
                    phase = get_user_input("请输入测试相位 (0-255)", default=0, 
                                          value_type=int, valid_range=(0, 255))
                    if phase is not None:
                        execute_scan(scanner, scan_mode=0, phase=phase, channel=0b10)
                else:
                    phase = get_user_input("请输入结束相位 (0-255, 推荐224)", default=224, 
                                          value_type=int, valid_range=(0, 255))
                    if phase is not None:
                        execute_scan(scanner, scan_mode=1, phase=phase, channel=0b10)
            
            elif choice == 5:
                # DOWN通道测试
                print("\n选择测试模式:")
                print("  1. 单步测试")
                print("  2. 全扫描")
                mode_choice = get_user_input("请选择", default=2, value_type=int, valid_range=(1, 2))
                if mode_choice is None:
                    continue
                
                if mode_choice == 1:
                    phase = get_user_input("请输入测试相位 (0-255)", default=0, 
                                          value_type=int, valid_range=(0, 255))
                    if phase is not None:
                        execute_scan(scanner, scan_mode=0, phase=phase, channel=0b01)
                else:
                    phase = get_user_input("请输入结束相位 (0-255, 推荐224)", default=224, 
                                          value_type=int, valid_range=(0, 255))
                    if phase is not None:
                        execute_scan(scanner, scan_mode=1, phase=phase, channel=0b01)
            
            elif choice == 6:
                # 连续单步扫描
                print("\n选择通道:")
                print("  1. UP 通道")
                print("  2. DOWN 通道")
                print("  3. 双通道 (BOTH)")
                ch_choice = get_user_input("请选择", default=3, value_type=int, valid_range=(1, 3))
                if ch_choice is None:
                    continue
                
                channel_map = {1: 0b10, 2: 0b01, 3: 0b11}
                channel = channel_map[ch_choice]
                
                print("\n提示: 225步(0-224)可覆盖完整3864ps周期")
                start_phase = get_user_input("请输入起始相位 (0-255)", default=0, 
                                            value_type=int, valid_range=(0, 255))
                if start_phase is None:
                    continue
                
                end_phase = get_user_input("请输入结束相位 (0-255, 推荐224)", default=224, 
                                          value_type=int, valid_range=(start_phase, 255))
                if end_phase is not None:
                    execute_continuous_single_scan(scanner, start_phase, end_phase, channel)
            
            elif choice == 7:
                # 校准
                print("\n[INFO] 启动 TDC 校准...")
                confirm = input("确认启动校准? (y/n) [y]: ").strip().lower()
                if not confirm or confirm in ['y', 'yes']:
                    if scanner.start_calibration():
                        print("[INFO] 校准命令已发送")
                    else:
                        print("[ERROR] 校准命令发送失败")
            
            elif choice == 8:
                # TDC性能分析
                print("\n[INFO] 请首先执行全扫描测试获取数据...")
                print("建议：选择选项1或选2进行0-255全扫描")
                print("此功能将分析最近一次测试的数据")
            
            # 询问是否继续
            print("\n" + "-"*70)
            continue_test = input("按 Enter 继续，输入 q 退出: ").strip().lower()
            if continue_test == 'q':
                print("\n[INFO] 退出程序")
                break
        
        return 0
        
    except KeyboardInterrupt:
        print("\n\n[INFO] 用户中断")
        return 130
    except Exception as e:
        print(f"\n[ERROR] 发生错误: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        scanner.disconnect()


if __name__ == "__main__":
    import sys
    sys.exit(main())
