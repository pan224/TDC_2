// ============================================================================
// TDC 以太网测试顶层模块
// ============================================================================
// 整合 TDC 测量系统与以太网通信
// 基于原 test.v 架构，增加双通道 TDC 测量功能
// ============================================================================

`timescale 1ns / 1ps

module test_tdc_eth(
    input wire CPU_RESET,
    input wire SYS_CLK_P,           // 200MHz 差分时钟
    input wire SYS_CLK_N,

    // ========================================================================
    // 以太网接口
    // ========================================================================
    input wire SGMIICLK_Q0_P,
    input wire SGMIICLK_Q0_N,
    output wire PHY_RESET_N,
    output wire [3:0] RGMII_TXD,
    output wire RGMII_TX_CTL,
    output wire RGMII_TXC,
    input wire [3:0] RGMII_RXD,
    input wire RGMII_RX_CTL,
    input wire RGMII_RXC,
    inout wire MDIO,
    output wire MDC
);

    // ========================================================================
    // 内部信号声明
    // ========================================================================
    wire reset, sys_clk;
    wire clk_50MHz, clk_100MHz, clk_10MHz, clk_250MHz;
    wire clk_sgmii_i, clk_125MHz;
    
    // 以太网信号
    wire [7:0] gig_eth_tx_tdata, gig_eth_rx_tdata;
    wire gig_eth_tx_tvalid, gig_eth_rx_tvalid;
    wire gig_eth_tx_tready, gig_eth_rx_tready;
    wire gig_eth_tcp_use_fifo;
    wire gig_eth_tx_fifo_wrclk;
    wire [31:0] gig_eth_tx_fifo_q;
    wire gig_eth_tx_fifo_wren;
    wire gig_eth_tx_fifo_full;
    wire gig_eth_rx_fifo_rdclk;
    wire [31:0] gig_eth_rx_fifo_q;
    wire gig_eth_rx_fifo_rden;
    wire gig_eth_rx_fifo_empty;
    wire [31:0] set_ipv4_addr;
    
    // TDC 状态
    wire tdc_ready;
    wire [7:0] tdc_status;

    // ========================================================================
    // 时钟和复位生成
    // ========================================================================
    global_clock_reset global_clock_reset_inst (
        .SYS_CLK_P(SYS_CLK_P),
        .SYS_CLK_N(SYS_CLK_N),
        .FORCE_RST(~CPU_RESET),
        // 输出
        .GLOBAL_RST(reset),
        .SYS_CLK(sys_clk),              // 200MHz
        .CLK_OUT1(clk_50MHz),
        .CLK_OUT2(clk_100MHz),
        .CLK_OUT3(clk_10MHz),
        .CLK_OUT4(clk_250MHz)
    );

    // ========================================================================
    // 以太网时钟生成 (125MHz)
    // ========================================================================
    IBUFDS_GTE2 #(
        .CLKCM_CFG("TRUE"),
        .CLKRCV_TRST("TRUE"),
        .CLKSWING_CFG(2'b11)
    ) IBUFDS_GTE2_inst (
        .O(clk_sgmii_i),
        .ODIV2(),
        .CEB(1'b0),
        .I(SGMIICLK_Q0_P),
        .IB(SGMIICLK_Q0_N)
    );
    
    BUFG BUFG_inst (
        .O(clk_125MHz),
        .I(clk_sgmii_i)
    );

    // ========================================================================
    // 以太网 IDELAYCTRL
    // ========================================================================
    (* IODELAY_GROUP = "tri_mode_ethernet_mac_iodelay_grp" *)
    IDELAYCTRL IDELAYCTRL_gbe_inst (
        .RDY(),
        .REFCLK(sys_clk),               // 200MHz
        .RST(reset)
    );

    // ========================================================================
    // 以太网配置
    // ========================================================================
    assign gig_eth_tcp_use_fifo = 1'b1;     // 使用 FIFO 模式
    assign set_ipv4_addr = {8'd192, 8'd168, 8'd2, 8'd100};  // IP: 192.168.2.100

    // ========================================================================
    // 以太网 MAC 模块
    // ========================================================================
    gig_eth gig_eth_inst (
        // 异步复位
        .GLBL_RST(reset),
        // 时钟
        .GTX_CLK(clk_125MHz),
        .REF_CLK(sys_clk),              // 200MHz for IODELAY
        // PHY 接口
        .PHY_RESETN(PHY_RESET_N),
        // RGMII 接口
        .RGMII_TXD(RGMII_TXD),
        .RGMII_TX_CTL(RGMII_TX_CTL),
        .RGMII_TXC(RGMII_TXC),
        .RGMII_RXD(RGMII_RXD),
        .RGMII_RX_CTL(RGMII_RX_CTL),
        .RGMII_RXC(RGMII_RXC),
        // MDIO 接口
        .MDIO(MDIO),
        .MDC(MDC),
        // TCP 流接口（未使用）
        .TCP_CONNECTION_RESET(1'b0),
        .TX_TDATA(gig_eth_tx_tdata),
        .TX_TVALID(gig_eth_tx_tvalid),
        .TX_TREADY(gig_eth_tx_tready),
        .RX_TDATA(gig_eth_rx_tdata),
        .RX_TVALID(gig_eth_rx_tvalid),
        .RX_TREADY(gig_eth_rx_tready),
        // FIFO 接口
        .TCP_USE_FIFO(gig_eth_tcp_use_fifo),
        .TX_FIFO_WRCLK(gig_eth_tx_fifo_wrclk),
        .TX_FIFO_Q(gig_eth_tx_fifo_q),
        .TX_FIFO_WREN(gig_eth_tx_fifo_wren),
        .TX_FIFO_FULL(gig_eth_tx_fifo_full),
        .RX_FIFO_RDCLK(gig_eth_rx_fifo_rdclk),
        .RX_FIFO_Q(gig_eth_rx_fifo_q),
        .RX_FIFO_RDEN(gig_eth_rx_fifo_rden),
        .RX_FIFO_EMPTY(gig_eth_rx_fifo_empty),
        .SET_IPv4_ADDR(set_ipv4_addr)
    );

    // ========================================================================
    // TDC 以太网集成系统
    // ========================================================================
    tdc_eth_integrated tdc_eth_system (
        // 系统时钟和复位
        .sys_clk_200MHz(sys_clk),       // 200MHz
        .sys_reset(reset),
        
        // TDC 测量信号（使用内部自测信号）
        .signal_up(1'b0),
        .signal_down(1'b0),
        .tdc_reset_trigger(1'b0),
        
        // 扫描测试使能（强制启用内部测试）
        .scan_test_en(1'b1),
        
        // 以太网 FIFO 接口（200MHz 时钟域）
        .gig_eth_tx_fifo_wrclk(gig_eth_tx_fifo_wrclk),
        .gig_eth_tx_fifo_full(gig_eth_tx_fifo_full),
        .gig_eth_tx_fifo_q(gig_eth_tx_fifo_q),
        .gig_eth_tx_fifo_wren(gig_eth_tx_fifo_wren),
        
        .gig_eth_rx_fifo_rdclk(gig_eth_rx_fifo_rdclk),
        .gig_eth_rx_fifo_empty(gig_eth_rx_fifo_empty),
        .gig_eth_rx_fifo_q(gig_eth_rx_fifo_q),
        .gig_eth_rx_fifo_rden(gig_eth_rx_fifo_rden),
        // 调试输出
        .tdc_ready_out(tdc_ready)
    );

    // ========================================================================
    // ILA 调试（可选）
    // ========================================================================
    
    // ila_0 ila_eth_debug (
    //     .clk(sys_clk),
    //     .probe0({
    //         gig_eth_rx_fifo_q,          // [31:0]
    //         gig_eth_tx_fifo_q,          // [31:0]
    //         gig_eth_tx_fifo_full,       // [0]
    //         gig_eth_rx_fifo_empty,      // [0]
    //         gig_eth_rx_fifo_rden,       // [0]
    //         gig_eth_tx_fifo_wren,       // [0]
    //         tdc_ready                   // [0]
    //     })
    // );
    

endmodule
