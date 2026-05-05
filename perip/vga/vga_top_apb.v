module vga_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  reg [23:0] vga_data[0:0'h7ffff];
  parameter    h_frontporch = 96;
  parameter    h_active = 144;
  parameter    h_backporch = 784;
  parameter    h_total = 800;

  parameter    v_frontporch = 2;
  parameter    v_active = 35;
  parameter    v_backporch = 515;
  parameter    v_total = 525;

  //像素计数值
  reg [9:0]    x_cnt;
  reg [9:0]    y_cnt;
  wire         h_valid;
  wire         v_valid;

  always @(posedge clock) begin//行像素计数
      if (reset == 1'b1)
        x_cnt <= 1;
      else
      begin
        if (x_cnt == h_total)
            x_cnt <= 1;
        else
            x_cnt <= x_cnt + 10'd1;
      end
  end

  always @(posedge clock)  begin//列像素计数
      if (reset == 1'b1)
        y_cnt <= 1;
      else
      begin
        if (y_cnt == v_total & x_cnt == h_total)
            y_cnt <= 1;
        else if (x_cnt == h_total)
            y_cnt <= y_cnt + 10'd1;
      end
  end

  reg [18:0] addr_cnt;

  always @(posedge clock)  begin//列像素计数
      if (reset == 1'b1)
        addr_cnt <= 0;
      else
      begin
        if ((y_cnt > v_active) & (y_cnt <= v_backporch) & (x_cnt > h_active) & (x_cnt <= h_backporch))
            addr_cnt <= addr_cnt + 1;
        else if (y_cnt == v_total & x_cnt == h_total)
            addr_cnt <= 0;
      end
  end

  //生成同步信号
  assign vga_hsync = (x_cnt > h_frontporch);
  assign vga_vsync = (y_cnt > v_frontporch);
  //生成消隐信号
  assign h_valid = (x_cnt > h_active) & (x_cnt <= h_backporch);
  assign v_valid = (y_cnt > v_active) & (y_cnt <= v_backporch);
  assign vga_valid = h_valid & v_valid;
  //设置输出的颜色值
  assign vga_r = vga_data[addr_cnt][23:16];
  assign vga_g = vga_data[addr_cnt][15:8];
  assign vga_b = vga_data[addr_cnt][7:0];

  assign in_pslverr = 0;
  reg [1:0] state;
  localparam IDLE = 2'd0, WRITE=2'd1, READ=2'd2;

  always @(posedge clock) begin
    if (reset) begin
      state <= IDLE;
    end
    else begin
      case (state)
        IDLE: begin
          if (in_psel) begin
            state <= in_pwrite ? WRITE : READ;
          end
        end
        WRITE: begin
          if (in_pstrb[0])
            vga_data[in_paddr[20:2]][7:0] <= in_pwdata[7:0];
          if (in_pstrb[1])
            vga_data[in_paddr[20:2]][15:8] <= in_pwdata[15:8];
          if (in_pstrb[2])
            vga_data[in_paddr[20:2]][23:16] <= in_pwdata[23:16];
          state <= IDLE;
        end
        READ: begin
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

assign in_prdata = (state==READ) ? {8'b0, vga_data[in_paddr[20:2]]} : 0;
assign in_pready = (state==READ) | (state==WRITE);
endmodule
