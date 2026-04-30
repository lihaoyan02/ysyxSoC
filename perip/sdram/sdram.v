module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 3:0] dqm,
  inout [31:0] dq
);

sdram16b u_sdram1 (
  .clk(clk),
  .cke(cke),
  .cs(cs),
  .ras(ras),
  .cas(cas),
  .we(we),
  .a(a),
  .ba(ba),
  .dqm(dqm[1:0]),
  .dq(dq[15:0])
);

sdram16b u_sdram2 (
  .clk(clk),
  .cke(cke),
  .cs(cs),
  .ras(ras),
  .cas(cas),
  .we(we),
  .a(a),
  .ba(ba),
  .dqm(dqm[3:2]),
  .dq(dq[31:16])
);

endmodule

module sdram16b (
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);
localparam CMD_NOP           = 4'b0111;
localparam CMD_ACTIVE        = 4'b0011;
localparam CMD_READ          = 4'b0101;
localparam CMD_WRITE         = 4'b0100;
localparam CMD_TERMINATE     = 4'b0110;
localparam CMD_PRECHARGE     = 4'b0010;
localparam CMD_REFRESH       = 4'b0001;
localparam CMD_LOAD_MODE     = 4'b0000;

reg [12:0] mode_reg;
wire [2:0] cas_latency = mode_reg[6:4];
wire [2:0] burst_len = 3'b1; //3'b1 << mode_Reg[2:0];
reg [2:0] cnt;

localparam INIT=3'd0, IDLE = 3'd1, ACTIVE=3'd2, READ_WAIT = 3'd3, READ = 3'd4, WRITE = 3'd5;
wire [3:0] command_q = {cs,ras,cas,we};
reg [2:0] state, next_state;

reg [23:0] addr_buf;
reg [12:0] actived_row [3:0];
reg [1:0] dqm_buf;
reg [15:0] dq_buf;
reg [15:0] sdram_mem [(1<<24)-1:0];
// load mode
  always @(posedge clk) begin
    if (!cke) begin
      state <= INIT;
      mode_reg <= 0;
      addr_buf <= 0;
      actived_row[0] <= 0;
      actived_row[1] <= 0;
      actived_row[2] <= 0;
      actived_row[3] <= 0;
      cnt <= 0;
      dqm_buf <= 0;
      dq_buf <= 0;
    end
    else begin
      case (state)
        INIT: begin
          if (command_q==CMD_LOAD_MODE) begin
            mode_reg <= a;
            state <= IDLE;
          end
        end
        IDLE: begin
          if (command_q==CMD_ACTIVE) begin
            addr_buf[23:11] <= a; //addr row
            actived_row[ba] <= a;
            addr_buf[10:9] <= ba; //addr bank
            state <= ACTIVE;
          end
        end
        ACTIVE: begin
          if (command_q==CMD_ACTIVE) begin
            addr_buf[23:11] <= a; //addr row
            actived_row[ba] <= a;
            addr_buf[10:9] <= ba; //addr bank
            state <= ACTIVE;
          end
          else if (command_q==CMD_READ) begin
            addr_buf[8:0] <= a[8:0]; //addr col
            addr_buf[10:9] <= ba; //addr bank
            addr_buf[23:11] <= actived_row[ba];
            state <= READ_WAIT; //cas=2
            cnt <= 0; 
          end
          else if (command_q==CMD_WRITE) begin
            addr_buf[8:0] <= a[8:0];
            addr_buf[10:9] <= ba;
            addr_buf[23:11] <= actived_row[ba];
            dqm_buf <= dqm;
            dq_buf <= dq;
            state <= WRITE;
            // cnt <= burst_len;
          end
        end
        READ_WAIT: begin
          cnt <= burst_len;
          state <= READ;
        end
        READ: begin
          // if (cnt!=0) begin
          //   cnt <= cnt -1;
          //   addr_buf <= addr_buf + 1;
          // end
          // else begin
            state <= ACTIVE;
          // end
        end
        WRITE: begin
          // if (cnt!=0) begin
            // cnt <= cnt -1;
            addr_buf <= addr_buf + 1;
            dqm_buf <= dqm;
            dq_buf <= dq;
            if (!dqm_buf[0]) begin
              sdram_mem[addr_buf][7:0] <= dq_buf[7:0];
            end
            if (!dqm_buf[1]) begin
              sdram_mem[addr_buf][15:8] <= dq_buf[15:8];
            end
          // end
          // else begin
            state <= ACTIVE;
          // end
        end
        default: state <= INIT;
      endcase
    end
  end

  assign dq = (state==READ) ? sdram_mem[addr_buf] : 16'bz;

endmodule
