// ============================================================================
// TDC 以太网集成系统
// ============================================================================
// 整合新TDC测量核心与以太网通信功能
// 测量 UP 和 DOWN 信号在 RESET 后的绝对时间
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"


module tdc_eth_integrated (
    // ========================================================================
    // 系统时钟和复位
    // ========================================================================
    input  wire         sys_clk_200MHz,     // 系统时钟 200MHz
    input  wire         sys_reset,          // 系统复位
    
    // ========================================================================
    // TDC 测量信号
    // ========================================================================
    input  wire         signal_up,          // UP 信号
    input  wire         signal_down,        // DOWN 信号
    input  wire         tdc_reset_trigger,  // TDC 复位触发（时间基准）
    
    // 扫描测试使能（高电平启用扫描测试模式）
    input  wire         scan_test_en,       // 扫描测试使能
    
    // ========================================================================
    // 以太网 FIFO 接口 (200MHz 时钟域)
    // ========================================================================
    // TX FIFO
    output wire         gig_eth_tx_fifo_wrclk,
    input  wire         gig_eth_tx_fifo_full,
    output wire [31:0]  gig_eth_tx_fifo_q,
    output wire         gig_eth_tx_fifo_wren,
    
    // RX FIFO
    output wire         gig_eth_rx_fifo_rdclk,
    input  wire         gig_eth_rx_fifo_empty,
    input  wire [31:0]  gig_eth_rx_fifo_q,
    output wire         gig_eth_rx_fifo_rden,

    // ========================================================================
    // 调试输出
    // ========================================================================
    output wire         tdc_ready_out       // TDC就绪状态输出
);

    // ========================================================================
    // 参数定义
    // ========================================================================
    // 260MHz 时钟周期 = 3846ps (~3.85ns)
    localparam CLK_PERIOD_PS = `CLK_IN_PS;
    
    // 粗计数位宽调整为适应以太网（16位粗计数 + 13位精细 = 29位，适合32位传输）
    localparam COARSE_BITS = 16;        // 粗计数 16位（0-65535 周期 = 0-252us @ 260MHz）
    
    // ========================================================================
    // 时钟生成模块
    // ========================================================================
    wire        clk_260MHz;             // TDC 工作时钟 260MHz
    wire        clk_260MHz_p0;          // TDC 0度相位时钟
    wire        clk_260MHz_p90;         // TDC 90度相位时钟
    wire        clk_260MHz_p180;        // TDC 180度相位时钟
    wire        clk_260MHz_p270;        // TDC 270度相位时钟
    
    tdc_clock_manager clock_mgr_inst (
        .sys_clk_200MHz(sys_clk_200MHz),
        .clk_260MHz(clk_260MHz),
        .clk_260MHz_p0(clk_260MHz_p0),
        .clk_260MHz_p90(clk_260MHz_p90),
        .clk_260MHz_p180(clk_260MHz_p180),
        .clk_260MHz_p270(clk_260MHz_p270)
    );
    
    // ========================================================================
    // 复位同步模块
    // ========================================================================
    wire        rst_260MHz;
    wire        rst_200MHz;
    
    tdc_reset_sync reset_sync_inst (
        .sys_reset(sys_reset),
        .clk_260MHz(clk_260MHz),
        .clk_200MHz(sys_clk_200MHz),
        .rst_260MHz(rst_260MHz),
        .rst_200MHz(rst_200MHz)
    );
    
    // ========================================================================
    // TDC 通道实例化
    // ========================================================================
    // 通道1 (UP信号)
    wire        ch1_ready, ch1_valid;
    wire [12:0] ch1_time_fine;

    // 通道2 (DOWN信号)
    wire        ch2_ready, ch2_valid;
    wire [12:0] ch2_time_fine;

    // 就绪信号
    wire tdc_ready = ch1_ready & ch2_ready;
    
    // ========================================================================
    // 跨时钟域同步模块
    // ========================================================================
    wire        manual_calib_trigger_200;   // 200MHz 域校准触发
    wire        manual_calib_trigger_260;   // 260MHz 域校准触发
    wire        scan_cmd_trigger_200;       // 200MHz 域扫描命令
    wire        scan_cmd_trigger_260;       // 260MHz 域扫描命令
    wire [10:0] scan_cmd_param_200;         // 200MHz 域扫描参数
    wire [10:0] scan_cmd_param_260;         // 260MHz 域扫描参数
    
    tdc_cdc_sync cdc_sync_inst (
        .clk_260MHz(clk_260MHz),
        .clk_200MHz(sys_clk_200MHz),
        .rst_260MHz(rst_260MHz),
        .rst_200MHz(rst_200MHz),
        .manual_calib_trigger_200(manual_calib_trigger_200),
        .scan_cmd_trigger_200(scan_cmd_trigger_200),
        .scan_cmd_param_200(scan_cmd_param_200),
        .manual_calib_trigger_260(manual_calib_trigger_260),
        .scan_cmd_trigger_260(scan_cmd_trigger_260),
        .scan_cmd_param_260(scan_cmd_param_260)
    );
    
    // ========================================================================
    // 校准控制模块
    // ========================================================================
    wire        calib_sel;
    wire        ro_clk;
    
    tdc_calib_ctrl calib_ctrl_inst (
        .clk_260MHz(clk_260MHz),
        .rst_260MHz(rst_260MHz),
        .sys_reset(sys_reset),
        .tdc_ready(tdc_ready),
        .manual_calib_trigger(manual_calib_trigger_260),
        .calib_sel(calib_sel),
        .ro_clk(ro_clk)
    );
    
    // ========================================================================
    // 扫描测试控制模块
    // ========================================================================
    wire        scan_running;
    wire [7:0]  scan_status;
    wire        test_pulse_up;
    wire        test_pulse_down;
    wire        tdc_reset_scan;

    tdc_scan_ctrl scan_ctrl_inst (
        .clk_260MHz(clk_260MHz),
        .sys_reset(rst_260MHz),
        .scan_cmd_trigger(scan_cmd_trigger_260),
        .scan_cmd_param(scan_cmd_param_260),
        .scan_running(scan_running),
        .scan_status(scan_status),
        .test_pulse_up(test_pulse_up),
        .test_pulse_down(test_pulse_down),
        .tdc_reset_trigger(tdc_reset_scan)
    );
    
    // ========================================================================
    // 信号多路复用模块
    // ========================================================================
    wire signal_up_mux;
    wire signal_down_mux;
    wire tdc_reset_mux;
    
    tdc_signal_mux signal_mux_inst (
        .signal_up(signal_up),
        .signal_down(signal_down),
        .tdc_reset_trigger(tdc_reset_trigger),
        .scan_test_en(scan_test_en),
        .test_pulse_up(test_pulse_up),
        .test_pulse_down(test_pulse_down),
        .tdc_reset_scan(tdc_reset_scan),
        .calib_sel(calib_sel),
        .ro_clk(ro_clk),
        .signal_up_mux(signal_up_mux),
        .signal_down_mux(signal_down_mux),
        .tdc_reset_mux(tdc_reset_mux)
    );
    
    // ========================================================================
    // 时间戳捕获模块
    // ========================================================================
    wire                    up_valid;
    wire [12:0]             up_fine;
    wire [COARSE_BITS-1:0]  up_coarse;
    wire [7:0]              up_id;
    wire                    down_valid;
    wire [12:0]             down_fine;
    wire [COARSE_BITS-1:0]  down_coarse;
    wire [7:0]              down_id;
    wire [7:0]              measurement_id;
    
    tdc_timestamp_capture #(
        .COARSE_BITS(COARSE_BITS)
    ) timestamp_capture_inst (
        .clk_260MHz(clk_260MHz),
        .rst_260MHz(rst_260MHz),
        .ch1_valid(ch1_valid),
        .ch1_time_fine(ch1_time_fine),
        .ch2_valid(ch2_valid),
        .ch2_time_fine(ch2_time_fine),
        .tdc_reset_trigger(tdc_reset_mux),
        .up_valid(up_valid),
        .up_fine(up_fine),
        .up_coarse(up_coarse),
        .up_id(up_id),
        .down_valid(down_valid),
        .down_fine(down_fine),
        .down_coarse(down_coarse),
        .down_id(down_id),
        .measurement_id(measurement_id)
    );
    
    // ========================================================================
    // TDC 通道1实例化 (UP 信号测量)
    // ========================================================================
    channel #(
        .CH("ch_up")
    ) channel_up_inst (
        .CLK_P0(clk_260MHz_p0),
        .CLK_P90(clk_260MHz_p90),
        .CLK_P180(clk_260MHz_p180),
        .CLK_P270(clk_260MHz_p270),
        .RST(rst_260MHz),
        .clk_period(CLK_PERIOD_PS),
        .sensor(signal_up_mux),
        .calib_en(calib_sel),
        .ready(ch1_ready),
        .valid(ch1_valid),
        .time_out(ch1_time_fine)
    );
    
    // ========================================================================
    // TDC 通道2实例化 (DOWN 信号测量)
    // ========================================================================
    channel #(
        .CH("ch_down")
    ) channel_down_inst (
        .CLK_P0(clk_260MHz_p0),
        .CLK_P90(clk_260MHz_p90),
        .CLK_P180(clk_260MHz_p180),
        .CLK_P270(clk_260MHz_p270),
        .RST(rst_260MHz),
        .clk_period(CLK_PERIOD_PS),
        .sensor(signal_down_mux),
        .calib_en(calib_sel),
        .ready(ch2_ready),
        .valid(ch2_valid),
        .time_out(ch2_time_fine)
    );
    
    // ========================================================================
    // 以太网通信控制模块 (双通道版)
    // ========================================================================
    eth_comm_ctrl_tdc #(
        .FINE_BITS(13),
        .COARSE_BITS(COARSE_BITS)
    ) eth_comm_inst (
        .clk_200MHz(sys_clk_200MHz),
        .clk_260MHz(clk_260MHz),
        .rst_200MHz(rst_200MHz),
        .rst_260MHz(rst_260MHz),
        .up_valid(up_valid),
        .up_fine(up_fine),
        .up_coarse(up_coarse),
        .up_id(up_id),
        .down_valid(down_valid),
        .down_fine(down_fine),
        .down_coarse(down_coarse),
        .down_id(down_id),
        .gig_eth_tx_fifo_wrclk(gig_eth_tx_fifo_wrclk),
        .gig_eth_tx_fifo_full(gig_eth_tx_fifo_full),
        .gig_eth_tx_fifo_q(gig_eth_tx_fifo_q),
        .gig_eth_tx_fifo_wren(gig_eth_tx_fifo_wren),
        .gig_eth_rx_fifo_rdclk(gig_eth_rx_fifo_rdclk),
        .gig_eth_rx_fifo_empty(gig_eth_rx_fifo_empty),
        .gig_eth_rx_fifo_q(gig_eth_rx_fifo_q),
        .gig_eth_rx_fifo_rden(gig_eth_rx_fifo_rden),
        .system_ready(tdc_ready),
        .manual_calib_trigger(manual_calib_trigger_200),
        .scan_cmd_trigger(scan_cmd_trigger_200),
        .scan_cmd_param(scan_cmd_param_200)
    );
    
    // ========================================================================
    // 调试输出
    // ========================================================================
    assign tdc_ready_out = tdc_ready;


    // ila_0 ila_eth_debug (
    // .clk(sys_clk_200MHz),
    // .probe0({
    //     gig_eth_rx_fifo_q,          // [31:0]
    //     gig_eth_tx_fifo_q,          // [31:0]
    //     gig_eth_tx_fifo_full,       // [0]
    //     gig_eth_rx_fifo_empty,      // [0]
    //     gig_eth_rx_fifo_rden,       // [0]
    //     gig_eth_tx_fifo_wren,       // [0]
    //     tdc_ready_out               // [0]
    //     })
    // );

    // ila_1 ila_tdc_debug (
    // .clk(clk_260MHz),   
    // .probe0({   
    //     ch1_time_fine,              // 13位 - UP通道精细时间
    //     ch2_time_fine,              // 13位 - DOWN通道精细时间
    //     ch1_valid,                  // 1位  - UP通道有效信号
    //     ch2_valid,                  // 1位  - DOWN通道有效信号
    //     ch1_ready,                  // 1位  - UP通道就绪标志
    //     ch2_ready,                  // 1位  - DOWN通道就绪标志
    //     ch1_lut_init,               // 1位  - UP通道LUT初始化状态 ⚠️关键
    //     ch2_lut_init,               // 1位  - DOWN通道LUT初始化状态 ⚠️关键
    //     ch1_dl_valid,               // 1位  - UP通道延迟线有效
    //     ch2_dl_valid,               // 1位  - DOWN通道延迟线有效
    //     ch1_valid_pipe,             // 4位  - UP通道流水线状态
    //     ch2_valid_pipe,             // 4位  - DOWN通道流水线状态
    //     calib_sel,                  // 1位  - 校准选择信号
    //     up_event_id,                // 8位  - UP事件ID计数器
    //     down_event_id,              // 8位  - DOWN事件ID计数器
    //     signal_up_mux,              // 1位  - 多路复用后的UP信号
    //     signal_down_mux             // 1位  - 多路复用后的DOWN信号
    //     })             
    // );

    // ila_2  ila_scan_cmd_debug (
    //     .clk(clk_260MHz),
    //     .probe0({
    //         scan_cmd_param_260,
    //         scan_cmd_trigger_260
    //     })
    // );


endmodule
