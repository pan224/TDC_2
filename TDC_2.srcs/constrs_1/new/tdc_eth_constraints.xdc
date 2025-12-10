# ============================================================================
# TDC 以太网系统约束文件
# ============================================================================
# 适用于 Xilinx 7 系列 FPGA
# ============================================================================

# ============================================================================
# 管脚约束
# ============================================================================
#-------------------- ayatem pins ---------------
# --system reset active HIGH
set_property PACKAGE_PIN W19 [get_ports CPU_RESET]
set_property IOSTANDARD LVCMOS33 [get_ports CPU_RESET]
# PadFunction: IO_L12P_T1_MRCC_33
#set_property VCCAUX_IO DONTCARE [get_ports SYS_CLK_P]
#set_property IOSTANDARD DIFF_SSTL15 [get_ports SYS_CLK_P]
# 125MHz clock, for GTP/GTH/GTX
set_property PACKAGE_PIN U8 [get_ports SGMIICLK_Q0_P]
set_property PACKAGE_PIN U7 [get_ports SGMIICLK_Q0_N]

# Pins for GBE
set_property PACKAGE_PIN A27 [get_ports PHY_RESET_N]
set_property IOSTANDARD LVCMOS25 [get_ports PHY_RESET_N]
set_property PACKAGE_PIN A26 [get_ports MDIO]
set_property IOSTANDARD LVCMOS25 [get_ports MDIO]
set_property PACKAGE_PIN C26 [get_ports MDC]
set_property IOSTANDARD LVCMOS25 [get_ports MDC]

