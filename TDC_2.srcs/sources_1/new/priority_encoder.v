// ============================================================================
// Priority Encoder Module
// ============================================================================
// 将延迟线的温度计码转换为二进制位置编码
// 从VHDL priority_encoder.vhd转换而来
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"

module priority_encoder #(
    parameter PHASE = "0"       // 相位: "0", "90", "180", "270"
)(
    input  wire                     CLK_P0,
    input  wire                     CLK_P90,
    input  wire                     CLK_P180,
    input  wire                     CLK_P270,
    input  wire                     RST,
    input  wire [`BINS_WIDTH-1:0]  bins,       // 延迟线输入(96位)
    output reg  [`PE_INTBITS-1:0]  bin,        // 位置输出(9位)
    output reg                      valid       // 有效标志
);

    // ========================================================================
    // 内部信号声明
    // ========================================================================
    wire sample_clk;                            // 采样时钟
    integer i;
    
    // 第一级流水线 (对应VHDL的s.bins和s.cpos)
    reg [`BINS_WIDTH-1:0] bins_reg;            // 对应VHDL的s.bins
    reg [3:0]              cpos;                // 对应VHDL的s.cpos
    
    // 第二级流水线 (对应VHDL的s.sslv, s.valid1, s.cpos2)
    reg [11:0] sslv;                            // 对应VHDL的s.sslv
    reg [1:0]  valid1;                          // 对应VHDL的s.valid1
    reg [3:0]  cpos2;                           // 对应VHDL的s.cpos2
    
    // 第三级流水线 (对应VHDL的s.bin和s.valid2)
    reg [`PE_INTBITS-1:0] bin_out;             // 对应VHDL的s.bin
    reg                    valid2;              // 对应VHDL的s.valid2

    // ========================================================================
    // 时钟相位选择(用于第一级采样)
    // ========================================================================
    generate
        if (PHASE == "0") begin : gen_phase_0
            assign sample_clk = CLK_P0;
        end else if (PHASE == "90") begin : gen_phase_90
            assign sample_clk = CLK_P90;
        end else if (PHASE == "180") begin : gen_phase_180
            assign sample_clk = CLK_P180;
        end else begin : gen_phase_270
            assign sample_clk = CLK_P270;
        end
    endgenerate

    // ========================================================================
    // 第一级: 粗定位
    // ========================================================================
    // VHDL中在一个时钟周期内:
    //   1. 计算variable v_coarse (立即生效)
    //   2. s.bins <= d.bins (周期结束时更新)
    //   3. s.cpos <= onehot2bin(...v_coarse...) (周期结束时更新)
    // Verilog实现: 使用组合逻辑+时序逻辑分离
    
    reg [15:0] v_coarse;  // 组合逻辑计算的v_coarse
    
    always @(*) begin
        // 组合逻辑: 对应VHDL的variable v_coarse计算
        for (i = 0; i < 16; i = i + 1) begin
            if (bins[i*6 +: 6] == 6'b111111)
                v_coarse[i] = 1'b1;
            else
                v_coarse[i] = 1'b0;
        end
    end
    
    always @(posedge sample_clk) begin : stage1
        // 对应VHDL: s.bins <= d.bins; s.cpos <= onehot2bin(therm2onehot(v_coarse));
        bins_reg <= bins;
        cpos     <= onehot2bin(therm2onehot({1'b0, v_coarse}));
    end

    // ========================================================================
    // 第二级: 精细定位
    // ========================================================================
    // VHDL中: bins_extended := x"000" & s.bins (variable,立即计算)
    //         s.sslv <= bins_extended(...s.cpos...) (使用上一周期的s.cpos)
    // Verilog: 使用组合逻辑bins_extended
    
    wire [`BINS_WIDTH+12-1:0] bins_extended;
    assign bins_extended = {12'h000, bins_reg};
    
    always @(posedge sample_clk) begin : stage2
        // 对应VHDL: s.sslv <= bins_extended(...); s.valid1 <= ...; s.cpos2 <= s.cpos;
        sslv   <= bins_extended[cpos*6 +: 12];
        valid1 <= {bins_reg[`BINS_WIDTH-1], bins_reg[0]};
        cpos2  <= cpos;
    end

    // ========================================================================
    // 第三级: 最终计算
    // ========================================================================
    // VHDL: s.bin <= resize(s.cpos2*6 + find_msb(s.sslv), PE_INTBITS);
    //       s.valid2 <= s.valid1(0) and (not s.valid1(1));
    
    always @(posedge sample_clk) begin : stage3
        // 对应VHDL: s.bin <= ...; s.valid2 <= ...;
        bin_out <= cpos2 * 6 + find_msb(sslv);
        valid2  <= valid1[0] && (!valid1[1]);
    end

    // ========================================================================
    // 输出同步到主时钟域 (匹配VHDL的两级同步)
    // ========================================================================
    reg [`PE_INTBITS-1:0] bin_sync;
    reg                    valid_sync;
    
    generate
        if (PHASE == "0") begin : gen_sync_0
            // Phase 0: sample_clk = CLK，无需CDC
            always @(posedge CLK_P0) begin
                bin_sync  <= bin_out;
                valid_sync <= valid2;
            end
        end else if (PHASE == "90") begin : gen_sync_90
            // Phase 90: sample_clk = CLK_P90，需要CDC到CLK
            // 第一级同步（对应VHDL的s.bin_out）
            always @(posedge CLK_P0) begin
                bin_sync  <= bin_out;
                valid_sync <= valid2;
            end
        end else if (PHASE == "180") begin : gen_sync_180
            // Phase 180: sample_clk = ~CLK，需要CDC到CLK_P90
            // 第一级同步（对应VHDL的s.bin_out）
            always @(posedge CLK_P90) begin
                bin_sync  <= bin_out;
                valid_sync <= valid2;
            end
        end else begin : gen_sync_270
            // Phase 270: sample_clk = ~CLK_P90，需要CDC到CLK下降沿
            // 第一级同步（对应VHDL的s.bin_out）
            always @(posedge CLK_P180) begin
                bin_sync  <= bin_out;
                valid_sync <= valid2;
            end
        end
    endgenerate
    
    // 第二级同步：输出到统一时钟域（对应VHDL的q.bin/q.valid）
    always @(posedge CLK_P0) begin
        bin   <= bin_sync;
        valid <= valid_sync;
    end

endmodule
