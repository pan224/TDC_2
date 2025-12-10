// ============================================================================
// Delay Line Synchronization Module
// ============================================================================
// 管理四相位延迟线采样并选择最优结果
// 从VHDL dl_sync. vhd转换而来
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"

module dl_sync #(
    parameter CH = "ch1"                // 通道标识
)(
    input  wire                     CLK_P0,
    input  wire                     CLK_P90,
    input  wire                     CLK_P180,
    input  wire                     CLK_P270,
    input  wire                     RST,
    // 输入接口
    input  wire                     sensor,
    input  wire                     calib_en,
    // 输出接口
    output reg  [`PE_INTBITS-1:0]  bin,
    output reg                      valid,
    output reg                      calib_flag
);

    // ========================================================================
    // 内部信号声明
    // ========================================================================
    // 延迟线输出
    wire [`BINS_WIDTH-1:0] bins_0, bins_90, bins_180, bins_270;
    
    // 优先编码器输出
    wire [`PE_INTBITS-1:0] pe_bin_0, pe_bin_90, pe_bin_180, pe_bin_270;
    wire                    pe_valid_0, pe_valid_90, pe_valid_180, pe_valid_270;
    
    // 内部寄存器
    reg [`PE_INTBITS-1:0]  bin_internal;
    reg [`PE_INTBITS-1:0]  bin270_prev;
    reg                     valid_internal;
    reg                     calib_en_reg;
    
    // 死区时间计数器 - 用于处理校准使能信号的同步
    reg [3:0]               deadtime_cnt;
    
    // ========================================================================
    // 初始化块 - 确保信号在仿真和综合中都有正确的初值
    // ========================================================================
    initial begin
        bin_internal = {`PE_INTBITS{1'b0}};
        bin270_prev = {`PE_INTBITS{1'b1}};  // 初始化为全1，防止第一次比较时出现误触发
        valid_internal = 1'b0;
        calib_en_reg = 1'b0;
        deadtime_cnt = 4'b0;
    end

    // ========================================================================
    // 延迟线实例化 - 四个相位
    // ========================================================================
    
    // Phase 0 度
    delay_line #(
        .PHASE("0"),
        .CH(CH)
    ) dl_0 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .sensor(sensor),
        .bins(bins_0)
    );
    
    // Phase 90 度
    delay_line #(
        .PHASE("90"),
        .CH(CH)
    ) dl_90 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .sensor(sensor),
        .bins(bins_90)
    );
    
    // Phase 180 度
    delay_line #(
        . PHASE("180"),
        .CH(CH)
    ) dl_180 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .sensor(sensor),
        .bins(bins_180)
    );
    
    // Phase 270 度
    delay_line #(
        .PHASE("270"),
        .CH(CH)
    ) dl_270 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .sensor(sensor),
        . bins(bins_270)
    );

    // ========================================================================
    // 优先编码器实例化 - 四个相位
    // ========================================================================
    
    // Phase 0 度
    priority_encoder #(
        . PHASE("0")
    ) pe_0 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .RST(RST),
        . bins(bins_0),
        .bin(pe_bin_0),
        .valid(pe_valid_0)
    );
    
    // Phase 90 度
    priority_encoder #(
        . PHASE("90")
    ) pe_90 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .RST(RST),
        . bins(bins_90),
        .bin(pe_bin_90),
        .valid(pe_valid_90)
    );
    
    // Phase 180 度
    priority_encoder #(
        .PHASE("180")
    ) pe_180 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .RST(RST),
        .bins(bins_180),
        .bin(pe_bin_180),
        . valid(pe_valid_180)
    );
    
    // Phase 270 度
    priority_encoder #(
        . PHASE("270")
    ) pe_270 (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .RST(RST),
        . bins(bins_270),
        .bin(pe_bin_270),
        .valid(pe_valid_270)
    );

    // ========================================================================
    // 主控制逻辑
    // ========================================================================
    always @(posedge CLK_P0) begin
    if (RST) begin
        bin_internal    <= {`PE_INTBITS{1'b0}};
        bin270_prev     <= {`PE_INTBITS{1'b1}};
        valid_internal  <= 1'b0;
        calib_en_reg    <= 1'b0;
        deadtime_cnt    <= 4'b0;
        bin             <= {`PE_INTBITS{1'b0}};
        valid           <= 1'b0;
        calib_flag      <= 1'b0;
    end else begin
        // 默认值 - 与 VHDL 一致
        valid_internal <= 1'b0;
        valid <= 1'b0;
        bin270_prev <= {`PE_INTBITS{1'b1}};  // 关键！
        
        calib_en_reg <= calib_en;
        
        // 优先级选择逻辑
        if (pe_valid_0 && (pe_bin_0 < bin270_prev)) begin
            bin_internal   <= pe_bin_0 + 3 * `DEPTH * 4;
            valid_internal <= 1'b1;
        end
        else if (pe_valid_90) begin
            bin_internal   <= pe_bin_90 + 2 * `DEPTH * 4;
            valid_internal <= 1'b1;
        end
        else if (pe_valid_180) begin
            bin_internal   <= pe_bin_180 + `DEPTH * 4;
            valid_internal <= 1'b1;
        end
        else if (pe_valid_270) begin
            bin_internal   <= pe_bin_270;
            valid_internal <= 1'b1;
            bin270_prev    <= pe_bin_270;
        end
        
        // 死区时间管理 - 修正版
        if (calib_en_reg != calib_en) begin
            deadtime_cnt <= 4'b0;
        end
        else if (deadtime_cnt < `CALIB_DEADTIME) begin
            deadtime_cnt <= deadtime_cnt + 4'd1;
        end
        
        // 输出逻辑
        if (deadtime_cnt >= `CALIB_DEADTIME) begin
            valid      <= valid_internal;
            calib_flag <= calib_en_reg;
        end
        
        // bin 总是更新
        bin <= bin_internal;
    end
end

endmodule