set_property PACKAGE_PIN G29 [get_ports {RGMII_RXD[3]}]
set_property PACKAGE_PIN E30 [get_ports {RGMII_RXD[2]}]
set_property PACKAGE_PIN E29 [get_ports {RGMII_RXD[1]}]
set_property PACKAGE_PIN G28 [get_ports {RGMII_RXD[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_RXD[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_RXD[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_RXD[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_RXD[0]}]
set_property PACKAGE_PIN C27 [get_ports {RGMII_TXD[3]}]
set_property PACKAGE_PIN A30 [get_ports {RGMII_TXD[2]}]
set_property PACKAGE_PIN B29 [get_ports {RGMII_TXD[1]}]
set_property PACKAGE_PIN C30 [get_ports {RGMII_TXD[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_TXD[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_TXD[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_TXD[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {RGMII_TXD[0]}]
set_property PACKAGE_PIN D29 [get_ports RGMII_TX_CTL]
set_property PACKAGE_PIN C25 [get_ports RGMII_TXC]
set_property IOSTANDARD LVCMOS25 [get_ports RGMII_TX_CTL]
set_property IOSTANDARD LVCMOS25 [get_ports RGMII_TXC]
set_property PACKAGE_PIN G30 [get_ports RGMII_RX_CTL]
set_property IOSTANDARD LVCMOS25 [get_ports RGMII_RX_CTL]
set_property PACKAGE_PIN D27 [get_ports RGMII_RXC]
set_property IOSTANDARD LVCMOS25 [get_ports RGMII_RXC]

# ============================================================================
# 时钟约束
# ============================================================================
# --system clk 200MHz
set_property PACKAGE_PIN AD12 [get_ports SYS_CLK_P]
set_property PACKAGE_PIN AD11 [get_ports SYS_CLK_N]
set_property IOSTANDARD DIFF_SSTL15 [get_ports SYS_CLK_P]
set_property IOSTANDARD DIFF_SSTL15 [get_ports SYS_CLK_N]


# 系统时钟 200MHz (差分输入)
create_clock -period 5.000 -name sys_clk_200 [get_ports SYS_CLK_P]

# 以太网 SGMII 时钟 125MHz（通过 GTE2 输入）
create_clock -period 8.000 -name sgmii_clk_125 [get_ports SGMIICLK_Q0_P]

# ============================================================================
# 生成的内部时钟 - global_clock_reset 模块
# ============================================================================
# 这些时钟由 global_clock_reset 内部的 clocking wizard 生成
# 需要与实际的时钟树路径匹配

# 200MHz 系统时钟（直通）
create_generated_clock -name sys_clk -source [get_ports SYS_CLK_P] -divide_by 1 [get_pins global_clock_reset_inst/clk_wiz_200M_inst/clk_out1]

# 50MHz 时钟
create_generated_clock -name clk_50MHz -source [get_ports SYS_CLK_P] -divide_by 4 [get_pins global_clock_reset_inst/clk_wiz_200M_inst/clk_out2]

# 100MHz 时钟
create_generated_clock -name clk_100MHz -source [get_ports SYS_CLK_P] -divide_by 2 [get_pins global_clock_reset_inst/clk_wiz_200M_inst/clk_out3]

# 10MHz 时钟
create_generated_clock -name clk_10MHz -source [get_ports SYS_CLK_P] -divide_by 20 [get_pins global_clock_reset_inst/clk_wiz_200M_inst/clk_out4]

# 250MHz 时钟
create_generated_clock -name clk_250MHz -source [get_ports SYS_CLK_P] -multiply_by 5 -divide_by 4 [get_pins global_clock_reset_inst/clk_wiz_200M_inst/clk_out5]

# ============================================================================
# TDC 时钟生成 - tdc_eth_integrated 模块内的 clk_wiz_tdc
# ============================================================================
# 260MHz TDC 主时钟（关键路径）
# ⚠️ 重要: 必须定义此约束,否则ready/lut_init信号会出现时序毛刺
create_generated_clock -name clk_260MHz -source [get_pins tdc_eth_system/clk_wiz_tdc_inst/clk_in1] -divide_by 10 -multiply_by 13 [get_pins tdc_eth_system/clk_wiz_tdc_inst/clk_out1]

# 260MHz 90度相位时钟（关键路径）
create_generated_clock -name clk_260MHz_p90 -source [get_pins tdc_eth_system/clk_wiz_tdc_inst/clk_in1] -divide_by 10 -multiply_by 13 [get_pins tdc_eth_system/clk_wiz_tdc_inst/clk_out2]

# 125MHz 以太网时钟（从 IBUFDS_GTE2 输出）
# 注释掉因为此时钟由IP核自动管理
# create_generated_clock -name clk_125MHz -source [get_ports SGMIICLK_Q0_P] -divide_by 1 [get_pins BUFG_inst/O]


# ============================================================================
# 异步时钟域约束
# ============================================================================

# 定义物理独立的时钟组（完全异步）
# sys_clk_200 和 sgmii_clk_125 来自不同的物理时钟源，是真正的异步时钟
set_clock_groups -asynchronous -group [get_clocks sys_clk_200] -group [get_clocks sgmii_clk_125]

# 其他派生时钟也是异步的
set_clock_groups -asynchronous -group [get_clocks clk_50MHz] -group [get_clocks clk_100MHz] -group [get_clocks clk_10MHz] -group [get_clocks clk_250MHz]

# ============================================================================
# 260MHz 相位时钟与主时钟之间的路径约束
# ============================================================================
# clk_out1_clk_260_phase（由 clk_260_phase MMCM 生成）和 clk_out1_clk_wiz_tdc 
# 有级联关系，但它们在功能上是同步的，某些跨域路径是可接受的

# channel valid 信号到 timestamp_capture 的路径 - 这是同步逻辑路径
# 由于两个时钟来自同一源（clk_wiz_tdc），它们是相位对齐的
# 使用 set_max_delay 而不是 false_path 来允许一定的时序松弛
set_max_delay -from [get_pins -hierarchical -filter {NAME =~ *channel_up_inst/valid_reg/C}] -to [get_pins -hierarchical -filter {NAME =~ *timestamp_capture_inst/up_event_id_cnt_reg*/R}] 5.0 -datapath_only
set_max_delay -from [get_pins -hierarchical -filter {NAME =~ *channel_down_inst/valid_reg/C}] -to [get_pins -hierarchical -filter {NAME =~ *timestamp_capture_inst/down_event_id_cnt_reg*/R}] 5.0 -datapath_only

# ============================================================================
# 多周期路径约束 - 针对 TDC 关键路径
# ============================================================================
# 260MHz 时钟周期 = 3.85ns，放宽到 3 周期 = 11.55ns

# pulse_gen 状态机到 scan_ctrl 状态机的路径
# 这些控制信号不需要在单周期内稳定，允许 2 周期传播
set_multicycle_path -setup 2 -from [get_pins -hierarchical -filter {NAME =~ *pulse_gen_up/FSM_sequential_state_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *scan_ctrl_inst/FSM_sequential_state_reg*/CE}]
set_multicycle_path -hold 1 -from [get_pins -hierarchical -filter {NAME =~ *pulse_gen_up/FSM_sequential_state_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *scan_ctrl_inst/FSM_sequential_state_reg*/CE}]

set_multicycle_path -setup 2 -from [get_pins -hierarchical -filter {NAME =~ *pulse_gen_down/FSM_sequential_state_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *scan_ctrl_inst/FSM_sequential_state_reg*/CE}]
set_multicycle_path -hold 1 -from [get_pins -hierarchical -filter {NAME =~ *pulse_gen_down/FSM_sequential_state_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *scan_ctrl_inst/FSM_sequential_state_reg*/CE}]

# reset_sync 到 timestamp_capture 的复位路径 - 允许 2 周期
set_multicycle_path -setup 2 -from [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_260_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *timestamp_capture_inst/*_event_id_cnt_reg*/R}]
set_multicycle_path -hold 1 -from [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_260_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *timestamp_capture_inst/*_event_id_cnt_reg*/R}]

# # BRAM 读取路径（LUT 查找）- 允许 2 周期
# # 从 BRAM 输出到下一级寄存器
# set _xlnx_shared_i0 [get_pins -hierarchical -filter {NAME =~ *lut_inst/*_reg[*]/D}]
# set_multicycle_path -setup -from [get_pins -hierarchical -filter {NAME =~ *lut_inst/hist_bram*/CLKARDCLK}] -to $_xlnx_shared_i0 2
# set_multicycle_path -hold -from [get_pins -hierarchical -filter {NAME =~ *lut_inst/hist_bram*/CLKARDCLK}] -to $_xlnx_shared_i0 1

# # 延迟线同步路径 - dl_sync 模块的采样触发器
# # 这些是捕获亚稳态的触发器，允许较长的建立时间
# set_multicycle_path -setup 2 -to [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/*/sample_ff/D}]
# set_multicycle_path -hold 1 -to [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/*/sample_ff/D}]

# # 延迟线采样到优先级编码器路径 - 允许 2 周期
# # 这是 TDC 的核心测量路径，可以使用流水线延迟
# set _xlnx_shared_i1 [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/dl_*/gen_sample_ffs[*].gen_sample_real.sample_ff/C}]
# set_multicycle_path -setup -from $_xlnx_shared_i1 -to [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/pe_*/cpos_reg[*]/D}] 2
# set_multicycle_path -hold -from $_xlnx_shared_i1 -to [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/pe_*/cpos_reg[*]/D}] 1

# # 优先级编码器内部路径 - 允许 2 周期
# set_multicycle_path -setup -from [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/pe_*/gen_sync_*.bin_reg[*]/C}] -to [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/bin_internal_reg[*]/D}] 2
# set_multicycle_path -hold -from [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/pe_*/gen_sync_*.bin_reg[*]/C}] -to [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/bin_internal_reg[*]/D}] 1

# # 优先级编码器输出路径 - 允许 2 周期
# set_multicycle_path -setup -from [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/pe_*/bin_out_reg[*]/C}] 2
# set_multicycle_path -hold -from [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/pe_*/bin_out_reg[*]/C}] 1

# # bin_internal 到其他寄存器的路径
# set_multicycle_path -setup -from [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/bin_internal_reg[*]/C}] 2
# set_multicycle_path -hold -from [get_pins -hierarchical -filter {NAME =~ *dl_sync_inst/bin_internal_reg[*]/C}] 1


# ============================================================================
# 时序例外（False Path）
# ============================================================================

# 复位信号的异步路径
set_false_path -from [get_ports CPU_RESET]

# 跨时钟域的同步寄存器（CDC 双触发器）
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *sync_reg[0]/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *sync1_reg/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *sync2_reg/D}]

# 校准使能控制信号（静态或慢速变化）
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *calib_sel_reg/C}] -to [get_pins -hierarchical -filter {NAME =~ *BUFGCTRL*/CE*}]

# ============================================================================
# 以太网 MAC 复位路径约束
# ============================================================================

# gig_eth 内部复位同步链 - 这些是异步复位路径
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *gig_eth_inst/*/reset_sync*/C}] -to [get_pins -hierarchical -filter {NAME =~ *gig_eth_inst/*/reset_sync*/PRE}]

# IDELAYCTRL 复位路径
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *gig_eth_inst/*glbl_reset_gen/reset_sync*/C}] -to [get_pins -hierarchical -filter {NAME =~ *gig_eth_inst/*idelayctrl_reset_gen/reset_sync*/PRE}]

