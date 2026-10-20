interface rv32i_trace_if(input logic clk);
  logic rst_n;
  logic halted;
  logic trap_valid;
  logic [4:0] trap_cause;
  logic [31:0] trap_pc;
  logic [31:0] trap_value;
  logic retire_valid;
  logic [31:0] retire_pc;
  logic [31:0] retire_instr;
  logic [4:0] retire_rd;
  logic [31:0] retire_wdata;
endinterface
