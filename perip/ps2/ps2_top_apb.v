module ps2_top_apb(
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

  input         ps2_clk,
  input         ps2_data
);

assign in_pslverr = 0;

reg state;
localparam IDLE = 1'd0, READ=1'd1;
// internal signal, for test
reg [9:0] buffer;        // ps2_data bits
reg [7:0] fifo[7:0];     // data fifo
reg [2:0] w_ptr,r_ptr;   // fifo write and read pointers
reg [3:0] count;  // count ps2_data bits
reg [2:0] ps2_clk_sync;
reg ready;

  always @(posedge clock) begin
      ps2_clk_sync <=  {ps2_clk_sync[1:0],ps2_clk};
  end

  wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];
  integer i=0;
  always @(posedge clock) begin
        if (reset) begin // reset
            count <= 0; w_ptr <= 0; r_ptr <= 0; ready<= 0;
            for ( i=0 ; i<8; i=i+1) begin
              fifo[i] <= 0;
            end
            buffer <= 0;
        end
        else begin
            if ( ready ) begin // read to output next data
                if(state==READ) //read next data
                begin //changed: not read when almost full 
										r_ptr <= r_ptr + 3'b1;
										fifo[r_ptr] <= 8'b0;
										if(w_ptr==(r_ptr+1'b1)) //empty 
                        ready <= 1'b0;
                end
            end
            if (sampling) begin
              if (count == 4'd10) begin
                if ((buffer[0] == 0) &&  // start bit
                    (ps2_data)       &&  // stop bit
                    (^buffer[9:1])) begin      // odd  parity
                    fifo[w_ptr] <= buffer[8:1];  // kbd scan code
                    w_ptr <= w_ptr+3'b1;
                    ready <= 1'b1;
                end
                count <= 0;     // for next
              end else begin
                buffer[count] <= ps2_data;  // store ps2_data
                count <= count + 3'b1;
              end
            end
        end
    end

  always @(posedge clock) begin
    if (reset) begin
      state <= IDLE;
    end
    else begin
      case (state)
        IDLE: begin
          if (in_psel) begin
            state <= READ;
          end
        end
        READ: begin
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

assign in_prdata = (state==READ) ? {24'b0, fifo[r_ptr]} : 0;
assign in_pready = (state==READ);
endmodule
