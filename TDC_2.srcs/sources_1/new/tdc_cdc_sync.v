// ============================================================================
// TDC 跨时钟域同步模块
// ============================================================================
// 处理所有跨时钟域信号同步 (200MHz <-> 260MHz)
// - 手动校准触发信号: 200MHz -> 260MHz
// - 扫描命令信号: 200MHz -> 260MHz
// ============================================================================

`timescale 1ns / 1ps

module tdc_cdc_sync (
    // 时钟和复位
    input  wire         clk_260MHz,
    input  wire         clk_200MHz,
    input  wire         rst_260MHz,
    input  wire         rst_200MHz,
    
    // 200MHz 域输入
    input  wire         manual_calib_trigger_200,   // 手动校准触发
    input  wire         scan_cmd_trigger_200,       // 扫描命令触发
    input  wire [10:0]  scan_cmd_param_200,         // 扫描命令参数
    
    // 260MHz 域输出
    output wire         manual_calib_trigger_260,   // 同步后的手动校准触发
    output wire         scan_cmd_trigger_260,       // 同步后的扫描命令触发
    output wire [10:0]  scan_cmd_param_260          // 同步后的扫描命令参数
);

    // ========================================================================
    // 手动校准触发信号同步 (200MHz -> 260MHz)
    // ========================================================================
    (* ASYNC_REG = "TRUE" *) 
    reg manual_calib_sync1, manual_calib_sync2, manual_calib_sync3;
    
    always @(posedge clk_260MHz or posedge rst_260MHz) begin
        if (rst_260MHz) begin
            manual_calib_sync1 <= 1'b0;
            manual_calib_sync2 <= 1'b0;
            manual_calib_sync3 <= 1'b0;
        end
        else begin
            manual_calib_sync1 <= manual_calib_trigger_200;
            manual_calib_sync2 <= manual_calib_sync1;
            manual_calib_sync3 <= manual_calib_sync2;
        end
    end
    
    // 边沿检测
    assign manual_calib_trigger_260 = manual_calib_sync2 & ~manual_calib_sync3;
    
    // ========================================================================
    // 扫描命令同步 (200MHz -> 260MHz)
    // ========================================================================
    // 注意: 这里简化处理，实际项目中应使用握手协议或FIFO
    // 当前实现假设命令触发时参数已稳定
    
    // 扫描命令触发同步
    (* ASYNC_REG = "TRUE" *) 
    reg scan_trigger_sync1, scan_trigger_sync2;
    
    always @(posedge clk_260MHz or posedge rst_260MHz) begin
        if (rst_260MHz) begin
            scan_trigger_sync1 <= 1'b0;
            scan_trigger_sync2 <= 1'b0;
        end
        else begin
            scan_trigger_sync1 <= scan_cmd_trigger_200;
            scan_trigger_sync2 <= scan_trigger_sync1;
        end
    end
    
    assign scan_cmd_trigger_260 = scan_trigger_sync2;
    
    // 扫描命令参数同步
    (* ASYNC_REG = "TRUE" *) 
    reg [10:0] scan_param_sync1, scan_param_sync2;
    
    always @(posedge clk_260MHz or posedge rst_260MHz) begin
        if (rst_260MHz) begin
            scan_param_sync1 <= 11'b0;
            scan_param_sync2 <= 11'b0;
        end
        else begin
            scan_param_sync1 <= scan_cmd_param_200;
            scan_param_sync2 <= scan_param_sync1;
        end
    end
    
    assign scan_cmd_param_260 = scan_param_sync2;

endmodule
