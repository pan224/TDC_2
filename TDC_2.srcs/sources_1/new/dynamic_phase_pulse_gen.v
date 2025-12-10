`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: dynamic_phase_pulse_gen
// Description: 使用 MMCM 动态相位调整生成可控延迟的脉冲
//////////////////////////////////////////////////////////////////////////////////

module dynamic_phase_pulse_gen #(
    parameter PHASE_STEPS = 56,      // MMCM 相位步进数
    parameter PULSE_WIDTH = 2        // 脉冲宽度（时钟周期数），2 = 7.7ns @ 260MHz
)(
    input wire          clk_ref,        // 260MHz 参考时钟
    input wire          reset,
    
    // VIO 控制接口
    input wire [7:0]    target_phase,   // 目标相位步数 (0-255)
    input wire          phase_load,     // 加载新相位
    
    // 脉冲生成
    input wire          trigger,        // 触发信号
    output reg          pulse_out,      // 输出脉冲
    output wire         phase_ready     // 相位调整完成
);

//------------------------------------------------------------------------------
// Clocking Wizard 实例 (带动态相位调整)
//------------------------------------------------------------------------------
wire clk_260MHz_shifted;

// 动态相位调整接口
wire psdone;
reg psen;
reg psincdec;

clk_wiz_phase clk_wiz_inst (
    .clk_in1(clk_ref),           // 260MHz 输入
    .clk_out1(clk_260MHz_shifted), // 260MHz 输出 (可调相位)
    .reset(reset),
    
    // 动态相位调整
    .psclk(clk_ref),             // 使用参考时钟
    .psen(psen),
    .psincdec(psincdec),
    .psdone(psdone)
);

//------------------------------------------------------------------------------
// 相位调整控制状态机
//------------------------------------------------------------------------------
localparam IDLE         = 3'd0;
localparam CALC_DELTA   = 3'd1;
localparam SHIFT_PHASE  = 3'd2;
localparam WAIT_DONE    = 3'd3;
localparam COMPLETE     = 3'd4;

reg [2:0] state;
reg [7:0] current_phase;
reg [7:0] target_phase_reg;
reg [7:0] phase_delta;  // 带符号
reg phase_direction;    // 0=减少, 1=增加

assign phase_ready = (state == IDLE || state == COMPLETE);

// 边沿检测
reg phase_load_d1;
wire phase_load_posedge;

always @(posedge clk_ref) begin
    phase_load_d1 <= phase_load;
end

assign phase_load_posedge = phase_load & ~phase_load_d1;

always @(posedge clk_ref) begin
    if(reset) begin
        state <= IDLE;
        current_phase <= 8'd0;
        target_phase_reg <= 8'd0;
        psen <= 1'b0;
        psincdec <= 1'b0;
        phase_delta <= 8'd0;
    end
    else begin
        case(state)
            IDLE: begin
                psen <= 1'b0;
                if(phase_load_posedge) begin
                    target_phase_reg <= target_phase;
                    state <= CALC_DELTA;
                end
            end
            
            CALC_DELTA: begin
                // 计算相位差
                if(target_phase_reg > current_phase) begin
                    phase_delta <= target_phase_reg - current_phase;
                    phase_direction <= 1'b1; // 增加
                end
                else if(target_phase_reg < current_phase) begin
                    phase_delta <= current_phase - target_phase_reg;
                    phase_direction <= 1'b0; // 减少
                end
                else begin
                    phase_delta <= 8'd0;
                end
                
                state <= SHIFT_PHASE;
            end
            
            SHIFT_PHASE: begin
                if(phase_delta == 0) begin
                    state <= COMPLETE;
                end
                else begin
                    psen <= 1'b1;
                    psincdec <= phase_direction;
                    state <= WAIT_DONE;
                end
            end
            
            WAIT_DONE: begin
                psen <= 1'b0;
                if(psdone) begin
                    // 更新当前相位
                    if(phase_direction) begin
                        current_phase <= current_phase + 1'b1;
                    end
                    else begin
                        current_phase <= current_phase - 1'b1;
                    end
                    
                    phase_delta <= phase_delta - 1'b1;
                    state <= SHIFT_PHASE;
                end
            end
            
            COMPLETE: begin
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

//------------------------------------------------------------------------------
// 使用相位调整后的时钟生成脉冲
//------------------------------------------------------------------------------
reg trigger_sync1, trigger_sync2;
reg trigger_d1;
wire trigger_posedge;

// 同步 trigger 到 clk_260MHz_shifted 域
always @(posedge clk_260MHz_shifted) begin
    if(reset) begin
        trigger_sync1 <= 1'b0;
        trigger_sync2 <= 1'b0;
        trigger_d1 <= 1'b0;
    end
    else begin
        trigger_sync1 <= trigger;
        trigger_sync2 <= trigger_sync1;
        trigger_d1 <= trigger_sync2;
    end
end

assign trigger_posedge = trigger_sync2 & ~trigger_d1;

// 可配置脉宽生成器
localparam COUNTER_WIDTH = $clog2(PULSE_WIDTH)+1;
reg [COUNTER_WIDTH-1:0] pulse_counter;

always @(posedge clk_260MHz_shifted) begin
    if(reset) begin
        pulse_out <= 1'b0;
        pulse_counter <= {COUNTER_WIDTH{1'b0}};
    end
    else begin
        if(trigger_posedge) begin
            pulse_out <= 1'b1;
            pulse_counter <= PULSE_WIDTH - 1;  // 开始计数
        end
        else if(pulse_counter > 0) begin
            pulse_out <= 1'b1;                 // 保持高电平
            pulse_counter <= pulse_counter - 1'b1;
        end
        else begin
            pulse_out <= 1'b0;
        end
    end
end

endmodule