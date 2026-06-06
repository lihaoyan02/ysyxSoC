module axi4_delayer(
  input         clock,
  input         reset,

  output        in_arready,
  input         in_arvalid,
  input  [3:0]  in_arid,
  input  [31:0] in_araddr,
  input  [7:0]  in_arlen,
  input  [2:0]  in_arsize,
  input  [1:0]  in_arburst,
  input         in_rready,
  output        in_rvalid,
  output [3:0]  in_rid,
  output [31:0] in_rdata,
  output [1:0]  in_rresp,
  output        in_rlast,
  output        in_awready,
  input         in_awvalid,
  input  [3:0]  in_awid,
  input  [31:0] in_awaddr,
  input  [7:0]  in_awlen,
  input  [2:0]  in_awsize,
  input  [1:0]  in_awburst,
  output        in_wready,
  input         in_wvalid,
  input  [31:0] in_wdata,
  input  [3:0]  in_wstrb,
  input         in_wlast,
                in_bready,
  output        in_bvalid,
  output [3:0]  in_bid,
  output [1:0]  in_bresp,

  input         out_arready,
  output        out_arvalid,
  output [3:0]  out_arid,
  output [31:0] out_araddr,
  output [7:0]  out_arlen,
  output [2:0]  out_arsize,
  output [1:0]  out_arburst,
  output        out_rready,
  input         out_rvalid,
  input  [3:0]  out_rid,
  input  [31:0] out_rdata,
  input  [1:0]  out_rresp,
  input         out_rlast,
  input         out_awready,
  output        out_awvalid,
  output [3:0]  out_awid,
  output [31:0] out_awaddr,
  output [7:0]  out_awlen,
  output [2:0]  out_awsize,
  output [1:0]  out_awburst,
  input         out_wready,
  output        out_wvalid,
  output [31:0] out_wdata,
  output [3:0]  out_wstrb,
  output        out_wlast,
                out_bready,
  input         out_bvalid,
  input  [3:0]  out_bid,
  input  [1:0]  out_bresp
);

  // Frequency scaling parameters
  // Device: 100MHz, Processor: 550MHz => r = 5.5 = 11/2
  // Scaling factor s = 2, so r*s = 11 (hardcoded in RTL)
  // Per-cycle accumulation value (r*s hardcoded)
  localparam ACCUM_VALUE = 11 - 2;  // minus 1 for inherent 1 cycle delay, so 5.5*2-2=9
  localparam SCALE_FACTOR = 2;      // Division by 2 is a right shift by 1
  
  // States for read delay controller
  localparam R_IDLE = 2'b00;
  localparam AR_COUNTING = 2'b01;
  localparam R_COUNTING = 2'b10;
  localparam R_DONE = 2'b11;

  localparam AR_DELAYING = 2'b01;
  localparam R_PRE_DELAYING = 2'b10;
  localparam R_DELAYING = 2'b11;
  
  // Read delay state machine and counters
  reg [1:0]  r_state, r_state_next, r_delay_state;
  reg [31:0] r_counter, r_counter_next;
  reg [31:0] ar_counter, ar_counter_next;

  reg [3:0] ptr, ptr_next;

  reg [31:0] counter_queue [7:0];
  reg [31:0] counter_queue_next;

  reg [31:0] queue_rdata [7:0];
  reg [1:0] queue_rresp [7:0];
  reg [3:0] queue_rid [7:0];
  reg queue_rlast [7:0];
  
  
  // ==========================================================================
  // READ PATH: Handle read address, read data with delay calibration
  // ==========================================================================
  
  // Combinational logic for read state machine
  always @(*) begin
    r_state_next = r_state;
    ar_counter_next = ar_counter; // counter for ar handshake (aready)
    r_counter_next = r_counter; // counter for r handshanke
    ptr_next = ptr;
    counter_queue_next = 0;
    case (r_state)
      R_IDLE: begin
        if (in_arvalid) begin
          // Read address accepted - start of read transaction
          if (out_arready) begin
            // Device responds immediately with first data beat
            r_state_next = R_COUNTING;
            ar_counter_next = ACCUM_VALUE >> 1;
            r_counter_next = ACCUM_VALUE;
            ptr_next = 0;
          end else begin
            // Start counting cycles until device responds
            r_state_next = AR_COUNTING;
            ar_counter_next = ACCUM_VALUE;
            r_counter_next = 0;
            ptr_next = 0;
          end
        end
      end
      AR_COUNTING: begin
        if (out_arready) begin
          r_state_next = R_COUNTING;
          ar_counter_next = (ar_counter >> 1);
          r_counter_next = ACCUM_VALUE;
          ptr_next = 0;
        end
        else begin
          ar_counter_next = ar_counter + ACCUM_VALUE;
        end
      end
      R_COUNTING: begin
        if (out_rvalid) begin
          // r_state_next = R_DELAYING;
          r_counter_next = ACCUM_VALUE;
          counter_queue_next = r_counter >> 1;
          ptr_next = ptr + 1;
          if (out_rlast) begin
            r_state_next = R_DONE;
          end
        end
        else begin
          // r_state_next = R_COUNTING;
          r_counter_next = r_counter + ACCUM_VALUE;
        end
      end
      R_DONE: begin
        if (r_delay_state==R_IDLE) begin
          r_state_next = R_IDLE;
        end
        else begin
          r_state_next = r_state;
          ar_counter_next = ar_counter; // counter for ar handshake (aready)
          r_counter_next = r_counter; // counter for r handshanke
          ptr_next = ptr;
        end
      end
    endcase
  end
  // Sequential logic for read path
  integer i = 0;
  always @(posedge clock) begin
    if (reset) begin
      r_state <= R_IDLE;
      ar_counter <= 32'b0;
      r_counter <= 32'b0;
      ptr <= 0;
      for (i=0; i<8; i=i+1) begin
        counter_queue[i] <= 0;
        queue_rdata[i] <= 0;
        queue_rresp[i] <= 0;
        queue_rid[i] <= 0;
        queue_rlast[i] <= 0;
      end
    end else begin
      r_state <= r_state_next;
      ar_counter <= ar_counter_next;
      r_counter <= r_counter_next;
      ptr <= ptr_next;
      if (out_rvalid) begin
        counter_queue[ptr[2:0]] <= counter_queue_next;
        queue_rdata[ptr[2:0]] <= out_rdata;
        queue_rresp[ptr[2:0]] <= out_rresp;
        queue_rid[ptr[2:0]] <= out_rid;
        queue_rlast[ptr[2:0]] <= out_rlast;
      end
      
    end
  end

  // Sequential logic for uper level
  reg [3:0] r_ptr;
  wire [3:0] r_ptr_inc = r_ptr + 4'b1;
  reg [31:0] delay_counter;
  always @(posedge clock) begin
    if (reset) begin
      r_delay_state <= R_IDLE;
      delay_counter <= 0;
      r_ptr <= 4'b1111;
    end else begin
      case (r_delay_state)
        R_IDLE: begin
          if (r_state==R_COUNTING) begin
            r_delay_state <= AR_DELAYING;
            delay_counter <= ar_counter - 1;
          end
          r_ptr <= 4'b1111;
        end 
        AR_DELAYING: begin
          if (delay_counter==0) begin
            if (r_ptr_inc < ptr) begin  
              r_delay_state <= R_DELAYING;
              delay_counter <= counter_queue[r_ptr_inc[2:0]];
              r_ptr <= r_ptr_inc;
            end
            else begin
              r_delay_state <= R_PRE_DELAYING;
            end
          end
          else begin
            delay_counter <= delay_counter - 1;
          end
        end
        R_PRE_DELAYING: begin
          if (r_ptr_inc < ptr) begin  
            r_delay_state <= R_DELAYING;
            delay_counter <= counter_queue[r_ptr_inc[2:0]];
            r_ptr <= r_ptr_inc;
          end
        end
        R_DELAYING: begin
          if (delay_counter==0 & in_rready) begin
            if (queue_rlast[r_ptr[2:0]]) begin
              r_delay_state <= R_IDLE;
            end
            else if (r_ptr_inc < ptr) begin
              delay_counter <= counter_queue[r_ptr_inc[2:0]];
              r_ptr <= r_ptr_inc;
            end
            else begin
              r_delay_state <= R_PRE_DELAYING;
            end
          end
          else if(delay_counter!=0) begin
            delay_counter <= delay_counter - 1;
          end
        end
      endcase
    end
  end
  // Read output multiplexing
  
  assign in_rvalid = (r_delay_state==R_DELAYING & delay_counter==0) ? 1 : 0;
  assign in_rdata = (r_delay_state==R_DELAYING & delay_counter==0) ? queue_rdata[r_ptr[2:0]] : 0;
  assign in_rresp = (r_delay_state==R_DELAYING & delay_counter==0) ? queue_rresp[r_ptr[2:0]] : 0;
  assign in_rid = (r_delay_state==R_DELAYING & delay_counter==0) ? queue_rid[r_ptr[2:0]] : 0;
  assign in_rlast = (r_delay_state==R_DELAYING & delay_counter==0) ? queue_rlast[r_ptr[2:0]] : 0;
  assign out_rready = (r_state==R_COUNTING) ? 1 : 0;

  // assign in_rvalid = out_rvalid;
  // assign in_rdata = out_rdata;
  // assign in_rresp = out_rresp;
  // assign in_rid = out_rid;
  // assign in_rlast = out_rlast;
  // assign out_rready = in_rready;
  
  // Read address pass-through
  assign in_arready = (r_delay_state==AR_DELAYING & delay_counter==0) ? 1 : 0;
  // assign in_arready = out_arready;
  assign out_arvalid = (r_state==R_IDLE | r_state==AR_COUNTING) ? in_arvalid : 0;
  assign out_arid = in_arid;
  assign out_araddr = in_araddr;
  assign out_arlen = in_arlen;
  assign out_arsize = in_arsize;
  assign out_arburst = in_arburst;
  
  // ==========================================================================
  // WRITE PATH: Handle write address, write data, write response with delays
  // ==========================================================================
  // States for write delay controller
  localparam W_IDLE = 2'b00;
  localparam W_COUNTING = 2'b01;
  localparam W_DELAYING = 2'b10;
  // Write side state machine and counters
  reg [1:0]  w_state, w_state_next;
  reg [31:0] w_counter, w_counter_next;
  
  // Write response latching
  reg [31:0] b_delay_counter, b_delay_counter_next;
  reg [3:0]  bid_latched, bid_latched_next;
  reg [1:0]  bresp_latched, bresp_latched_next;
  
  // Combinational logic for write state machine
  always @(*) begin
    w_state_next = w_state;
    w_counter_next = w_counter;
    b_delay_counter_next = b_delay_counter;
    bid_latched_next = bid_latched;
    bresp_latched_next = bresp_latched;
    
    case (w_state)
      W_IDLE: begin
        if (in_awvalid) begin
          w_state_next = W_COUNTING;
          w_counter_next = ACCUM_VALUE;
        end
      end
      W_COUNTING: begin
        // Accumulating cycles while waiting for device response
        if (out_bvalid) begin
          w_state_next = W_DELAYING;
          w_counter_next = ((w_counter + ACCUM_VALUE) >> 1);
          bid_latched_next = out_bid;
          bresp_latched_next = out_bresp;
        end
        else begin
          w_counter_next = w_counter + ACCUM_VALUE;
        end
      end
      W_DELAYING: begin
        // Delaying before returning response to upstream
        if (w_counter == 32'h0) begin
          // Delay complete, ready to signal response
          if (in_bready) begin
            // Upstream accepts response
            w_state_next = W_IDLE;
          end
        end 
        else if (w_counter > 32'h0) begin
          // Continue counting down delay
          w_counter_next = w_counter - 32'b1;
        end
      end
      default: begin
        w_state_next = W_IDLE;
      end
    endcase
  end
  
  // Sequential logic for write path
  always @(posedge clock) begin
    if (reset) begin
      w_state <= W_IDLE;
      w_counter <= 32'b0;
      b_delay_counter <= 32'b0;
      bid_latched <= 4'b0;
      bresp_latched <= 2'b0;
    end else begin
      w_state <= w_state_next;
      w_counter <= w_counter_next;
      b_delay_counter <= b_delay_counter_next;
      bid_latched <= bid_latched_next;
      bresp_latched <= bresp_latched_next;
    end
  end
  
  // Write output multiplexing
  assign in_awready = out_awready;
  assign out_awvalid = in_awvalid;
  assign out_awid = in_awid;
  assign out_awaddr = in_awaddr;
  assign out_awlen = in_awlen;
  assign out_awsize = in_awsize;
  assign out_awburst = in_awburst;
  assign in_wready = out_wready;
  assign out_wvalid = in_wvalid;
  assign out_wdata = in_wdata;
  assign out_wstrb = in_wstrb;
  assign out_wlast = in_wlast;
  assign out_bready = (w_state==W_COUNTING);
  assign in_bvalid = (w_state==W_DELAYING & w_counter==0) ? 1 : 0;
  assign in_bid = (w_state==W_DELAYING & w_counter==0) ? bid_latched : 0;
  assign in_bresp =  (w_state==W_DELAYING & w_counter==0) ? bresp_latched : 0;

endmodule
