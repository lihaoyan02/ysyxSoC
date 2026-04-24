module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);

  reg [7:0] data_buf;
  reg [3:0] bit_cnt;
  reg state;
  localparam RECEIVE = 0, TRANSFER = 1;

  // 状态机
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      state <= RECEIVE;
    end
    else if (state == RECEIVE && bit_cnt == 7) begin
      state <= TRANSFER;
    end
  end
  // 计数器和数据寄存器
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      bit_cnt <= 0;
    end
    else if (bit_cnt < 8) begin
      bit_cnt <= bit_cnt + 1;
    end
  end
  // 数据接收
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      data_buf <= 0; 
    end
    else if (state == RECEIVE) begin
      data_buf <= {data_buf[6:0], mosi}; // 左移一位，接收新数据
    end
    else if (state == TRANSFER) begin
      data_buf <= {1'b0, data_buf[7:1]}; // 右移一位，准备下一位输出
    end
  end
  // 数据传输
  assign miso = (state == TRANSFER) ? data_buf[0] : 1'b1;
  
endmodule
