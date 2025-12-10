// ============================================================================
// TDC 信号多路复用模块
// ============================================================================
// 管理测量信号的多路复用:
// 1. 正常模式: 外部信号 (signal_up/signal_down)
// 2. 扫描测试模式: 内部测试脉冲
// 3. 校准模式: 环形振荡器
// ============================================================================

`timescale 1ns / 1ps

module tdc_signal_mux (
    // 输入信号
    input  wire         signal_up,          // 外部 UP 信号
    input  wire         signal_down,        // 外部 DOWN 信号
    input  wire         tdc_reset_trigger,  // 外部 TDC 复位触发
    
    // 扫描测试信号
    input  wire         scan_test_en,       // 扫描测试使能
    input  wire         test_pulse_up,      // 扫描测试 UP 脉冲
    input  wire         test_pulse_down,    // 扫描测试 DOWN 脉冲
    input  wire         tdc_reset_scan,     // 扫描测试复位
    
    // 校准信号
    input  wire         calib_sel,          // 校准选择
    input  wire         ro_clk,             // 环形振荡器时钟
    
    // 输出信号
    output wire         signal_up_mux,      // 多路复用后的 UP 信号
    output wire         signal_down_mux,    // 多路复用后的 DOWN 信号
    output wire         tdc_reset_mux       // 多路复用后的复位信号
);

    // ========================================================================
    // 第一级: 外部信号 vs 扫描测试信号
    // ========================================================================
    wire signal_up_selected;
    wire signal_down_selected;
    wire tdc_reset_selected;
    
    assign signal_up_selected   = scan_test_en ? test_pulse_up   : signal_up;
    assign signal_down_selected = scan_test_en ? test_pulse_down : signal_down;
    assign tdc_reset_selected   = scan_test_en ? tdc_reset_scan  : tdc_reset_trigger;
    
    // ========================================================================
    // 第二级: 测量信号 vs 校准信号 (使用 BUFGCTRL)
    // ========================================================================
    // UP 信号多路复用
    BUFGCTRL up_mux_inst (
        .O(signal_up_mux),
        .CE0(~calib_sel),               // 正常测量/扫描测试模式
        .CE1(calib_sel),                // 校准模式
        .I0(signal_up_selected),        // 外部UP信号 或 扫描测试脉冲
        .I1(ro_clk),                    // 环形振荡器
        .IGNORE0(1'b1),
        .IGNORE1(1'b1),
        .S0(1'b1),
        .S1(1'b1)
    );
    
    // DOWN 信号多路复用
    BUFGCTRL down_mux_inst (
        .O(signal_down_mux),
        .CE0(~calib_sel),
        .CE1(calib_sel),
        .I0(signal_down_selected),      // 外部DOWN信号 或 扫描测试脉冲
        .I1(ro_clk),                    // 环形振荡器
        .IGNORE0(1'b1),
        .IGNORE1(1'b1),
        .S0(1'b1),
        .S1(1'b1)
    );
    
    // ========================================================================
    // TDC RESET 信号直通 (不需要校准切换)
    // ========================================================================
    assign tdc_reset_mux = tdc_reset_selected;

endmodule
