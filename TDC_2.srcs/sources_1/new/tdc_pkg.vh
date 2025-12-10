// ============================================================================
// TDC Package - Verilog Header File
// ============================================================================
// 包含常量定义、参数和函数
// 从VHDL tdc_pkg.vhd转换而来
// ============================================================================

`ifndef TDC_PKG_VH
`define TDC_PKG_VH

`timescale 1ns / 1ps

// ============================================================================
// 常量定义
// ============================================================================
`define DEPTH           24          // 可采样的Carry Chain深度
`define HIST_SIZE       262144      // 2^18 直方图大小
`define CLK_IN_PS       3864        // 初始时钟周期(皮秒)
`define PE_INTBITS      9           // 优先编码器内部位宽
`define CALIB_DEADTIME  8           // 校准死区时间
`define RO_LENGTH       55          // 环形振荡器长度(奇数)
`define SIM             0           // 仿真标志 (0=False, 1=True)
`define SIM_OFFSET      510         // 仿真偏移

// 计算常量
`define BINS_WIDTH      (`DEPTH * 4)        // 96 bits
`define HIST_ADDR_WIDTH 10                  // log2(DEPTH*4*4) = log2(384)
`define LUT_ADDR_WIDTH  10                  // 查找表地址宽度

// ============================================================================
// 函数定义
// ============================================================================

// 对数函数 - 计算log2(i)
function integer log2;
    input integer value;
    integer temp;
    begin
        log2 = 0;
        temp = value;
        while (temp > 1) begin
            log2 = log2 + 1;
            temp = temp / 2;
        end
    end
endfunction

// 查找最高有效位 - 统计1的个数
function integer find_msb;
    input [11:0] value;
    integer i;
    begin
        find_msb = 0;
        for (i = 0; i < 12; i = i + 1) begin
            if (value[i]) begin
                find_msb = find_msb + 1;
            end
        end
    end
endfunction

// 温度计码转独热码
function [15:0] therm2onehot;
    input [16:0] therm;
    integer i;
    begin
        therm2onehot = 16'b0;
        for (i = 0; i < 16; i = i + 1) begin
            if (therm[i] && !therm[i+1]) begin
                therm2onehot[i] = 1'b1;
            end
        end
    end
endfunction

// 独热码转二进制
function [3:0] onehot2bin;
    input [15:0] onehot;
    integer i;
    begin
        onehot2bin = 4'b0;
        for (i = 0; i < 16; i = i + 1) begin
            if (onehot[i]) begin
                onehot2bin = onehot2bin | (i + 1);
            end
        end
    end
endfunction

// 数据传播(移位) - 左移一位，LSB补0
function [3:0] prop;
    input [3:0] slv;
    begin
        prop = {slv[2:0], 1'b0};
    end
endfunction

`endif // TDC_PKG_VH
