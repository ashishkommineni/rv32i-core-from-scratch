`timescale 1ns/1ps

module rv32i_uvm_top;
  import uvm_pkg::*;
  import rv32i_mem_pkg::*;
  import rv32i_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  rv32i_mem_if imem_if(clk);
  rv32i_mem_if dmem_if(clk);
  rv32i_trace_if trace_if(clk);

  string program_path;
  int force_imem_error;
  int force_dmem_error;

  rv32i_core dut (
    .clk, .rst_n,
    .imem_req_valid(imem_if.req_valid),
    .imem_req_ready(imem_if.req_ready),
    .imem_req_addr(imem_if.req_addr),
    .imem_rsp_valid(imem_if.rsp_valid),
    .imem_rsp_ready(imem_if.rsp_ready),
    .imem_rsp_rdata(imem_if.rsp_rdata),
    .imem_rsp_err(imem_if.rsp_err),
    .dmem_req_valid(dmem_if.req_valid),
    .dmem_req_ready(dmem_if.req_ready),
    .dmem_req_write(dmem_if.req_write),
    .dmem_req_addr(dmem_if.req_addr),
    .dmem_req_wdata(dmem_if.req_wdata),
    .dmem_req_wstrb(dmem_if.req_wstrb),
    .dmem_rsp_valid(dmem_if.rsp_valid),
    .dmem_rsp_ready(dmem_if.rsp_ready),
    .dmem_rsp_rdata(dmem_if.rsp_rdata),
    .dmem_rsp_err(dmem_if.rsp_err),
    .halted(trace_if.halted),
    .trap_valid(trace_if.trap_valid),
    .trap_cause(trace_if.trap_cause),
    .trap_pc(trace_if.trap_pc),
    .trap_value(trace_if.trap_value),
    .retire_valid(trace_if.retire_valid),
    .retire_pc(trace_if.retire_pc),
    .retire_instr(trace_if.retire_instr),
    .retire_rd(trace_if.retire_rd),
    .retire_wdata(trace_if.retire_wdata)
  );

  rv32i_isa_coverage coverage (
    .clk, .rst_n,
    .retire_valid(trace_if.retire_valid),
    .retire_instr(trace_if.retire_instr),
    .retire_pc(trace_if.retire_pc),
    .retire_rd(trace_if.retire_rd),
    .trap_valid(trace_if.trap_valid),
    .trap_cause(trace_if.trap_cause),
    .imem_req_valid(imem_if.req_valid),
    .imem_req_ready(imem_if.req_ready),
    .dmem_req_valid(dmem_if.req_valid),
    .dmem_req_ready(dmem_if.req_ready),
    .dmem_req_write(dmem_if.req_write),
    .dmem_req_wstrb(dmem_if.req_wstrb),
    .dmem_byte_offset(dut.mem_offset_q),
    .dmem_rsp_valid(dmem_if.rsp_valid),
    .dmem_rsp_ready(dmem_if.rsp_ready),
    .dmem_rsp_err(dmem_if.rsp_err)
  );

  assign imem_if.rst_n = rst_n;
  assign imem_if.req_write = 1'b0;
  assign imem_if.req_wdata = 32'd0;
  assign imem_if.req_wstrb = 4'd0;
  assign dmem_if.rst_n = rst_n;
  assign trace_if.rst_n = rst_n;

  always #5 clk = ~clk;

  initial begin
    rv32i_mem_agent_cfg imem_cfg;
    rv32i_mem_agent_cfg dmem_cfg;
    rv32i_memory_model imem_model;
    rv32i_memory_model dmem_model;

    program_path = "dv/programs/rv32i_smoke.hex";
    force_imem_error = 0;
    force_dmem_error = 0;
    void'($value$plusargs("PROGRAM=%s", program_path));
    void'($value$plusargs("IMEM_ERROR=%d", force_imem_error));
    void'($value$plusargs("DMEM_ERROR=%d", force_dmem_error));

    imem_model = rv32i_memory_model::type_id::create("imem_model");
    dmem_model = rv32i_memory_model::type_id::create("dmem_model");
    imem_cfg = rv32i_mem_agent_cfg::type_id::create("imem_cfg");
    dmem_cfg = rv32i_mem_agent_cfg::type_id::create("dmem_cfg");
    imem_cfg.vif = imem_if;
    imem_cfg.memory = imem_model;
    imem_cfg.read_only = 1'b1;
    imem_cfg.image = program_path;
    imem_cfg.max_wait = 3;
    imem_cfg.error_percent = force_imem_error ? 100 : 0;
    dmem_cfg.vif = dmem_if;
    dmem_cfg.memory = dmem_model;
    dmem_cfg.read_only = 1'b0;
    dmem_cfg.max_wait = 4;
    dmem_cfg.error_percent = force_dmem_error ? 100 : 0;

    uvm_config_db#(rv32i_mem_agent_cfg)::set(null, "uvm_test_top", "imem_cfg", imem_cfg);
    uvm_config_db#(rv32i_mem_agent_cfg)::set(null, "uvm_test_top", "dmem_cfg", dmem_cfg);
    uvm_config_db#(virtual rv32i_trace_if)::set(null, "uvm_test_top", "trace_vif", trace_if);

    fork
      begin
        repeat (7) @(posedge clk);
        rst_n <= 1'b1;
      end
    join_none
    run_test();
  end
endmodule
