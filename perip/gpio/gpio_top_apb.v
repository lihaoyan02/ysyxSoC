module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

reg [15:0] gpio_out_reg;
reg [3:0] gpio_seg_reg [0:7];
wire [3:0] local_addr = {in_paddr[3:2],2'b0};
reg [7:0] gpio_seg_inter [0:7];
assign gpio_out = gpio_out_reg;
assign gpio_seg_0 = gpio_seg_inter[0];
assign gpio_seg_1 = gpio_seg_inter[1];
assign gpio_seg_2 = gpio_seg_inter[2];
assign gpio_seg_3 = gpio_seg_inter[3];
assign gpio_seg_4 = gpio_seg_inter[4];
assign gpio_seg_5 = gpio_seg_inter[5];
assign gpio_seg_6 = gpio_seg_inter[6];
assign gpio_seg_7 = gpio_seg_inter[7];
//APB
assign in_pslverr = 1'b0;
assign in_prdata = (state==READ) ? ((local_addr==4'h0) ? {16'b0, gpio_out_reg} :
                                    (local_addr==4'h4) ? {16'b0, gpio_in} :
            (local_addr==4'h8) ? {gpio_seg_reg[7],gpio_seg_reg[6],gpio_seg_reg[5],gpio_seg_reg[4],
                                  gpio_seg_reg[3],gpio_seg_reg[2],gpio_seg_reg[1],gpio_seg_reg[0]} :
                                  32'b0) : 32'b0;
assign in_pready = (state==READ) | (state==WRITE);

reg [1:0] state;
localparam IDLE = 2'd0, WRITE=2'd1, READ=2'd2;
always @(posedge clock) begin
  if (reset) begin
    state <= IDLE;
    gpio_out_reg <= 0;
    for (integer i = 0; i<8 ; i=i+1) begin
      gpio_seg_reg[i] <= 4'h0;
    end
  end
  else begin
    case (state)
      IDLE: begin
        if (in_psel) begin
          state <= in_pwrite ? WRITE : READ;
        end
      end
      WRITE: begin
        if (local_addr==4'h0) begin
          if (in_pstrb[0])
            gpio_out_reg[7:0] <= in_pwdata[7:0];
          if (in_pstrb[1])
            gpio_out_reg[15:8] <= in_pwdata[15:8];
        end
        else if (local_addr==4'h8) begin
          if (in_pstrb[0])
            {gpio_seg_reg[1],gpio_seg_reg[0]} <= in_pwdata[7:0];
          if (in_pstrb[1])
            {gpio_seg_reg[3],gpio_seg_reg[2]} <= in_pwdata[15:8];
          if (in_pstrb[2])
            {gpio_seg_reg[5],gpio_seg_reg[4]} <= in_pwdata[23:16];
          if (in_pstrb[3])
            {gpio_seg_reg[7],gpio_seg_reg[6]} <= in_pwdata[31:24];
        end
        state <= IDLE;
      end
      READ: begin
        state <= IDLE;
      end
      default: state <= IDLE;
    endcase
  end
end

generate
  genvar seg_num;
  for (seg_num = 0; seg_num<8 ; seg_num=seg_num+1) begin
    always @(*) begin
      case (gpio_seg_reg[seg_num])
        4'b0000: gpio_seg_inter[seg_num] = 8'b0000_0011;
        4'b0001: gpio_seg_inter[seg_num] = 8'b1001_1111;
        4'b0010: gpio_seg_inter[seg_num] = 8'b0010_0101;
        4'b0011: gpio_seg_inter[seg_num] = 8'b0000_1101;
        4'b0100: gpio_seg_inter[seg_num] = 8'b1001_1001;
        4'b0101: gpio_seg_inter[seg_num] = 8'b0100_1001;
        4'b0110: gpio_seg_inter[seg_num] = 8'b0100_0001;
        4'b0111: gpio_seg_inter[seg_num] = 8'b0001_1111;
        4'b1000: gpio_seg_inter[seg_num] = 8'b0000_0001;
        4'b1001: gpio_seg_inter[seg_num] = 8'b0000_1001;
        4'b1010: gpio_seg_inter[seg_num] = 8'b0001_0001; 
        4'b1011: gpio_seg_inter[seg_num] = 8'b1100_0001;
        4'b1100: gpio_seg_inter[seg_num] = 8'b0110_0011;
        4'b1101: gpio_seg_inter[seg_num] = 8'b1000_0101;
        4'b1110: gpio_seg_inter[seg_num] = 8'b0110_0001;
        4'b1111: gpio_seg_inter[seg_num] = 8'b0111_0001;
        default: gpio_seg_inter[seg_num] = 8'b1111_1111;
      endcase
    end
  end
endgenerate

endmodule
