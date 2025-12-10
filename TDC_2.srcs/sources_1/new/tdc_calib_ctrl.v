// ============================================================================
// TDC 校准控制模块
// ============================================================================
// 管理TDC校准流程:
// 1. 自动校准: 上电后未就绪时自动校准
// 2. 手动校准: 就绪后通过命令触发
// 3. 环形振荡器: 提供校准时钟源
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"

module tdc_calib_ctrl (
    // 时钟和复位
    input  wire         clk_260MHz,
    input  wire         rst_260MHz,
    input  wire         sys_reset,
    
    // 控制输入
    input  wire         tdc_ready,              // TDC 就绪状态
    input  wire         manual_calib_trigger,   // 手动校准触发 (260MHz域)
    
    // 校准输出
    output wire         calib_sel,              // 校准选择信号
    output wire         ro_clk                  // 环形振荡器时钟输出
);

    // ========================================================================
    // 参数定义
    // ========================================================================
    // 手动校准时长：约1秒（260MHz × 400M cycles ≈ 1秒）
    localparam MANUAL_CALIB_CYCLES = 16'd40000;  // 简化为 40000 周期用于测试
    
    // ========================================================================
    // 手动校准状态机
    // ========================================================================
    reg         manual_calib_en;
    reg [15:0]  manual_calib_cnt;
    
    always @(posedge clk_260MHz) begin
        if (rst_260MHz) begin
            manual_calib_en <= 1'b0;
            manual_calib_cnt <= 16'b0;
        end
        else if (manual_calib_trigger && tdc_ready) begin
            // 触发手动校准 (仅在就绪状态下有效)
            manual_calib_en <= 1'b1;
            manual_calib_cnt <= MANUAL_CALIB_CYCLES;
        end
        else if (manual_calib_en) begin
            // 校准计数递减
            if (manual_calib_cnt > 0) begin
                manual_calib_cnt <= manual_calib_cnt - 1'b1;
            end
            else begin
                manual_calib_en <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // 校准选择逻辑
    // ========================================================================
    // 校准条件:
    // 1. 上电自动校准: 未就绪时 (tdc_ready=0)
    // 2. 手动校准: 就绪后通过命令触发 (manual_calib_en=1)
    assign calib_sel = ~tdc_ready | manual_calib_en;
    
    // ========================================================================
    // 环形振荡器校准源
    // ========================================================================
    wire ro_en;
    
    // 环形振荡器使能 (复位释放后启动)
    assign ro_en = ~sys_reset;
    
    // 环形振荡器实例化
    ro #(
        .LENGTH(`RO_LENGTH)
    ) ro_inst (
        .en(ro_en),
        .ro_clk(ro_clk)
    );

endmodule
