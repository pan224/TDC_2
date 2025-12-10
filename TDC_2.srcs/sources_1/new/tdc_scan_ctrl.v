// ============================================================================
// TDC 扫描测试控制模块
// ============================================================================
// 集成动态相位脉冲生成器，实现 0-140 相位步进扫描测试
// 通过以太网命令控制测试模式和参数
// ============================================================================

`timescale 1ns / 1ps

module tdc_scan_ctrl (
    // ========================================================================
    // 时钟和复位
    // ========================================================================
    input  wire         clk_260MHz,         // 260MHz 系统时钟
    input  wire         sys_reset,
    
    // ========================================================================
    // 以太网命令接口 (260MHz 时钟域)
    // ========================================================================
    input  wire         scan_cmd_trigger,   // 扫描命令触发
    input  wire [10:0]   scan_cmd_param,     // 命令参数
//     [10]     : 扫描模式 (0=单步, 1=全扫描)
//     [9:8]    : 通道选择 (00=无, 10=UP, 01=DOWN, 11=UP+DOWN)
//     [7:0]    : 相位参数0~255
    
    output reg          scan_running,       // 扫描运行标志
    output reg [7:0]    scan_status,        // 扫描状态
    // [7] = busy
    // [6:0] = 当前相位
    
    // ========================================================================
    // TDC 测试信号输出
    // ========================================================================
    output wire         test_pulse_up,      // UP 测试脉冲
    output wire         test_pulse_down,    // DOWN 测试脉冲（延迟）
    output reg          tdc_reset_trigger   // TDC 复位触发
);

    // ========================================================================
    // 参数定义
    // ========================================================================
    localparam PHASE_STEPS = 56;        // MMCM 相位步进数
    localparam PULSE_WIDTH = 1;         // 脉冲宽度（时钟周期）
    localparam MAX_PHASE = 255;         // 最大相位步数（0-255，共256次扫描）
    
    // 测试模式
    localparam MODE_STOP      = 2'b00;
    localparam MODE_SINGLE    = 2'b01;
    localparam MODE_SCAN      = 2'b10;
    localparam MODE_CONTINUOUS = 2'b11;
    
    // ========================================================================
    // 命令参数锁存 (260MHz 时钟域)
    // ========================================================================
    // 注意: scan_cmd_trigger 和 scan_cmd_param 跨时钟域同步 (200MHz -> 260MHz)
    //暂时不使用双寄存器同步
    wire [10:0] scan_param_latch;
    wire scan_cmd_trigger_posedge;
    assign scan_param_latch = scan_cmd_param;
    assign scan_cmd_trigger_posedge = scan_cmd_trigger;
    // ========================================================================
    // 动态相位脉冲生成器 (UP 信号)
    // ========================================================================
    wire        phase_ready_up;
    reg         phase_load_up;
    reg         trigger_up;
    reg [7:0]   phase_value_up;
    
    dynamic_phase_pulse_gen #(
        .PHASE_STEPS(PHASE_STEPS),
        .PULSE_WIDTH(PULSE_WIDTH)
    ) pulse_gen_up (
        .clk_ref(clk_260MHz),
        .reset(sys_reset),
        .target_phase(phase_value_up),
        .phase_load(phase_load_up),
        .trigger(trigger_up),
        .pulse_out(test_pulse_up),
        .phase_ready(phase_ready_up)
    );
    
    // ========================================================================
    // 动态相位脉冲生成器 (DOWN 信号 - 固定延迟)
    // ========================================================================
    wire        phase_ready_down;
    reg         phase_load_down;
    reg         trigger_down;
    reg [7:0]   phase_value_down;
    
    dynamic_phase_pulse_gen #(
        .PHASE_STEPS(PHASE_STEPS),
        .PULSE_WIDTH(PULSE_WIDTH)
    ) pulse_gen_down (
        .clk_ref(clk_260MHz),
        .reset(sys_reset),
        .target_phase(phase_value_down),
        .phase_load(phase_load_down),
        .trigger(trigger_down),
        .pulse_out(test_pulse_down),
        .phase_ready(phase_ready_down)
    );
    
    // ========================================================================
    // 扫描控制状态机
    // ========================================================================
    localparam ST_IDLE          = 4'd0;
    localparam ST_PARAM_LATCH   = 4'd1;  // 等待参数锁存稳定
    localparam ST_INIT_PARAM    = 4'd2;  // 读取稳定后的参数
    localparam ST_LOAD_PHASE    = 4'd3;
    localparam ST_WAIT_READY    = 4'd4;
    localparam ST_RESET_LOW     = 4'd5;
    localparam ST_TRIGGER_UP    = 4'd6;
    localparam ST_WAIT_UP       = 4'd7;
    localparam ST_TRIGGER_DOWN  = 4'd8;
    localparam ST_WAIT_DOWN     = 4'd9;
    localparam ST_RESET_HIGH    = 4'd10;
    localparam ST_SCAN_NEXT     = 4'd11;
    localparam ST_DONE          = 4'd12;
    
    reg [3:0]   state;
    reg [15:0]  counter;
    reg [7:0]   current_phase;
    reg [7:0]   down_phase_offset;      // DOWN 信号相对 UP 的延迟
    
    // 从锁存的参数中提取命令字段
    reg        scan_mode;   // 0=单步, 1=全扫描
    reg [1:0]  channel_sel;    // 00=无, 10=UP, 01=DOWN, 11=UP+DOWN
    reg [7:0]  target_phase;   // 相位参数

    // ========================================================================
    // 主控制状态机
    // ========================================================================
    always @(posedge clk_260MHz) begin
        if (sys_reset) begin
            state <= ST_IDLE;
            counter <= 16'd0;
            current_phase <= 8'd0;
            down_phase_offset <= 8'd0;     // 默认 DOWN 延迟 0 步
            
            phase_load_up <= 1'b0;
            phase_load_down <= 1'b0;
            trigger_up <= 1'b0;
            trigger_down <= 1'b0;
            tdc_reset_trigger <= 1'b1;
            
            scan_running <= 1'b0;
            scan_status <= 8'b0;
            
            phase_value_up <= 8'd0;
            phase_value_down <= 8'd70;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    tdc_reset_trigger <= 1'b1;//默认高
                    trigger_up <= 1'b0;
                    trigger_down <= 1'b0;
                    phase_load_up <= 1'b0;
                    phase_load_down <= 1'b0;
                    counter <= 16'd0;
                    scan_running <= 1'b0;
                    
                    // 更新状态输出
                    scan_status <= {1'b0, current_phase[6:0]};
                    if(scan_cmd_trigger_posedge) begin
                        // 检测到延迟后的触发，锁存scan_param的值
                        scan_mode <= scan_param_latch[10];
                        channel_sel <= scan_param_latch[9:8];
                        target_phase <= scan_param_latch[7:0];
                        state <= ST_INIT_PARAM;
                    end
                end
                ST_INIT_PARAM: begin
                    // 现在 scan_param_latch 已经稳定，读取参数并初始化
                    if (scan_mode) begin
                        // 全扫描模式：从 0 扫描到 255
                        current_phase <= 8'd0;
                        phase_value_up <= 8'd0;
                        phase_value_down <= down_phase_offset;
                    end
                    else begin
                        // 单步模式：使用指定相位
                        current_phase <= target_phase;
                        phase_value_up <= target_phase;
                        phase_value_down <= target_phase + down_phase_offset;
                    end
                    phase_load_up <= 1'b1;
                    phase_load_down <= 1'b1;
                    scan_running <= 1'b1;
                    state <= ST_LOAD_PHASE;
                end
                
                ST_LOAD_PHASE: begin
                    phase_load_up <= 1'b0;
                    phase_load_down <= 1'b0;
                    scan_status <= {1'b1, current_phase[6:0]};  // busy=1
                    state <= ST_WAIT_READY;
                end
                
                ST_WAIT_READY: begin
                    if (phase_ready_up && phase_ready_down) begin
                        state <= ST_RESET_LOW;
                    end
                end
                
                ST_RESET_LOW: begin
                    tdc_reset_trigger <= 1'b0;
                    counter <= counter + 1'b1;
                    
                    if (counter >= 16'd100) begin    // 等待 ~0.38us @ 260MHz (100 cycles)
                        counter <= 16'd0;
                        state <= ST_TRIGGER_UP;
                    end
                end
                
                ST_TRIGGER_UP: begin
                    trigger_up <= channel_sel[1];    // UP 信号
                    state <= ST_WAIT_UP;
                end
                
                ST_WAIT_UP: begin
                    counter <= counter + 1'b1;

                    if (counter >= 16'd0) begin    // 等待 ~3.8ns @ 260MHz
                        trigger_up <= 1'b0;
                        counter <= 16'd0;
                        state <= ST_TRIGGER_DOWN;
                    end
                end
                
                ST_TRIGGER_DOWN: begin
                    counter <= counter + 1'b1;

                    if(counter >= 16'd20)begin   // 等待 ~77ns @ 260MHz
                        trigger_down <= channel_sel[0];    // DOWN 信号
                        counter <= 16'd0;
                        state <= ST_WAIT_DOWN;
                    end
                end
                
                ST_WAIT_DOWN: begin
                    counter <= counter + 1'b1;
                    
                    if (counter >= 16'd0) begin    // 等待 ~3.8ns @ 260MHz
                        trigger_down <= 1'b0;
                        counter <= 16'd0;
                        state <= ST_RESET_HIGH;
                    end
                end
                
                ST_RESET_HIGH: begin
                    counter <= counter + 1'b1;
                    
                    if (counter >= 16'd20) begin    // 等待 ~77ns @ 260MHz
                        tdc_reset_trigger <= 1'b1;
                        counter <= 16'd0;
                        
                        // 根据模式决定下一步
                        if (scan_mode) begin
                            // 全扫描模式，继续下一个相位
                            state <= ST_SCAN_NEXT;
                        end
                        else begin
                            // 单步模式，完成
                            state <= ST_DONE;
                        end
                    end
                end
                
                ST_SCAN_NEXT: begin
                    counter <= counter + 1'b1;
                    
                    // 等待一段时间再进行下一次扫描
                    if (counter >= 16'd100) begin   // 等待 ~0.38us @ 260MHz
                        counter <= 16'd0;
                        
                        if (current_phase >= target_phase) begin
                            // 已经完成了相位0~target_phase的测试，结束扫描
                            state <= ST_DONE;
                        end
                        else begin
                            // 准备下一个相位
                            current_phase <= current_phase + 1'b1;
                            
                            // 继续下一个相位
                            phase_value_up <= current_phase + 1'b1;
                            phase_value_down <= current_phase + 1'b1 + down_phase_offset;
                            phase_load_up <= 1'b1;
                            phase_load_down <= 1'b1;
                            state <= ST_LOAD_PHASE;
                        end
                    end
                end
                
                ST_DONE: begin
                    scan_running <= 1'b0;
                    scan_status <= {1'b0, current_phase[6:0]};
                    
                    // 等待一段时间后返回 IDLE
                    counter <= counter + 1'b1;
                    if (counter >= 16'd50) begin
                        counter <= 16'd0;
                        state <= ST_IDLE;
                    end
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end

    // ila_3  tdc_scan_ctrl_debug(
    // .clk(clk_260MHz),   
    // .probe0({   
    //     scan_mode,              // 1位
    //     channel_sel,            // 2位
    //     target_phase,           // 8位
    //     current_phase,           // 8位
    //     phase_value_up,         // 8位
    //     phase_value_down,       // 8位
    //     trigger_up,              // 1位
    //     trigger_down            // 1位
    //     })             
    // );

endmodule
