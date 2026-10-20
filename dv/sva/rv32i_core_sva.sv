`timescale 1ns/1ps
module rv32i_core_sva (
  input logic clk,
  input logic rst_n,
  input logic imem_req_valid,
  input logic imem_req_ready,
  input logic [31:0] imem_req_addr,
  input logic imem_rsp_valid,
  input logic imem_rsp_ready,
  input logic dmem_req_valid,
  input logic dmem_req_ready,
  input logic dmem_req_write,
  input logic [31:0] dmem_req_addr,
  input logic [31:0] dmem_req_wdata,
  input logic [3:0] dmem_req_wstrb,
  input logic dmem_rsp_valid,
  input logic dmem_rsp_ready,
  input logic halted,
  input logic trap_valid,
  input logic retire_valid,
  input logic [4:0] retire_rd,
  input logic [31:0] retire_wdata,
  input logic [31:0] x0_value
);
  ap_imem_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    imem_req_valid && !imem_req_ready |=> imem_req_valid && $stable(imem_req_addr)
  );
  ap_dmem_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    dmem_req_valid && !dmem_req_ready |=>
      dmem_req_valid && $stable({dmem_req_write, dmem_req_addr, dmem_req_wdata, dmem_req_wstrb})
  );
  ap_imem_aligned: assert property (
    @(posedge clk) disable iff (!rst_n) imem_req_valid |-> imem_req_addr[1:0] == 2'b00);
  ap_dmem_bus_aligned: assert property (
    @(posedge clk) disable iff (!rst_n) dmem_req_valid |-> dmem_req_addr[1:0] == 2'b00);
  ap_store_has_strobe: assert property (
    @(posedge clk) disable iff (!rst_n)
    dmem_req_valid && dmem_req_write |-> dmem_req_wstrb != 4'b0000);
  ap_load_has_no_strobe: assert property (
    @(posedge clk) disable iff (!rst_n)
    dmem_req_valid && !dmem_req_write |-> dmem_req_wstrb == 4'b0000);
  ap_terminal_exclusive: assert property (
    @(posedge clk) disable iff (!rst_n) !(halted && trap_valid));
  ap_no_retire_in_terminal: assert property (
    @(posedge clk) disable iff (!rst_n) (halted || trap_valid) |-> !retire_valid);
  ap_x0_trace_is_zero: assert property (
    @(posedge clk) disable iff (!rst_n)
    retire_valid && retire_rd == 5'd0 |-> retire_wdata == 32'd0);
  ap_x0_storage_is_zero: assert property (
    @(posedge clk) disable iff (!rst_n) x0_value == 32'd0);
  ap_single_imem_phase: assert property (
    @(posedge clk) disable iff (!rst_n) !(imem_req_valid && imem_rsp_ready));
  ap_single_dmem_phase: assert property (
    @(posedge clk) disable iff (!rst_n) !(dmem_req_valid && dmem_rsp_ready));

  // This procedural assertion is intentionally active during reset; the
  // module-level default disable would otherwise suppress a reset property.
  always @(posedge clk) begin
    if (!rst_n)
      assert (!imem_req_valid && !imem_rsp_ready &&
              !dmem_req_valid && !dmem_rsp_ready &&
              !retire_valid && !halted && !trap_valid)
        else $error("core outputs were not quiescent during reset");
  end

  // A stall-cycle hit plus the stable-until-accepted assertions proves the
  // portable backpressure scenario without relying on delayed cover syntax
  // unsupported by Verilator 5.020.
  cp_waited_imem: cover property (
    @(posedge clk) disable iff (!rst_n) imem_req_valid && !imem_req_ready);
  cp_waited_dmem: cover property (
    @(posedge clk) disable iff (!rst_n) dmem_req_valid && !dmem_req_ready);
  cp_halt: cover property (
    @(posedge clk) disable iff (!rst_n) halted);
  cp_trap: cover property (
    @(posedge clk) disable iff (!rst_n) trap_valid);
endmodule

bind rv32i_core rv32i_core_sva rv32i_core_sva_i (
  .clk, .rst_n,
  .imem_req_valid, .imem_req_ready, .imem_req_addr,
  .imem_rsp_valid, .imem_rsp_ready,
  .dmem_req_valid, .dmem_req_ready, .dmem_req_write,
  .dmem_req_addr, .dmem_req_wdata, .dmem_req_wstrb,
  .dmem_rsp_valid, .dmem_rsp_ready,
  .halted, .trap_valid, .retire_valid, .retire_rd, .retire_wdata,
  .x0_value(regs[0])
);
