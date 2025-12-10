// ============================================================================
// TDC 复位同步模块
// ============================================================================
// 处理跨时钟域的复位信号同步
// 使用三级触发器链实现亚稳态消除
// ============================================================================

`timescale 1ns / 1ps

module tdc_reset_sync (
    // 输入
    input  wire         sys_reset,          // 异步复位输入
    input  wire         clk_260MHz,         // 260MHz 时钟域
    input  wire         clk_200MHz,         // 200MHz 时钟域
    
    // 输出
    output wire         rst_260MHz,         // 260MHz 域同步复位
    output wire         rst_200MHz          // 200MHz 域同步复位
);

    // ========================================================================
    // 260MHz 域复位同步
    // ========================================================================
    reg  [2:0]  reset_sync_260;
    
    always @(posedge clk_260MHz or posedge sys_reset) begin
        if (sys_reset)
            reset_sync_260 <= 3'b111;
        else
            reset_sync_260 <= {reset_sync_260[1:0], 1'b0};
    end
    
    assign rst_260MHz = reset_sync_260[2];
    
    // ========================================================================
    // 200MHz 域复位同步 (用于以太网通信)
    // ========================================================================
    reg  [2:0]  reset_sync_200;
    
    always @(posedge clk_200MHz or posedge sys_reset) begin
        if (sys_reset)
            reset_sync_200 <= 3'b111;
        else
            reset_sync_200 <= {reset_sync_200[1:0], 1'b0};
    end
    
    assign rst_200MHz = reset_sync_200[2];

endmodule