# 以太网 MAC 内部异步复位
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *gig_eth_inst/*/PRE}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *gig_eth_inst/*/CLR}]

# ============================================================================
# 跨时钟域路径 - CDC 同步
# ============================================================================

# TDC ready 信号：260MHz → 200MHz（通过 CDC 同步器）
# channel ready 到 eth_comm manual_calib_trigger 路径
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *channel_*/ready_reg/C}] -to [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/manual_calib_trigger_reg/D}]

# 扫描控制参数：200MHz → 200MHz（同时钟域，但通过寄存器锁存）
# set_false_path -from [get_pins -hierarchical -filter {NAME =~ *scan_ctrl_inst/scan_param_latch_reg[*]/C}] #     -to [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/*}]

# 扫描状态反馈：200MHz → 200MHz（同时钟域）
# set_false_path -from [get_pins -hierarchical -filter {NAME =~ *scan_ctrl_inst/scan_status_reg[*]/C}] #     -to [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/*}]

# 手动校准触发：200MHz → 260MHz（已通过 CDC 同步）
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/*calib*}] -to [get_pins -hierarchical -filter {NAME =~ *calib_trigger_sync*/D}]

# ============================================================================
# 异步 FIFO 复位路径约束（关键！）
# ============================================================================
# FIFO36E1 的 RST 是异步复位，不需要满足 Recovery/Removal 时序要求
# 这些是从 reset_sync_260_reg 到 FIFO RST 的路径

