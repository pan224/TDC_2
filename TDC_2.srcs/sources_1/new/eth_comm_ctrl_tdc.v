// ============================================================================
// 双通道以太网通信控制模块 - TDC专用版 (使用异步FIFO进行CDC)
// ============================================================================
// 处理 UP 和 DOWN 两个通道的时间戳数据
// 跨时钟域：260MHz (TDC) -> 200MHz (以太网)
// 参考tdc_wrapper.v使用异步FIFO进行CDC处理
// ============================================================================

`timescale 1ns / 1ps

module eth_comm_ctrl_tdc #(
    parameter FINE_BITS = 13,       // 精细时间位宽
    parameter COARSE_BITS = 16      // 粗计数位宽
)(
    // ========================================================================
    // 时钟和复位
    // ========================================================================
    input wire                      clk_200MHz,     // 以太网时钟域
    input wire                      clk_260MHz,     // TDC 时钟域
    input wire                      rst_200MHz,
    input wire                      rst_260MHz,
    
    // ========================================================================
    // UP 通道数据输入 (260MHz 域)
    // ========================================================================
    input wire                      up_valid,
    input wire [FINE_BITS-1:0]      up_fine,        // 精细时间
    input wire [COARSE_BITS-1:0]    up_coarse,      // 粗计数
    input wire [7:0]                up_id,          // 测量ID
    
    // ========================================================================
    // DOWN 通道数据输入 (260MHz 域)
    // ========================================================================
    input wire                      down_valid,
    input wire [FINE_BITS-1:0]      down_fine,
    input wire [COARSE_BITS-1:0]    down_coarse,
    input wire [7:0]                down_id,
    
    // ========================================================================
    // 以太网 FIFO 接口 (200MHz 域)
    // ========================================================================
    // TX FIFO
    output wire                     gig_eth_tx_fifo_wrclk,
    input wire                      gig_eth_tx_fifo_full,
    output reg [31:0]               gig_eth_tx_fifo_q,
    output reg                      gig_eth_tx_fifo_wren,
    
    // RX FIFO
    output wire                     gig_eth_rx_fifo_rdclk,
    input wire                      gig_eth_rx_fifo_empty,
    input wire [31:0]               gig_eth_rx_fifo_q,
    output reg                      gig_eth_rx_fifo_rden,
    
    // ========================================================================
    // 状态和控制
    // ========================================================================
    input wire                      system_ready,
    
    // 校准控制输出
    output reg                      manual_calib_trigger,
    
    // 扫描测试控制输出
    output reg                      scan_cmd_trigger,
    output reg [10:0]                scan_cmd_param
);

    // ========================================================================
    // 数据包格式定义
    // ========================================================================
    // [31:30] = 数据类型 (2'b00=UP, 2'b01=DOWN, 2'b10=保留, 2'b11=控制)
    // [29:22] = 测量ID (8位)
    // [21:9]  = 精细时间 [12:0]
    // [8:0]   = 粗计数低9位
    
    localparam TYPE_UP   = 2'b00;
    localparam TYPE_DOWN = 2'b01;
    localparam TYPE_INFO = 2'b10;
    localparam TYPE_CMD  = 2'b11;
    
    // 时钟域分配
    assign gig_eth_tx_fifo_wrclk = clk_200MHz;
    assign gig_eth_rx_fifo_rdclk = clk_200MHz;
    
    // ========================================================================
    // UP 通道异步FIFO - CDC处理（260MHz -> 200MHz）
    // ========================================================================
    // FIFO数据格式：{id[7:0], coarse[15:0], fine[12:0]} = 37位，使用64位FIFO
    wire [63:0] up_fifo_din, up_fifo_dout;
    wire        up_fifo_full, up_fifo_empty;
    wire        up_fifo_rden;
    wire [3:0]  up_fifo_unused0;
    wire [8:0]  up_fifo_unused1, up_fifo_unused2;
    
    // 打包数据（260MHz域）
    assign up_fifo_din = {
        26'b0,                          // [63:38] 填充
        1'b1,                           //[37] up通道标记
        up_id,                          // [36:29]
        up_coarse,                      // [28:13]
        up_fine                         // [12:0]
    };
    
    // 异步FIFO实例 - UP通道
    FIFO_DUALCLOCK_MACRO #(
        .DATA_WIDTH(64),
        .FIFO_SIZE("36Kb"),
        .FIRST_WORD_FALL_THROUGH("TRUE")
    ) up_async_fifo (
        .WRCLK(clk_260MHz),
        .RDCLK(clk_200MHz),
        .RST(rst_200MHz | rst_260MHz),
        .DI(up_fifo_din),
        .WREN(up_valid),                // 260MHz域写入
        .DO(up_fifo_dout),
        .RDEN(up_fifo_rden),            // 200MHz域读取
        .EMPTY(up_fifo_empty),
        .FULL(up_fifo_full),
        .ALMOSTEMPTY(up_fifo_unused0[0]),
        .ALMOSTFULL(up_fifo_unused0[1]),
        .RDERR(up_fifo_unused0[2]),
        .WRERR(up_fifo_unused0[3]),
        .RDCOUNT(up_fifo_unused1),
        .WRCOUNT(up_fifo_unused2)
    );
    
    // 解包数据（200MHz域）
    wire [7:0]              up_id_200;
    wire [COARSE_BITS-1:0]  up_coarse_200;
    wire [FINE_BITS-1:0]    up_fine_200;
    wire flag_up_channel;
    assign flag_up_channel = up_fifo_dout[37];
    assign up_id_200     = up_fifo_dout[36:29];
    assign up_coarse_200 = up_fifo_dout[28:13];
    assign up_fine_200   = up_fifo_dout[12:0];
    
    // ========================================================================
    // DOWN 通道异步FIFO - CDC处理（260MHz -> 200MHz）
    // ========================================================================
    wire [63:0] down_fifo_din, down_fifo_dout;
    wire        down_fifo_full, down_fifo_empty;
    wire        down_fifo_rden;
    wire [3:0]  down_fifo_unused0;
    wire [8:0]  down_fifo_unused1, down_fifo_unused2;
    
    // 打包数据（260MHz域）
    assign down_fifo_din = {
        26'b0,                          // [63:38] 填充
        1'b0,                           //[37] down通道标记
        down_id,                        // [36:29]
        down_coarse,                    // [28:13]
        down_fine                       // [12:0]
    };
    
    // 异步FIFO实例 - DOWN通道
    FIFO_DUALCLOCK_MACRO #(
        .DATA_WIDTH(64),
        .FIFO_SIZE("36Kb"),
        .FIRST_WORD_FALL_THROUGH("TRUE")
    ) down_async_fifo (
        .WRCLK(clk_260MHz),
        .RDCLK(clk_200MHz),
        .RST(rst_200MHz | rst_260MHz),
        .DI(down_fifo_din),
        .WREN(down_valid),              // 260MHz域写入
        .DO(down_fifo_dout),
        .RDEN(down_fifo_rden),          // 200MHz域读取
        .EMPTY(down_fifo_empty),
        .FULL(down_fifo_full),
        .ALMOSTEMPTY(down_fifo_unused0[0]),
        .ALMOSTFULL(down_fifo_unused0[1]),
        .RDERR(down_fifo_unused0[2]),
        .WRERR(down_fifo_unused0[3]),
        .RDCOUNT(down_fifo_unused1),
        .WRCOUNT(down_fifo_unused2)
    );
    
    // 解包数据（200MHz域）
    wire [7:0]              down_id_200;
    wire [COARSE_BITS-1:0]  down_coarse_200;
    wire [FINE_BITS-1:0]    down_fine_200;
    wire flag_down_channel;
    assign flag_down_channel = down_fifo_dout[37];
    assign down_id_200     = down_fifo_dout[36:29];
    assign down_coarse_200 = down_fifo_dout[28:13];
    assign down_fine_200   = down_fifo_dout[12:0];
    
    // ========================================================================
    // 发送状态机（200MHz 域）- 从异步FIFO读取并发送
    // ========================================================================
    localparam TX_IDLE  = 2'd0;
    localparam TX_SEND  = 2'd1;
    localparam TX_WAIT  = 2'd2;
    localparam TX_DONE  = 2'd3;  // 新增：等待FIFO状态稳定
    
    reg [1:0] tx_state;
    reg up_fifo_rden_reg, down_fifo_rden_reg;
    
    // FIFO读使能信号 - FIRST_WORD_FALL_THROUGH模式下，数据立即可用
    assign up_fifo_rden   = up_fifo_rden_reg;
    assign down_fifo_rden = down_fifo_rden_reg;
    
    reg send_up;  // 标记当前发送的是UP还是DOWN
    
    always @(posedge clk_200MHz) begin
        if (rst_200MHz) begin
            tx_state <= TX_IDLE;
            gig_eth_tx_fifo_wren <= 1'b0;
            gig_eth_tx_fifo_q <= 32'b0;
            send_up <= 1'b0;
            up_fifo_rden_reg <= 1'b0;
            down_fifo_rden_reg <= 1'b0;
        end
        else begin
            // 默认值
            up_fifo_rden_reg <= 1'b0;
            down_fifo_rden_reg <= 1'b0;
            
            case (tx_state)
                TX_IDLE: begin
                    gig_eth_tx_fifo_wren <= 1'b0;
                    
                    // UP 通道有数据（优先级高）
                    if (!up_fifo_empty && !gig_eth_tx_fifo_full) begin
                        // FWFT模式：empty=0时数据已在dout可用，不要立即rden
                        send_up <= 1'b1;
                        tx_state <= TX_SEND;
                    end
                    // DOWN 通道有数据（UP为空时）
                    else if (!down_fifo_empty && !gig_eth_tx_fifo_full) begin
                        // FWFT模式：empty=0时数据已在dout可用，不要立即rden
                        send_up <= 1'b0;
                        tx_state <= TX_SEND;
                    end
                end
                
                TX_SEND: begin
                    // FIRST_WORD_FALL_THROUGH模式：数据已经可用，先准备数据
                    if (send_up) begin
                        gig_eth_tx_fifo_q <= {
                            TYPE_UP,                    // [31:30]
                            up_id_200,                  // [29:22]
                            up_fine_200,                // [21:9]
                            flag_up_channel,            // [8] UP通道标志(期望1)
                            up_coarse_200[7:0]          // [7:0]coarse
                        };
                    end else begin
                        gig_eth_tx_fifo_q <= {
                            TYPE_DOWN,                  // [31:30]
                            down_id_200,                // [29:22]
                            down_fine_200,              // [21:9]
                            flag_down_channel,          // [8] DOWN通道标志(期望0)
                            down_coarse_200[7:0]        // [7:0]coarse
                        };
                    end
                    // 数据准备好，下一周期写入
                    tx_state <= TX_WAIT;
                end
                
                TX_WAIT: begin
                    // 数据已稳定，拉高wren写入以太网FIFO
                    gig_eth_tx_fifo_wren <= 1'b1;
                    
                    // 同时弹出已处理的CDC FIFO数据
                    if (send_up) begin
                        up_fifo_rden_reg <= 1'b1;
                    end else begin
                        down_fifo_rden_reg <= 1'b1;
                    end
                    
                    tx_state <= TX_DONE;  // 先进入DONE状态等待FIFO稳定
                end
                
                TX_DONE: begin
                    // 等待一个周期让FIFO的empty信号更新
                    gig_eth_tx_fifo_wren <= 1'b0;
                    tx_state <= TX_IDLE;
                end
                
                default: begin
                    gig_eth_tx_fifo_wren <= 1'b0;
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end
    
    // ========================================================================
    // 接收状态机（200MHz 域）- 命令解析
    // ========================================================================
    /*
    gig_eth_rx_fifo_q  数据格式：
    [31]     : 1=重新校准; 0=扫描测试
    [30]     : 扫描模式 (0=单步, 1=全扫描)
    [29:28]  : 通道选择 (00=无, 10=UP, 01=DOWN, 11=UP+DOWN)
    [27:20]  : 相位参数（8位）
    [19:0]   : 保留
    
    scan_cmd_param 输出格式（11位）：
    [10]     : 扫描模式 (0=单步, 1=全扫描)
    [9:8]    : 通道选择 (00=无, 10=UP, 01=DOWN, 11=UP+DOWN)
    [7:0]    : 相位参数
    */
    
    // FWFT 模式：empty=0 时数据立即可用，rden=1 弹出当前数据
    localparam RX_IDLE      = 3'd0;
    localparam RX_READ_DATA = 3'd1;
    localparam RX_RESET     = 3'd2;//校准
    localparam RX_EN        = 3'd3;
    localparam RX_DONE      = 3'd5;  
    
    reg [2:0] rx_state;
    
    always @(posedge clk_200MHz) begin
        if (rst_200MHz) begin
            rx_state <= RX_IDLE;
            gig_eth_rx_fifo_rden <= 1'b0;
            manual_calib_trigger <= 1'b0;
            scan_cmd_trigger <= 1'b0;
            scan_cmd_param <= 11'b0;  // 修正：11位清零
        end
        else begin
            case (rx_state)
                RX_IDLE: begin
                    gig_eth_rx_fifo_rden <= 1'b0;
                    // 默认清除脉冲信号
                    manual_calib_trigger <= 1'b0;
                    scan_cmd_trigger <= 1'b0;
                    
                    // FWFT 模式：empty=0 时数据已在 q 端口可用
                    if (!gig_eth_rx_fifo_empty) begin
                        rx_state <= RX_READ_DATA;
                        // 读取数据
                    end
                end
                
                RX_READ_DATA: begin
                    case (gig_eth_rx_fifo_q[31])
                        1'b1: begin
                            // 重新校准命令
                            manual_calib_trigger <= 1'b1;
                            rx_state <= RX_RESET;  
                        end
                        1'b0: begin
                            // 扫描模式：提取 [30:20] 共 11 位
                            scan_cmd_param <= gig_eth_rx_fifo_q[30:20];
                            scan_cmd_trigger <= 1'b1;
                            rx_state <= RX_EN;  
                        end
                        default: begin
                            // 不应到达此处
                        end
                    endcase
                end
                RX_RESET: begin
                    manual_calib_trigger <= 1'b0;
                    gig_eth_rx_fifo_rden <= 1'b1; // 弹出数据
                    rx_state <= RX_DONE;
                end
                RX_EN: begin
                    gig_eth_rx_fifo_rden <= 1'b1; // 弹出数据
                    scan_cmd_trigger <= 1'b0; // 保持一个周期
                    rx_state <= RX_DONE;
                end
                
                RX_DONE: begin
                    gig_eth_rx_fifo_rden <= 1'b0;
                    rx_state <= RX_IDLE;
                end
                
                default: begin
                    gig_eth_rx_fifo_rden <= 1'b0;
                    manual_calib_trigger <= 1'b0;
                    scan_cmd_trigger <= 1'b0;
                    scan_cmd_param <= 11'b0;
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end


    // ila_2 ila_eth_comm_ctrl_tdc (
    //     .clk(clk_200MHz),
    //     .probe0({
    //         scan_cmd_param,
    //         scan_cmd_trigger
    //     })
    // );

endmodule
