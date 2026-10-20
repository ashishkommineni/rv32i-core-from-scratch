`timescale 1ns/1ps
package rv32i_pkg;
  typedef enum logic [3:0] {
    ST_FETCH_REQ,
    ST_FETCH_RSP,
    ST_EXECUTE,
    ST_DMEM_REQ,
    ST_DMEM_RSP,
    ST_HALT,
    ST_TRAP
  } core_state_e;

  localparam logic [6:0] OPCODE_LOAD     = 7'b0000011;
  localparam logic [6:0] OPCODE_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OPCODE_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPCODE_STORE    = 7'b0100011;
  localparam logic [6:0] OPCODE_OP       = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI      = 7'b0110111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPCODE_JALR     = 7'b1100111;
  localparam logic [6:0] OPCODE_JAL      = 7'b1101111;
  localparam logic [6:0] OPCODE_SYSTEM   = 7'b1110011;

  // Values intentionally match the synchronous-exception mcause codes.
  localparam logic [4:0] CAUSE_INSTR_ADDR_MISALIGNED = 5'd0;
  localparam logic [4:0] CAUSE_INSTR_ACCESS_FAULT    = 5'd1;
  localparam logic [4:0] CAUSE_ILLEGAL_INSTRUCTION   = 5'd2;
  localparam logic [4:0] CAUSE_BREAKPOINT            = 5'd3;
  localparam logic [4:0] CAUSE_LOAD_ADDR_MISALIGNED  = 5'd4;
  localparam logic [4:0] CAUSE_LOAD_ACCESS_FAULT     = 5'd5;
  localparam logic [4:0] CAUSE_STORE_ADDR_MISALIGNED = 5'd6;
  localparam logic [4:0] CAUSE_STORE_ACCESS_FAULT    = 5'd7;
  localparam logic [4:0] CAUSE_ECALL_MMODE           = 5'd11;
endpackage
