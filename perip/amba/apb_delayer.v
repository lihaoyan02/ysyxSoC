module apb_delayer(
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

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  // Frequency scaling parameters
  // Device: 100MHz, Processor: 550MHz => r = 5.5 = 11/2
  // Scaling factor s = 2, so r*s = 11 (hardcoded in RTL)
  // Per-cycle accumulation value (r*s hardcoded)
  localparam ACCUM_VALUE = 11-2; //minus 1 for inherent 1 cycle delay in APB transaction, so 5.5*2-2=9
  localparam SCALE_FACTOR = 2;  // Division by 2 is a right shift by 1
  
  // States for delay controller
  localparam IDLE = 2'b00;
  localparam COUNTING = 2'b01;
  localparam DELAYING = 2'b10;
  
  // State register
  reg [1:0] state, state_next;
  
  // Counters for delay calculation
  // counter_scaled is used for both accumulation and delay phases
  // When accumulating: counter_scaled += ACCUM_VALUE per cycle
  // When delaying: counter_scaled -= 1 per cycle
  reg [31:0] counter_scaled, counter_scaled_next;
  
  // Latched response data
  reg [31:0] prdata_latched, prdata_latched_next;
  reg pslverr_latched, pslverr_latched_next;
  
  // APB transaction detection
  // Transaction begins when both psel and penable are asserted
  wire xact_begin = in_psel && in_penable;
  // Device response occurs when out_pready is asserted
  wire device_resp = out_pready;
  
  // Combinational logic for next state and counter updates
  always @(*) begin
    state_next = state;
    counter_scaled_next = counter_scaled;
    prdata_latched_next = prdata_latched;
    pslverr_latched_next = pslverr_latched;
    
    case (state)
      IDLE: begin
        if (xact_begin) begin
          if (device_resp) begin
            state_next = DELAYING;
            counter_scaled_next = ACCUM_VALUE >> 1;
            prdata_latched_next = out_prdata;
            pslverr_latched_next = out_pslverr;
          end else begin
            // Start of APB transaction: enter counting phase
            state_next = COUNTING;
            counter_scaled_next = ACCUM_VALUE;  // Start from 0, will accumulate from next cycle
          end
        end
      end
      
      COUNTING: begin
        // In counting phase, accumulate per cycle while waiting for device response
        if (device_resp) begin
          // Device has responded: accumulate one more time, then convert value
          // counter_scaled = ACCUM_VALUE * (k-1), add one more for ACCUM_VALUE * k
          // Then divide by SCALE_FACTOR: y = (ACCUM_VALUE * k) / SCALE_FACTOR
          //                             = (counter_scaled + ACCUM_VALUE) >> 1
          state_next = DELAYING;
          counter_scaled_next = ((counter_scaled + ACCUM_VALUE) >> 1);  // (11*k) >> 1 = 5.5*k
          // Latch the response data
          prdata_latched_next = out_prdata;
          pslverr_latched_next = out_pslverr;
        end else begin
          // Continue accumulating
          counter_scaled_next = counter_scaled + ACCUM_VALUE;
        end
      end
      
      DELAYING: begin
        // In delay phase, decrement counter each cycle
        if (counter_scaled == 32'b0) begin
          // Delay complete: return to IDLE
          state_next = IDLE;
        end else begin
          // Continue delaying
          counter_scaled_next = counter_scaled - 32'b1;
        end
      end
      
      default: begin
        state_next = IDLE;
      end
    endcase
  end
  
  // Sequential logic
  always @(posedge clock) begin
    if (reset) begin
      state <= IDLE;
      counter_scaled <= 32'b0;
      prdata_latched <= 32'b0;
      pslverr_latched <= 1'b0;
    end else begin
      state <= state_next;
      counter_scaled <= counter_scaled_next;
      prdata_latched <= prdata_latched_next;
      pslverr_latched <= pslverr_latched_next;
    end
  end
  
  // Output multiplexing logic
  // Pass through address and control signals directly to device
  // The delay is applied only to the ready and response signals
  assign out_paddr   = in_paddr;
  assign out_psel    = (state == DELAYING) ? 1'b0 : in_psel;
  assign out_penable = (state == DELAYING) ? 1'b0 : in_penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  
  // Ready signal: 
  // - In IDLE: pass through device ready directly
  // - In DELAYING: signal ready when counter about to decrement to 0 (counter_scaled == 1)
  // - In COUNTING: always not ready (0)
  assign in_pready = (state == DELAYING && counter_scaled == 32'h1);
  
  // Data signals: from latched values during delay, from device otherwise
  assign in_prdata = (state == DELAYING) ? prdata_latched : out_prdata;
  assign in_pslverr = (state == DELAYING) ? pslverr_latched : out_pslverr;

endmodule