# UP 方向异步 FIFO（260MHz 写入，200MHz 读取）
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/up_async_fifo/*/RST}]

# DOWN 方向异步 FIFO（200MHz 写入，260MHz 读取）
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/down_async_fifo/*/RST}]

# 通用匹配：所有到 FIFO36E1 RST 引脚的路径
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *fifo_36_72*/RST}]

# CDC 同步模块中的异步清除信号
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *cdc_sync_inst/*/CLR}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *cdc_sync_inst/*/PRE}]

# Reset sync 模块到所有异步复位目标的路径
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_260_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ */RST}]
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_260_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ */CLR}]
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_200_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ */RST}]
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_200_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ */CLR}]

# ============================================================================
# 跨时钟域 CDC 同步器路径约束（关键！）
# ============================================================================
# CDC 同步器的第一级寄存器输入是跨时钟域信号，不需要满足严格的时序要求
# 这些路径通过双触发器同步器来处理亚稳态

# sys_clk_200 到 clk_260MHz 域的 CDC 同步器输入
# scan_param 信号从 eth_comm (200MHz) 传输到 cdc_sync (260MHz)
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/scan_cmd_param_reg*/C}] -to [get_pins -hierarchical -filter {NAME =~ *cdc_sync_inst/scan_param_sync1_reg*/D}]

# manual_calib 信号的 CDC 路径
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *eth_comm_inst/manual_calib_trigger_reg/C}] -to [get_pins -hierarchical -filter {NAME =~ *cdc_sync_inst/manual_calib_sync1_reg/D}]

# Global reset 信号到 260MHz 时钟域的异步路径
set_false_path -from [get_pins -hierarchical -filter {NAME =~ *globalresetter_inst/GLOBAL_RST_reg/C}] -to [get_pins -hierarchical -filter {NAME =~ *reset_sync_inst/reset_sync_260_reg*/PRE}]

# ============================================================================
# 输入输出延迟约束
# ============================================================================

# RGMII 接口时序（相对于125MHz以太网时钟，但FIFO工作在200MHz）
# 输入延迟相对于 RGMII_RXC
# set_input_delay -clock [get_clocks sgmii_clk_125] -max 1.500 [get_ports RGMII_RXD*]
# set_input_delay -clock [get_clocks sgmii_clk_125] -min 0.500 [get_ports RGMII_RXD*]
# set_input_delay -clock [get_clocks sgmii_clk_125] -max 1.500 [get_ports RGMII_RX_CTL]
# set_input_delay -clock [get_clocks sgmii_clk_125] -min 0.500 [get_ports RGMII_RX_CTL]

# # 输出延迟相对于 RGMII_TXC
# set_output_delay -clock [get_clocks sgmii_clk_125] -max 1.000 [get_ports RGMII_TXD*]
# set_output_delay -clock [get_clocks sgmii_clk_125] -min -0.500 [get_ports RGMII_TXD*]
# set_output_delay -clock [get_clocks sgmii_clk_125] -max 1.000 [get_ports RGMII_TX_CTL]
# set_output_delay -clock [get_clocks sgmii_clk_125] -min -0.500 [get_ports RGMII_TX_CTL]

# ============================================================================
# 物理约束 - 优化布局布线
# ============================================================================

