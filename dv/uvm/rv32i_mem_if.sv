interface rv32i_mem_if(input logic clk);
  logic rst_n;
  logic req_valid;
  logic req_ready;
  logic req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid;
  logic rsp_ready;
  logic [31:0] rsp_rdata;
  logic rsp_err;
endinterface
