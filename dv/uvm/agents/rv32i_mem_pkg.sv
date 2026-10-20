package rv32i_mem_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class rv32i_mem_item extends uvm_sequence_item;
    bit write;
    bit [31:0] addr;
    bit [31:0] wdata;
    bit [3:0] wstrb;
    bit [31:0] rdata;
    bit err;
    int unsigned wait_cycles;

    `uvm_object_utils_begin(rv32i_mem_item)
      `uvm_field_int(write, UVM_DEFAULT)
      `uvm_field_int(addr, UVM_HEX)
      `uvm_field_int(wdata, UVM_HEX)
      `uvm_field_int(wstrb, UVM_HEX)
      `uvm_field_int(rdata, UVM_HEX)
      `uvm_field_int(err, UVM_DEFAULT)
      `uvm_field_int(wait_cycles, UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "rv32i_mem_item");
      super.new(name);
    endfunction
  endclass

  class rv32i_memory_model extends uvm_object;
    logic [31:0] words [0:1023];
    `uvm_object_utils(rv32i_memory_model)

    function new(string name = "rv32i_memory_model");
      super.new(name);
      clear();
    endfunction

    function void clear();
      foreach (words[i]) words[i] = 32'd0;
    endfunction

    task load_hex(string path, bit fill_ebreak = 0);
      if (fill_ebreak)
        foreach (words[i]) words[i] = 32'h0010_0073;
      $readmemh(path, words);
    endtask

    function bit in_range(bit [31:0] addr);
      return ((addr >> 2) < 1024);
    endfunction

    function logic [31:0] read_word(bit [31:0] addr);
      return words[addr >> 2];
    endfunction

    function void write_word(bit [31:0] addr, bit [31:0] data, bit [3:0] strobe);
      if (strobe[0]) words[addr >> 2][7:0]   = data[7:0];
      if (strobe[1]) words[addr >> 2][15:8]  = data[15:8];
      if (strobe[2]) words[addr >> 2][23:16] = data[23:16];
      if (strobe[3]) words[addr >> 2][31:24] = data[31:24];
    endfunction
  endclass

  class rv32i_mem_agent_cfg extends uvm_object;
    virtual rv32i_mem_if vif;
    rv32i_memory_model memory;
    bit read_only;
    int unsigned max_wait = 3;
    int unsigned error_percent = 0;
    string image = "";

    `uvm_object_utils_begin(rv32i_mem_agent_cfg)
      `uvm_field_int(read_only, UVM_DEFAULT)
      `uvm_field_int(max_wait, UVM_DEC)
      `uvm_field_int(error_percent, UVM_DEC)
      `uvm_field_string(image, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "rv32i_mem_agent_cfg");
      super.new(name);
    endfunction
  endclass

  class rv32i_mem_sequencer extends uvm_sequencer #(rv32i_mem_item);
    `uvm_component_utils(rv32i_mem_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class rv32i_mem_driver extends uvm_driver #(rv32i_mem_item);
    `uvm_component_utils(rv32i_mem_driver)
    rv32i_mem_agent_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("MEM/CFG", "rv32i_mem_agent_cfg was not supplied")
      if (cfg.vif == null || cfg.memory == null)
        `uvm_fatal("MEM/CFG", "memory agent needs a virtual interface and memory model")
    endfunction

    task run_phase(uvm_phase phase);
      rv32i_mem_item item;
      int unsigned delay;
      bit canceled;
      cfg.vif.req_ready <= 1'b0;
      cfg.vif.rsp_valid <= 1'b0;
      cfg.vif.rsp_rdata <= 32'd0;
      cfg.vif.rsp_err   <= 1'b0;
      if (cfg.image != "")
        cfg.memory.load_hex(cfg.image, cfg.read_only);
      wait (cfg.vif.rst_n === 1'b1);
      forever begin
        @(posedge cfg.vif.clk);
        cfg.vif.req_ready <= 1'b1;
        if (cfg.vif.req_valid && cfg.vif.req_ready) begin
          item = rv32i_mem_item::type_id::create("item");
          item.write = cfg.vif.req_write;
          item.addr   = cfg.vif.req_addr;
          item.wdata  = cfg.vif.req_wdata;
          item.wstrb  = cfg.vif.req_wstrb;
          cfg.vif.req_ready <= 1'b0;
          delay = (cfg.max_wait == 0) ? 0 : $urandom_range(cfg.max_wait, 0);
          item.wait_cycles = delay;
          canceled = 1'b0;
          repeat (delay) begin
            @(posedge cfg.vif.clk);
            if (!cfg.vif.rst_n)
              canceled = 1'b1;
          end
          if (canceled) begin
            cfg.vif.rsp_valid <= 1'b0;
            cfg.vif.rsp_err   <= 1'b0;
            wait (cfg.vif.rst_n === 1'b1);
            continue;
          end
          item.err = !cfg.memory.in_range(item.addr) ||
                     (cfg.error_percent != 0 && $urandom_range(99, 0) < cfg.error_percent);
          if (!item.err) begin
            if (item.write) begin
              if (cfg.read_only)
                item.err = 1'b1;
              else
                cfg.memory.write_word(item.addr, item.wdata, item.wstrb);
            end else begin
              item.rdata = cfg.memory.read_word(item.addr);
            end
          end
          cfg.vif.rsp_rdata <= item.rdata;
          cfg.vif.rsp_err   <= item.err;
          cfg.vif.rsp_valid <= 1'b1;
          do @(posedge cfg.vif.clk); while (cfg.vif.rst_n && !cfg.vif.rsp_ready);
          cfg.vif.rsp_valid <= 1'b0;
          cfg.vif.rsp_err   <= 1'b0;
          if (!cfg.vif.rst_n)
            wait (cfg.vif.rst_n === 1'b1);
        end
      end
    endtask
  endclass

  class rv32i_mem_monitor extends uvm_monitor;
    `uvm_component_utils(rv32i_mem_monitor)
    uvm_analysis_port #(rv32i_mem_item) ap;
    rv32i_mem_agent_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("MEM/MON/CFG", "rv32i_mem_agent_cfg was not supplied")
    endfunction

    task run_phase(uvm_phase phase);
      rv32i_mem_item pending;
      forever begin
        @(posedge cfg.vif.clk);
        if (!cfg.vif.rst_n) begin
          pending = null;
        end else begin
          if (cfg.vif.req_valid && cfg.vif.req_ready) begin
            if (pending != null)
              `uvm_error("MEM/ORDER", "second request observed before first response")
            pending = rv32i_mem_item::type_id::create("pending");
            pending.write = cfg.vif.req_write;
            pending.addr   = cfg.vif.req_addr;
            pending.wdata  = cfg.vif.req_wdata;
            pending.wstrb  = cfg.vif.req_wstrb;
          end
          if (cfg.vif.rsp_valid && cfg.vif.rsp_ready) begin
            if (pending == null) begin
              `uvm_error("MEM/ORDER", "response observed without a request")
            end else begin
              pending.rdata = cfg.vif.rsp_rdata;
              pending.err   = cfg.vif.rsp_err;
              ap.write(pending);
              pending = null;
            end
          end
        end
      end
    endtask
  endclass

  class rv32i_mem_agent extends uvm_agent;
    `uvm_component_utils(rv32i_mem_agent)
    rv32i_mem_driver driver;
    rv32i_mem_monitor monitor;
    rv32i_mem_sequencer sequencer;
    rv32i_mem_agent_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("MEM/AGT/CFG", "rv32i_mem_agent_cfg was not supplied")
      uvm_config_db#(rv32i_mem_agent_cfg)::set(this, "*", "cfg", cfg);
      driver = rv32i_mem_driver::type_id::create("driver", this);
      monitor = rv32i_mem_monitor::type_id::create("monitor", this);
      sequencer = rv32i_mem_sequencer::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass
endpackage