# 环形振荡器需要允许组合环路
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical -filter {NAME =~ *ro_clk*}]
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical -filter {NAME =~ *ro_inst*}]

# ============================================================================
# TDC Sensor信号路径延迟平衡约束 - 关键！
# ============================================================================
# 目标：确保从BUFGCTRL多路复用器输出到4个delay_line的sensor_ff输入的路径延迟
# 尽可能相等，减少由于布线延迟差异导致的测量盲区

# UP通道：从 up_mux_inst (BUFGCTRL) 到 4个delay_line的sensor_ff
# 设置最大延迟为1.8ns（根据当前布线延迟 ~1.8ns），强制布线器平衡路径
set_max_delay -from [get_pins tdc_eth_system/up_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_up_inst/dl_sync_inst/dl_0/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

set_max_delay -from [get_pins tdc_eth_system/up_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_up_inst/dl_sync_inst/dl_90/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

set_max_delay -from [get_pins tdc_eth_system/up_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_up_inst/dl_sync_inst/dl_180/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

set_max_delay -from [get_pins tdc_eth_system/up_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_up_inst/dl_sync_inst/dl_270/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

# DOWN通道：从 down_mux_inst (BUFGCTRL) 到 4个delay_line的sensor_ff
set_max_delay -from [get_pins tdc_eth_system/down_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_down_inst/dl_sync_inst/dl_0/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

set_max_delay -from [get_pins tdc_eth_system/down_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_down_inst/dl_sync_inst/dl_90/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

set_max_delay -from [get_pins tdc_eth_system/down_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_down_inst/dl_sync_inst/dl_180/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

set_max_delay -from [get_pins tdc_eth_system/down_mux_inst/O] \
              -to [get_pins tdc_eth_system/channel_down_inst/dl_sync_inst/dl_270/gen_sensor_ff_real.sensor_ff/C] \
              1.800 -datapath_only

# 可选：如果使用了BUFG平衡树，则约束从最终BUFG到sensor_ff的路径
# 注释：下面的约束仅在dl_sync.v中添加了BUFG缓冲树后才生效
# set_max_delay -from [get_pins {tdc_eth_system/channel_up_inst/dl_sync_inst/sensor_buf_final_*/O}] \
#               -to [get_pins {tdc_eth_system/channel_up_inst/dl_sync_inst/dl_*/gen_sensor_ff_real.sensor_ff/C}] \
#               0.500 -datapath_only
# 
# set_max_delay -from [get_pins {tdc_eth_system/channel_down_inst/dl_sync_inst/sensor_buf_final_*/O}] \
#               -to [get_pins {tdc_eth_system/channel_down_inst/dl_sync_inst/dl_*/gen_sensor_ff_real.sensor_ff/C}] \
#               0.500 -datapath_only

# TDC 关键模块放置在相同区域以减少布线延迟
# DOWN通道
set_property LOC SLICE_X0Y0 [get_cells tdc_eth_system/channel_down_inst/dl_sync_inst/dl_0/gen_carry0_real.carry4_0]
set_property LOC SLICE_X10Y0 [get_cells tdc_eth_system/channel_down_inst/dl_sync_inst/dl_90/gen_carry0_real.carry4_0]
set_property LOC SLICE_X20Y0 [get_cells tdc_eth_system/channel_down_inst/dl_sync_inst/dl_180/gen_carry0_real.carry4_0]
set_property LOC SLICE_X30Y0 [get_cells tdc_eth_system/channel_down_inst/dl_sync_inst/dl_270/gen_carry0_real.carry4_0]
# UP通道
set_property LOC SLICE_X40Y0 [get_cells tdc_eth_system/channel_up_inst/dl_sync_inst/dl_0/gen_carry0_real.carry4_0]
set_property LOC SLICE_X50Y0 [get_cells tdc_eth_system/channel_up_inst/dl_sync_inst/dl_90/gen_carry0_real.carry4_0]
set_property LOC SLICE_X60Y0 [get_cells tdc_eth_system/channel_up_inst/dl_sync_inst/dl_180/gen_carry0_real.carry4_0]
set_property LOC SLICE_X70Y0 [get_cells tdc_eth_system/channel_up_inst/dl_sync_inst/dl_270/gen_carry0_real.carry4_0]


# set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
# set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
# connect_debug_port dbg_hub/clk [get_nets sys_clk]

// ============================================================================
# DRC 约束放宽
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
set_property SEVERITY {Warning} [get_drc_checks LCCH-1]


// ============================================================================
