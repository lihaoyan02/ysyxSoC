module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  reg [2:0] state;
  reg [1:0] rstate; //for qpi
  reg qpi_flag;
  initial begin
    qpi_flag = 0; // qpi disabled initially
  end

  localparam IDLE = 3'b0, ADDR_READ=3'b1, WAIT=3'b10, DATA_TRANS_HIGH=3'b11,
    DATA_TRANS_LOW = 3'b100, DATA_RECV_HIGH=3'b101, DATA_RECV_LOW=3'b110, QPI_TRANS=3'b111;
  // state for qpi (read)
  localparam RIDLE=2'b00, READ_HIGH = 2'b1, READ_LOW = 2'b10;
  reg [3:0] cnt;

  reg [7:0] cmd_read;
  reg [23:0] addr_buf;
  reg [23:0] addr_qpi;

  // psram
  reg [7:0] psram_mem [(1<<24)-1:0];
  // output
  assign dio = qpi_flag ? ((rstate==READ_HIGH) ? psram_mem[addr_qpi][7:4] :
            (rstate==READ_LOW) ? psram_mem[addr_qpi][3:0] : 4'bz) :
            (state==DATA_TRANS_HIGH) ? psram_mem[addr_buf][7:4] :
            (state==DATA_TRANS_LOW) ? psram_mem[addr_buf][3:0] : 4'bz;
  
  // command parse state machine
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      if (cmd_read==8'h35) begin
        qpi_flag <= 1;
      end
      state <= IDLE;
      cmd_read <= 0;
      cnt <= 0;
      addr_buf <= 0;
    end else begin
      case (state)
        IDLE: begin
          if (qpi_flag==1) begin // QPI
            if (cnt < 2) begin
              cmd_read <= {cmd_read[3:0], dio};
              cnt <= cnt + 1;
            end
            else begin
              cnt <= 4'b1;
              addr_buf <= {addr_buf[19:0], dio};
              state <= ADDR_READ;
            end
          end else begin // Q-SPI
            if (cnt < 8) begin
              cmd_read <= {cmd_read[6:0], dio[0]};
              cnt <= cnt + 1;
            end
            else begin
              cnt <= 4'b1;
              addr_buf <= {addr_buf[19:0], dio};
              state <= ADDR_READ;
            end
          end
        end 
        ADDR_READ: begin
          if (cnt < 6) begin
            cnt <= cnt + 1;
            addr_buf <= {addr_buf[19:0], dio};
          end
          else if (cmd_read == 8'heb) begin
            cnt <= 4'b1;
            state <= WAIT;
          end
          else if (cmd_read == 8'h38) begin
            psram_mem[addr_buf][7:4] <= dio;
            state <= DATA_RECV_LOW;
          end
          else begin
            $display("Unsupported command `%xh`, only support `eb` read command\n", cmd_read);
            $finish;
          end
        end
        WAIT: begin
          if (cnt < 6) begin
            cnt <= cnt + 1;
          end
          else begin
            if (qpi_flag) begin
              state <= QPI_TRANS; // enable qpi (negedge triger)
            end 
            else begin
              state <= DATA_TRANS_HIGH;
            end
          end
        end
        DATA_TRANS_HIGH: begin
          state <= DATA_TRANS_LOW;
        end
        DATA_TRANS_LOW: begin
          addr_buf <= addr_buf + 1;
          state <= DATA_TRANS_HIGH;
        end
        DATA_RECV_HIGH: begin // qpi is the same as q-spi for receive
          psram_mem[addr_buf][7:4] <= dio;
          state <= DATA_RECV_LOW;
        end
        DATA_RECV_LOW: begin
          psram_mem[addr_buf][3:0] <= dio;
          addr_buf <= addr_buf + 1;
          state <= DATA_RECV_HIGH;
        end
        QPI_TRANS: state <= QPI_TRANS;
        default: state <= IDLE;
      endcase
    end
  end
  // QPI read state machine
  always @(negedge sck, posedge ce_n) begin
    if (ce_n) begin
      addr_qpi <= 0;
      rstate <= RIDLE;
    end
    else begin
      if (state == QPI_TRANS) begin
        case (rstate)
          RIDLE: begin
            addr_qpi <= addr_buf;
            rstate <= READ_HIGH;
          end 
          READ_HIGH: begin
            rstate <= READ_LOW;
          end
          READ_LOW: begin
            addr_qpi <= addr_qpi + 1;
            rstate <= READ_HIGH;
          end
          default: rstate <= RIDLE;
        endcase
      end
    end
  end
endmodule
