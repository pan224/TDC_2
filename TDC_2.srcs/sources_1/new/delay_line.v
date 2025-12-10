// ============================================================================
// Delay Line Module - Tapped Delay Line using CARRY4
// ============================================================================
// 使用CARRY4原语实现的抽头延迟线
// 从VHDL delay_line.vhd转换而来
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"

module delay_line #(
    parameter PHASE = "0",      // 采样相位: "0", "90", "180", "270"
    parameter CH = "ch1"        // 通道标识: "ch1" or "ch2"
)(
    input  wire                     CLK_P0,
    input  wire                     CLK_P90,
    input  wire                     CLK_P180,
    input  wire                     CLK_P270,

    // 输入接口
    input  wire                     sensor,         // 传感器输入信号
    output wire [`BINS_WIDTH-1:0]   bins            // 延迟线抽头输出(96位)
);

    // ========================================================================
    // 内部信号声明
    // ========================================================================
    wire sample_clk;                                // 采样时钟
    wire [`BINS_WIDTH-1:0] carry_out;              // CARRY4输出
    wire [`BINS_WIDTH-1:0] bins_sampled;           // 采样后的bins (wire类型)
    wire sensor_delayed;                            // 延迟后的传感器信号
    wire [3:0] co0;                                // 第一个CARRY4的进位输出

    assign bins = bins_sampled;

    // ========================================================================
    // 时钟相位选择
    // ========================================================================
    generate
        if (PHASE == "0") begin : gen_phase_0
            assign sample_clk = CLK_P0;
        end else if (PHASE == "90") begin : gen_phase_90
            assign sample_clk = CLK_P90;
        end else if (PHASE == "180") begin : gen_phase_180
            assign sample_clk = CLK_P180;
        end else begin : gen_phase_270  // PHASE == "270"
            assign sample_clk = CLK_P270;
        end
    endgenerate

    // ========================================================================
    // 触发器 - 传感器信号
    // ========================================================================
    // 使用FDCE异步清除触发器
    // 在sensor上升沿置位，在延迟链末端自清除
    generate
        if (`SIM == 0) begin : gen_sensor_ff_real
            (* DONT_TOUCH = "TRUE" *)
            (* RLOC = "X0Y0" *)
            FDCE #(
                .INIT(1'b0)
            ) sensor_ff (
                .Q(sensor_delayed),
                . C(sensor),
                .CE(1'b1),
                .CLR(carry_out[`BINS_WIDTH-1]),    // 延迟链末端自清除
                .D(1'b1)
            );
        end else begin : gen_sensor_ff_sim
            // 仿真模式下的简化实现
            reg sensor_reg;
            
            // 初始化sensor_reg
            initial sensor_reg = 1'b0;
            
            always @(posedge sensor or posedge carry_out[`BINS_WIDTH-1]) begin
                if (carry_out[`BINS_WIDTH-1])
                    sensor_reg <= 1'b0;
                else
                    sensor_reg <= 1'b1;
            end
            assign sensor_delayed = sensor_reg;
        end
    endgenerate

    // ========================================================================
    // CARRY4链 - 第一个CARRY4 (特殊处理)
    // ========================================================================
    generate
        if (`SIM == 0) begin : gen_carry0_real
            (* DONT_TOUCH = "TRUE" *)
            (* RLOC = "X0Y0" *)
            CARRY4 carry4_0 (
                .CO(co0),
                .O(),                               // 未使用
                .CI(1'b0),
                . CYINIT(sensor_delayed),
                .DI(4'b0000),
                .S(4'b1111)
            );
        end else begin : gen_carry0_sim
            // 仿真模式 - 简化模型
            assign co0 = {4{sensor_delayed}};
        end
    endgenerate

    // ========================================================================
    // CARRY4链 - 第一个有效CARRY4
    // ========================================================================
    generate
        if (`SIM == 0) begin : gen_carry1_real
            (* DONT_TOUCH = "TRUE" *)
            (* RLOC = "X0Y1" *)
            CARRY4 carry4_1 (
                .CO(carry_out[3:0]),
                .O(),
                .CI(co0[3]),
                .CYINIT(1'b0),
                .DI(4'b0000),
                .S(4'b1111)
            );
        end else begin : gen_carry1_sim
            // 仿真模式 - 第一个CARRY4的输出
            assign carry_out[3:0] = co0;
        end
    endgenerate

    // ========================================================================
    // CARRY4链 - 后续CARRY4单元
    // ========================================================================
    // 注意：Verilog属性不支持在generate循环中使用变量
    // RLOC布局约束应该在XDC文件中定义，或者依赖工具自动推断CARRY4链
    // DONT_TOUCH属性可以保持CARRY4链的完整性
    genvar i;
    generate
        for (i = 1; i < `DEPTH; i = i + 1) begin : gen_carry_chain
            if (`SIM == 0) begin : gen_carry_real
                (* DONT_TOUCH = "TRUE" *)
                (* HBLKNM = {CH, "_CARRY_CHAIN"} *)  // 将同一通道的CARRY4分组
                CARRY4 carry4_inst (
                    .CO(carry_out[i*4+3:i*4]),
                    .O(),
                    .CI(carry_out[i*4-1]),
                    .CYINIT(1'b0),
                    .DI(4'b0000),
                    .S(4'b1111)
                );
            end else begin : gen_carry_sim
                // 仿真模式 - 传播信号
                assign carry_out[i*4+3:i*4] = carry_out[i*4-1:i*4-4];
            end
        end
    endgenerate

    // ========================================================================
    // 采样触发器阵列
    // ========================================================================
    generate
        for (i = 0; i < `BINS_WIDTH; i = i + 1) begin : gen_sample_ffs
            if (`SIM == 0) begin : gen_sample_real
                (* DONT_TOUCH = "TRUE" *)
                FDCE #(
                    . INIT(1'b0)
                ) sample_ff (
                    .Q(bins_sampled[i]),
                    . C(sample_clk),
                    .CE(1'b1),
                    .CLR(1'b0),
                    . D(carry_out[i])
                );
            end else begin : gen_sample_sim
                // 仿真模式采样 - 使用reg信号
                reg bins_sampled_reg;
                
                // 初始化采样寄存器
                initial bins_sampled_reg = 1'b0;
                
                always @(posedge sample_clk) begin
                    bins_sampled_reg <= carry_out[i];
                end
                assign bins_sampled[i] = bins_sampled_reg;
            end
        end
    endgenerate

    // ========================================================================
    // 仿真模式延迟模型 (非综合代码)
    // ========================================================================
    generate
        if (`SIM == 1) begin : gen_sim_delay
            // 声明仿真相关的本地信号
            reg clk_sim;
            reg [`BINS_WIDTH-1:0] bins_sim;
            reg sensor_sim;
            integer cnt;
            integer offset;
            
            // 初始化仿真信号
            initial begin
                clk_sim = 1'b0;
                bins_sim = {`BINS_WIDTH{1'b0}};
                sensor_sim = 1'b0;
                cnt = 0;
                offset = 0;
            end

            // 仿真时钟 - 7ps周期
            always #0.007 clk_sim = ~clk_sim;

            always @(posedge clk_sim) begin
                // 根据通道选择偏移量
                if (CH == "ch2")
                    offset = `SIM_OFFSET;
                else
                    offset = 0;

                // 移位寄存器：将传感器输入移入bins_sim
                bins_sim <= {bins_sim[`BINS_WIDTH-2:0], sensor_sim};
                
                // 计数器逻辑：在特定计数时翻转传感器输入
                if (cnt == 6000 + offset) begin
                    sensor_sim <= ~sensor_sim;
                    cnt <= offset;
                end else begin
                    cnt <= cnt + 1;
                end
            end

            // 将仿真的bins_sim连接到carry_out
            assign carry_out = bins_sim;
        end
    endgenerate

endmodule