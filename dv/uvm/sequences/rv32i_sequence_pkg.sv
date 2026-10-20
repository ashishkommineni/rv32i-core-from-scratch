package rv32i_sequence_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class rv32i_wait_terminal_vseq extends uvm_sequence #(uvm_sequence_item);
    `uvm_object_utils(rv32i_wait_terminal_vseq)
    virtual rv32i_trace_if trace_vif;
    int unsigned timeout_cycles = 20000;

    function new(string name = "rv32i_wait_terminal_vseq");
      super.new(name);
    endfunction

    task body();
      int unsigned cycles;
      if (trace_vif == null)
        `uvm_fatal("VSEQ/VIF", "trace_vif was not assigned")
      wait (trace_vif.rst_n === 1'b1);
      for (cycles = 0; cycles < timeout_cycles; cycles++) begin
        @(posedge trace_vif.clk);
        if (trace_vif.halted || trace_vif.trap_valid)
          return;
      end
      `uvm_fatal("VSEQ/TIMEOUT", $sformatf("core did not terminate within %0d cycles", timeout_cycles))
    endtask
  endclass
endpackage
