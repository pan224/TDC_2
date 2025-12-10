// ============================================================================
// Channel Module
// ============================================================================
// 单个测量通道的完整数据处理流程
// 从VHDL channel.vhd转换而来
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"

module channel #(
    parameter CH = "ch1"                // 通道标识
)(
    input  wire         CLK_P0,
    input  wire         CLK_P90,
    input  wire         CLK_P180,
    input  wire         CLK_P270,
    input  wire         RST,
    // 输入接口
    input  wire [12:0]  clk_period,     // 时钟周期(皮秒)
    input  wire         sensor,         // 传感器信号
    input  wire         calib_en,       // 校准使能
    // 输出接口
    output reg          ready,          // 就绪标志
    output reg          valid,          // 输出有效
    output reg  [12:0]  time_out        // 时间输出
);

    // ========================================================================
    // 内部信号声明
    // ========================================================================
    // dl_sync模块接口
    wire [`PE_INTBITS-1:0] dl_bin;
    wire                    dl_valid;
    wire                    dl_calib_flag;
    
    // LUT模块接口
    wire [17:0]             lut_data;
    wire                    lut_init;
    
    // 流水线寄存器
    reg [3:0]               valid_pipe;     // 4级有效流水线
    reg                     lut_init_reg;
    reg [17:0]              lut_data_reg;
    reg [30:0]              time_calc;      // 31位时间计算结果
    
    // LUT输入寄存器
    reg                     lut_valid_in;
    reg                     lut_calib_flag_in;
    reg [`PE_INTBITS-1:0]  lut_bin_in;



    // ========================================================================
    //信号缓冲
    // ========================================================================
    wire sensor_buf;
    
    BUF sensor_buffer (
        .I(sensor),
        .O(sensor_buf)
    );


    // ========================================================================
    // dl_sync模块实例化
    // ========================================================================
    dl_sync #(
        .CH(CH)
    ) dl_sync_inst (
        .CLK_P0(CLK_P0),
        .CLK_P90(CLK_P90),
        .CLK_P180(CLK_P180),
        .CLK_P270(CLK_P270),
        .RST(RST),
        .sensor(sensor_buf),
        .calib_en(calib_en),
        .bin(dl_bin),
        .valid(dl_valid),
        .calib_flag(dl_calib_flag)
    );

    // ========================================================================
    // LUT模块实例化
    // ========================================================================
    lut #(
        .CH(CH)
    ) lut_inst (
        .CLK(CLK_P0),
        .RST(RST),
        .valid_in(lut_valid_in),
        .calib_flag(lut_calib_flag_in),
        .bin_in(lut_bin_in),
        .data_out(lut_data),
        .init(lut_init)
    );

    // ========================================================================
    // 主数据处理流水线
    // ========================================================================
    always @(posedge CLK_P0) begin
        if (RST) begin
            ready           <= 1'b0;
            valid           <= 1'b0;
            valid_pipe      <= 4'b0;
            lut_init_reg    <= 1'b0;
            lut_valid_in    <= 1'b0;
            lut_data_reg    <= 18'b0;
            time_calc       <= 31'b0;
            time_out        <= 13'b0;
            
        end else begin
            // ================================================================
            // 默认值
            // ================================================================
            lut_valid_in <= 1'b0;
            valid_pipe   <= {valid_pipe[2:0], 1'b0};  // 左移，LSB补0
            valid        <= 1'b0;
            
            // ================================================================
            // 就绪标志管理
            // ================================================================
            if (lut_init) begin
                ready <= 1'b1;
            end
            
            // ================================================================
            // Stage 0: 接收dl_sync有效数据
            // ================================================================
            // 流水线忙检测：只有在流水线空闲时才接受新数据
            // 防止数据重叠导致流水线异常 (避免 0x1→0x3→0x6→0xC 的错误模式)
            if (dl_valid && (valid_pipe == 4'b0000)) begin
                lut_init_reg        <= lut_init;
                lut_bin_in          <= dl_bin;
                lut_valid_in        <= 1'b1;
                lut_calib_flag_in   <= dl_calib_flag;
                
                // 忽略校准数据，只处理测量数据
                if (!dl_calib_flag) begin
                    valid_pipe[0] <= 1'b1;
                end
            end
            
            // ================================================================
            // Stage 1: 等待LUT数据
            // ================================================================
            if (valid_pipe[1] && lut_init_reg) begin
                lut_data_reg <= lut_data;
            end
            
            // ================================================================
            // Stage 2: 执行乘法 (lut_data × clk_period)
            // ================================================================
            if (valid_pipe[2] && lut_init_reg) begin
                time_calc <= lut_data_reg * clk_period;
            end
            
            // ================================================================
            // Stage 3: 右移归一化并输出
            // ================================================================
            // T = (LUT_DATA * CLK_PERIOD) >> log2(HIST_SIZE)
            // HIST_SIZE = 2^18, 所以右移18位
            if (valid_pipe[3] && lut_init_reg) begin
                time_out <= time_calc[30:18];  // 右移18位，取高13位
                valid    <= 1'b1;
            end
        end
    end
    
    // ========================================================================
    // 调试信号输出
    // ========================================================================
    assign lut_init_out = lut_init;
    assign dl_valid_out = dl_valid;
    assign valid_pipe_out = valid_pipe;

endmodule
