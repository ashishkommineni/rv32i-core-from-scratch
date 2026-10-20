package rv32i_trace_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {TRACE_RETIRE, TRACE_HALT, TRACE_TRAP} rv32i_trace_kind_e;

  class rv32i_trace_item extends uvm_sequence_item;
    rv32i_trace_kind_e kind;
    bit [31:0] pc;
    bit [31:0] instr;
    bit [4:0] rd;
    bit [31:0] wdata;
    bit [4:0] cause;
    bit [31:0] value;

    `uvm_object_utils_begin(rv32i_trace_item)
      `uvm_field_enum(rv32i_trace_kind_e, kind, UVM_DEFAULT)
      `uvm_field_int(pc, UVM_HEX)
      `uvm_field_int(instr, UVM_HEX)
      `uvm_field_int(rd, UVM_DEC)
      `uvm_field_int(wdata, UVM_HEX)
      `uvm_field_int(cause, UVM_DEC)
      `uvm_field_int(value, UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "rv32i_trace_item");
      super.new(name);
    endfunction
  endclass

  class rv32i_trace_monitor extends uvm_monitor;
    `uvm_component_utils(rv32i_trace_monitor)
    uvm_analysis_port #(rv32i_trace_item) ap;
    virtual rv32i_trace_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rv32i_trace_if)::get(this, "", "vif", vif))
        `uvm_fatal("TRACE/CFG", "trace virtual interface was not supplied")
    endfunction

    task run_phase(uvm_phase phase);
      rv32i_trace_item item;
      bit terminal_seen = 0;
      forever begin
        @(posedge vif.clk);
        if (!vif.rst_n) begin
          terminal_seen = 0;
        end else begin
          if (vif.retire_valid) begin
            item = rv32i_trace_item::type_id::create("retire_item");
            item.kind  = TRACE_RETIRE;
            item.pc    = vif.retire_pc;
            item.instr = vif.retire_instr;
            item.rd    = vif.retire_rd;
            item.wdata = vif.retire_wdata;
            ap.write(item);
          end
          if (!terminal_seen && vif.halted) begin
            item = rv32i_trace_item::type_id::create("halt_item");
            item.kind  = TRACE_HALT;
            item.pc    = vif.trap_pc;
            item.cause = vif.trap_cause;
            item.value = vif.trap_value;
            ap.write(item);
            terminal_seen = 1;
          end else if (!terminal_seen && vif.trap_valid) begin
            item = rv32i_trace_item::type_id::create("trap_item");
            item.kind  = TRACE_TRAP;
            item.pc    = vif.trap_pc;
            item.cause = vif.trap_cause;
            item.value = vif.trap_value;
            ap.write(item);
            terminal_seen = 1;
          end
        end
      end
    endtask
  endclass

  class rv32i_trace_agent extends uvm_agent;
    `uvm_component_utils(rv32i_trace_agent)
    rv32i_trace_monitor monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = rv32i_trace_monitor::type_id::create("monitor", this);
    endfunction
  endclass
endpackage
