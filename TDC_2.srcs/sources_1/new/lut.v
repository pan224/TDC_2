// ============================================================================
// Look-Up Table (LUT) Module
// ============================================================================
// 查找表校准模块 - 通过直方图校准补偿延迟线非线性
// 从VHDL lut.vhd转换而来
// ============================================================================

`timescale 1ns / 1ps
`include "tdc_pkg.vh"

module lut #(
    parameter CH = "ch1"                // 通道标识
)(
    input  wire                     CLK,
    input  wire                     RST,
    // 输入接口
    input  wire                     valid_in,
    input  wire                     calib_flag,
    input  wire [`PE_INTBITS-1:0]  bin_in,
    // 输出接口
    output wire [17:0]              data_out,
    output reg                      init
);

    // ========================================================================
    // 状态机定义
    // ========================================================================
    localparam STATE_CLEAR  = 2'b00;
    localparam STATE_RUN    = 2'b01;
    localparam STATE_CONFIG = 2'b10;
    
    reg [1:0] state;

    // ========================================================================
    // 内部信号
    // ========================================================================
    // 直方图BRAM信号
    reg  [17:0] hist_di;
    wire [17:0] hist_do;
    reg  [9:0]  hist_wa, hist_ra;
    reg         hist_we, hist_re;
    
    // 查找表BRAM信号
    wire [17:0] lut_do;
    reg  [17:0] lut_di;
    reg  [9:0]  lut_wa;
    wire [9:0]  lut_ra;
    wire        lut_re;
    reg         lut_we;
    
    // 控制信号
    reg [17:0]  hit_cnt;                // 命中计数器
    reg [9:0]   clear_cnt;              // 清零计数器
    reg         mempage;                // LUT存储页选择
    reg         wait1;                  // 等待标志
    
    // 配置流水线
    reg [8:0]   confpipe_cnt [2:0];     // 配置计数器流水线
    reg [2:0]   confpipe_valid;         // 配置有效标志流水线
    
    // 累加和
    reg [17:0]  sum;
    
    // 地址流水线
    reg [9:0]   ap0, ap1;

    // ========================================================================
    // LUT读取接口 (对应VHDL的并发信号赋值)
    // ========================================================================
    // lut.ra <= s.mempage & std_logic_vector(d.bin);
    // lut.re <= d.valid;
    // q.data <= unsigned(lut.do);
    assign lut_ra = {mempage, bin_in};
    assign lut_re = valid_in;
    assign data_out = lut_do;

    // ========================================================================
    // 主状态机
    // ========================================================================
    always @(posedge CLK) begin
        if (RST) begin
            state           <= STATE_CLEAR;
            init            <= 1'b0;
            mempage         <= 1'b0;
            hist_we         <= 1'b0;
            hist_re         <= 1'b0;
            lut_we          <= 1'b0;
            clear_cnt       <= 10'b0;
            hit_cnt         <= 18'b0;
            wait1           <= 1'b0;
            sum             <= 18'b0;
            confpipe_cnt[0] <= 9'b0;
            confpipe_cnt[1] <= 9'b0;
            confpipe_cnt[2] <= 9'b0;
            confpipe_valid  <= 3'b0;
            ap0             <= 10'b0;
            ap1             <= 10'b0;
            
        end else begin
            // 默认值 (对应VHDL process开头的defaults)
            // VHDL: hist.we <= '0'; hist.re <= '0'; lut.we <= '0';
            //       s.sum <= (s.sum'range => '0'); -- 只在非CONFIG状态清零
            //       s.clear_cnt <= (others => '0'); -- 只在非CLEAR状态清零
            //       s.wait1 <= '0';
            hist_we    <= 1'b0;
            hist_re    <= 1'b0;
            lut_we     <= 1'b0;
            clear_cnt  <= 10'b0;
            wait1      <= 1'b0;
            // 注意: sum不在这里清零,在CONFIG状态外才清零
            
            case (state)
                // ============================================================
                // CLEAR状态: 清零直方图
                // ============================================================
                STATE_CLEAR: begin
                    // 对应VHDL: s.hit_cnt <= (others => '0');
                    hit_cnt     <= 18'b0;
                    sum         <= 18'b0;  // 清零累加和
                    hist_wa     <= clear_cnt;
                    hist_di     <= 18'b0;
                    hist_we     <= 1'b1;
                    
                    // 对应VHDL: s.clear_cnt <= s.clear_cnt+1 (在默认值被覆盖)
                    clear_cnt   <= clear_cnt + 1;
                    
                    if (clear_cnt == (`DEPTH * 4 * 4)) begin
                        state     <= STATE_RUN;
                    end
                end
                
                // ============================================================
                // RUN状态: 累积直方图
                // ============================================================
                STATE_RUN: begin
                    sum <= 18'b0;  // 确保sum在RUN状态清零
                    
                    // 只处理校准数据
                    // 对应VHDL: if d.valid='1' and d.calib_flag='1' and hist.re='0' and s.wait1='0'
                    if (valid_in && calib_flag && !hist_re && !wait1) begin
                        hist_ra <= {1'b0, bin_in};
                        ap0     <= {1'b0, bin_in};
                        hist_re <= 1'b1;
                    end
                    
                    // 对应VHDL: s.wait1 <= hist.re; s.ap1 <= s.ap0;
                    wait1 <= hist_re;
                    ap1   <= ap0;
                    
                    // 更新直方图
                    if (wait1) begin
                        hist_we <= 1'b1;
                        hist_wa <= ap1;
                        hist_di <= hist_do + 1;
                        
                        if (hit_cnt == `HIST_SIZE - 2) begin
                            state            <= STATE_CONFIG;
                            hit_cnt          <= 18'b0;
                            confpipe_cnt[0]  <= 9'b0;
                            confpipe_cnt[1]  <= 9'b0;
                            confpipe_cnt[2]  <= 9'b0;
                            confpipe_valid   <= 3'b0;
                        end else begin
                            hit_cnt <= hit_cnt + 1;
                        end
                    end
                end
                
                // ============================================================
                // CONFIG状态: 生成LUT(累积分布函数)
                // ============================================================
                STATE_CONFIG: begin
                    // 第一级流水线: 读直方图地址
                    // 对应VHDL: s.confpipe(0).cnt <= s.confpipe(0).cnt+1;
                    //           s.confpipe(0).valid <= '1';
                    confpipe_cnt[0]   <= confpipe_cnt[0] + 1;
                    confpipe_valid[0] <= 1'b1;
                    hist_ra           <= {1'b0, confpipe_cnt[0]};
                    hist_re           <= 1'b1;
                    
                    // 第二级流水线: 读取数据
                    // 对应VHDL: s.confpipe(1) <= s.confpipe(0);
                    confpipe_cnt[1]   <= confpipe_cnt[0];
                    confpipe_valid[1] <= confpipe_valid[0];
                    
                    // 第三级流水线: 累加并写入LUT
                    // 对应VHDL: s.confpipe(2) <= s.confpipe(1);
                    confpipe_cnt[2]   <= confpipe_cnt[1];
                    confpipe_valid[2] <= confpipe_valid[1];
                    
                    // 关键: sum在CONFIG状态持续累加,不能被默认值清零!
                    // 对应VHDL: if s.confpipe(2).valid = '1' then
                    //             s.sum <= s.sum + unsigned(hist.do);
                    //             lut.di <= std_logic_vector(s.sum + shift_right(unsigned(hist.do),1));
                    if (confpipe_valid[2]) begin
                        sum    <= sum + hist_do;            // 累积分布函数累加
                        lut_di <= sum + (hist_do >> 1);     // sum + hist_do/2
                        lut_wa <= {~mempage, confpipe_cnt[2]};  // 写入非活动页
                        lut_we <= 1'b1;
                    end
                    
                    // 配置完成
                    if (confpipe_cnt[2] == (`DEPTH * 4 * 4)) begin
                        state   <= STATE_CLEAR;
                        mempage <= ~mempage;    // 切换存储页
                        init    <= 1'b1;        // 标记初始化完成
                    end
                end
                
                default: begin
                    state <= STATE_CLEAR;
                end
            endcase
        end
    end

    // ========================================================================
    // 直方图BRAM实例化 (18Kb双端口)
    // ========================================================================
    BRAM_SDP_MACRO #(
        .BRAM_SIZE("18Kb"),
        .DEVICE("7SERIES"),
        .WRITE_WIDTH(18),
        .READ_WIDTH(18),
        .DO_REG(0),
        .INIT(18'h00000),
        .INIT_FILE("NONE"),
        .WRITE_MODE("READ_FIRST"),
        .SIM_COLLISION_CHECK("ALL")
    ) hist_bram (
        .DO(hist_do),
        .DI(hist_di),
        .RDADDR(hist_ra),
        .RDCLK(CLK),
        .RDEN(hist_re),
        .REGCE(1'b1),
        .RST(RST),
        .WE(2'b11),
        .WRADDR(hist_wa),
        .WRCLK(CLK),
        .WREN(hist_we)
    );

    // ========================================================================
    // 查找表BRAM实例化 (18Kb双端口)
    // ========================================================================
    BRAM_SDP_MACRO #(
        .BRAM_SIZE("18Kb"),
        .DEVICE("7SERIES"),
        .WRITE_WIDTH(18),
        .READ_WIDTH(18),
        .DO_REG(0),
        .INIT(18'h00000),
        .INIT_FILE("NONE"),
        .WRITE_MODE("READ_FIRST"),
        .SIM_COLLISION_CHECK("ALL")
    ) lut_bram (
        .DO(lut_do),
        .DI(lut_di),
        .RDADDR(lut_ra),
        .RDCLK(CLK),
        .RDEN(lut_re),
        .REGCE(1'b1),
        .RST(RST),
        .WE(2'b11),
        .WRADDR(lut_wa),
        .WRCLK(CLK),
        .WREN(lut_we)
    );

endmodule
