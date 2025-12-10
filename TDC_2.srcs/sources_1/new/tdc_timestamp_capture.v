// ============================================================================
// TDC 时间戳捕获模块
// ============================================================================
// 捕获双通道TDC测量结果并组合为完整时间戳
// - 全局粗计数器管理
// - 事件ID管理
// - 边沿检测防止重复触发
// - 时间戳打包输出
// ============================================================================

`timescale 1ns / 1ps

module tdc_timestamp_capture #(
    parameter COARSE_BITS = 16              // 粗计数位宽
)(
    // 时钟和复位
    input  wire                     clk_260MHz,
    input  wire                     rst_260MHz,
    
    // TDC 通道输入
    input  wire                     ch1_valid,          // UP 通道有效
    input  wire [12:0]              ch1_time_fine,      // UP 通道精细时间
    input  wire                     ch2_valid,          // DOWN 通道有效
    input  wire [12:0]              ch2_time_fine,      // DOWN 通道精细时间
    
    // TDC 控制
    input  wire                     tdc_reset_trigger,  // TDC 复位触发
    
    // UP 通道输出
    output reg                      up_valid,
    output reg [12:0]               up_fine,
    output reg [COARSE_BITS-1:0]    up_coarse,
    output reg [7:0]                up_id,
    
    // DOWN 通道输出
    output reg                      down_valid,
    output reg [12:0]               down_fine,
    output reg [COARSE_BITS-1:0]    down_coarse,
    output reg [7:0]                down_id,
    
    // 状态输出
    output reg [7:0]                measurement_id      // 测量周期ID
);

    // ========================================================================
    // 全局粗计数器
    // ========================================================================
    reg [COARSE_BITS-1:0]   global_coarse_counter;
    reg [7:0]               up_event_id_cnt;        // UP 事件计数器
    reg [7:0]               down_event_id_cnt;      // DOWN 事件计数器
    
    // ========================================================================
    // 边沿检测 - 避免重复触发
    // ========================================================================
    reg ch1_valid_d1;
    reg ch2_valid_d1;
    
    wire ch1_valid_posedge;
    wire ch2_valid_posedge;
    
    assign ch1_valid_posedge = ch1_valid & ~ch1_valid_d1;
    assign ch2_valid_posedge = ch2_valid & ~ch2_valid_d1;
    
    always @(posedge clk_260MHz) begin
        if (rst_260MHz) begin
            ch1_valid_d1 <= 1'b0;
            ch2_valid_d1 <= 1'b0;
        end
        else begin
            ch1_valid_d1 <= ch1_valid;
            ch2_valid_d1 <= ch2_valid;
        end
    end
    
    // ========================================================================
    // 粗计数器和测量ID管理
    // ========================================================================
    always @(posedge clk_260MHz) begin
        if (rst_260MHz) begin
            global_coarse_counter <= {COARSE_BITS{1'b0}};
            measurement_id <= 8'b0;
            up_event_id_cnt <= 8'b0;
            down_event_id_cnt <= 8'b0;
        end
        else if (tdc_reset_trigger) begin
            // TDC RESET: 重置粗计数器, 开始新的测量周期
            global_coarse_counter <= {COARSE_BITS{1'b0}};
            measurement_id <= measurement_id + 1'b1;
        end
        else begin
            // 正常递增
            global_coarse_counter <= global_coarse_counter + 1'b1;
        end
        
        // 事件ID独立递增: 每次通道valid上升沿时递增
        if (ch1_valid_posedge) begin
            up_event_id_cnt <= up_event_id_cnt + 1'b1;
        end
        if (ch2_valid_posedge) begin
            down_event_id_cnt <= down_event_id_cnt + 1'b1;
        end
    end
    
    // ========================================================================
    // UP 通道时间戳捕获
    // ========================================================================
    always @(posedge clk_260MHz) begin
        if (rst_260MHz) begin
            up_fine <= 13'b0;
            up_coarse <= {COARSE_BITS{1'b0}};
            up_id <= 8'b0;
            up_valid <= 1'b0;
        end
        else begin
            up_valid <= 1'b0;                   // 默认
            
            if (ch1_valid_posedge) begin        // 仅在上升沿触发
                up_fine <= ch1_time_fine;
                up_coarse <= global_coarse_counter;
                up_id <= up_event_id_cnt;
                up_valid <= 1'b1;
            end
        end
    end
    
    // ========================================================================
    // DOWN 通道时间戳捕获
    // ========================================================================
    always @(posedge clk_260MHz) begin
        if (rst_260MHz) begin
            down_fine <= 13'b0;
            down_coarse <= {COARSE_BITS{1'b0}};
            down_id <= 8'b0;
            down_valid <= 1'b0;
        end
        else begin
            down_valid <= 1'b0;                 // 默认
            
            if (ch2_valid_posedge) begin        // 仅在上升沿触发
                down_fine <= ch2_time_fine;
                down_coarse <= global_coarse_counter;
                down_id <= down_event_id_cnt;
                down_valid <= 1'b1;
            end
        end
    end

endmodule
