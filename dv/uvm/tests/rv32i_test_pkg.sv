package rv32i_test_pkg;
  import uvm_pkg::*;
  import rv32i_mem_pkg::*;
  import rv32i_trace_pkg::*;
  import rv32i_env_pkg::*;
  import rv32i_sequence_pkg::*;
  `include "uvm_macros.svh"

  class rv32i_base_test extends uvm_test;
    `uvm_component_utils(rv32i_base_test)
    rv32i_env env;
    rv32i_mem_agent_cfg imem_cfg;
    rv32i_mem_agent_cfg dmem_cfg;
    virtual rv32i_trace_if trace_vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "imem_cfg", imem_cfg))
        `uvm_fatal("TEST/CFG", "imem_cfg missing")
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "dmem_cfg", dmem_cfg))
        `uvm_fatal("TEST/CFG", "dmem_cfg missing")
      if (!uvm_config_db#(virtual rv32i_trace_if)::get(this, "", "trace_vif", trace_vif))
        `uvm_fatal("TEST/CFG", "trace_vif missing")
      uvm_config_db#(rv32i_mem_agent_cfg)::set(this, "env", "imem_cfg", imem_cfg);
      uvm_config_db#(rv32i_mem_agent_cfg)::set(this, "env", "dmem_cfg", dmem_cfg);
      uvm_config_db#(virtual rv32i_trace_if)::set(this, "env.trace_agent*", "vif", trace_vif);
      env = rv32i_env::type_id::create("env", this);
    endfunction

    task wait_for_terminal(uvm_phase phase);
      rv32i_wait_terminal_vseq wait_seq;
      wait_seq = rv32i_wait_terminal_vseq::type_id::create("wait_seq");
      wait_seq.trace_vif = trace_vif;
      wait_seq.start(null);
      repeat (3) @(posedge trace_vif.clk);
    endtask
  endclass

  class rv32i_smoke_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_smoke_test)
    logic [31:0] expected [0:63];
    string expected_path;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      expected_path = "dv/programs/rv32i_smoke_expected.hex";
      void'($value$plusargs("EXPECTED=%s", expected_path));
      $readmemh(expected_path, expected);
      wait_for_terminal(phase);
      if (!trace_vif.halted || trace_vif.trap_valid)
        `uvm_error("TEST/TERM", $sformatf("expected host halt; halt=%0b trap=%0b cause=%0d",
                   trace_vif.halted, trace_vif.trap_valid, trace_vif.trap_cause))
      foreach (expected[i]) begin
        if (dmem_cfg.memory.words[(32'h400 >> 2) + i] !== expected[i])
          `uvm_error("TEST/SIG", $sformatf("signature[%0d] expected=%08x actual=%08x",
                     i, expected[i], dmem_cfg.memory.words[(32'h400 >> 2) + i]))
      end
      `uvm_info("TEST/PASS", $sformatf("signature checked; retirements=%0d",
                env.scoreboard.checked_retirements), UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class rv32i_trap_test extends rv32i_base_test;
    `uvm_component_utils(rv32i_trap_test)
    int expected_cause;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      if (!$value$plusargs("EXPECTED_CAUSE=%d", expected_cause))
        `uvm_fatal("TEST/ARG", "+EXPECTED_CAUSE=<decimal> is required")
      wait_for_terminal(phase);
      if (!trace_vif.trap_valid)
        `uvm_error("TEST/TRAP", "expected trap_valid but core did not trap")
      else if (trace_vif.trap_cause != expected_cause[4:0])
        `uvm_error("TEST/TRAP", $sformatf("expected cause=%0d actual=%0d pc=%08x value=%08x",
                   expected_cause, trace_vif.trap_cause, trace_vif.trap_pc, trace_vif.trap_value))
      phase.drop_objection(this);
    endtask
  endclass
endpackage
