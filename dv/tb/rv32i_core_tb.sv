`timescale 1ns/1ps

module rv32i_core_tb;
  import rv32i_pkg::*;

  localparam int IMEM_WORDS = 1024;
  localparam int DMEM_WORDS = 1024;
  localparam int SIG_BASE_WORD = 32'h400 >> 2;
  localparam int SIG_WORDS = 64;
  localparam int MAX_CYCLES = 20000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  logic imem_req_valid, imem_req_ready;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_rsp_rdata;
  logic imem_rsp_err;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready;
  logic [31:0] dmem_rsp_rdata;
  logic dmem_rsp_err;
  logic halted, trap_valid;
  logic [4:0] trap_cause;
  logic [31:0] trap_pc, trap_value;
  logic retire_valid;
  logic [31:0] retire_pc, retire_instr, retire_wdata;
  logic [4:0] retire_rd;

  logic [31:0] imem [0:IMEM_WORDS-1];
  logic [31:0] dmem [0:DMEM_WORDS-1];
  logic [31:0] expected_signature [0:SIG_WORDS-1];

  logic imem_pending;
  logic [31:0] imem_pending_addr;
  logic fetch_seen;
  logic [31:0] last_fetch_pc, last_fetch_instr;
  integer imem_delay;
  logic dmem_pending;
  logic [31:0] dmem_pending_addr;
  logic [31:0] dmem_pending_wdata;
  logic [3:0] dmem_pending_wstrb;
  logic dmem_pending_write;
  integer dmem_delay;
  integer bus_cycle;
  integer force_imem_err;
  integer force_dmem_err;

  logic [9:0] cov_op;
  logic [8:0] cov_op_imm;
  logic [5:0] cov_branch;
  logic [4:0] cov_load;
  logic [2:0] cov_store;
  logic [4:0] cov_control;
  integer retired_count;

  string program_path;
  string expected_path;
  string test_name;
  integer expected_cause;
  integer errors;
  integer cycles;
  integer idx;

  rv32i_core dut (
    .clk, .rst_n,
    .imem_req_valid, .imem_req_ready, .imem_req_addr,
    .imem_rsp_valid, .imem_rsp_ready, .imem_rsp_rdata, .imem_rsp_err,
    .dmem_req_valid, .dmem_req_ready, .dmem_req_write, .dmem_req_addr,
    .dmem_req_wdata, .dmem_req_wstrb, .dmem_rsp_valid, .dmem_rsp_ready,
    .dmem_rsp_rdata, .dmem_rsp_err,
    .halted, .trap_valid, .trap_cause, .trap_pc, .trap_value,
    .retire_valid, .retire_pc, .retire_instr, .retire_rd, .retire_wdata
  );

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  assign imem_req_ready = !imem_pending && !imem_rsp_valid && (bus_cycle[1:0] != 2'b00);
  assign dmem_req_ready = !dmem_pending && !dmem_rsp_valid && (bus_cycle[2:0] != 3'b000);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      imem_pending      <= 1'b0;
      imem_pending_addr <= 32'd0;
      imem_delay        <= 0;
      imem_rsp_valid    <= 1'b0;
      imem_rsp_rdata    <= 32'd0;
      imem_rsp_err      <= 1'b0;
      fetch_seen        <= 1'b0;
      last_fetch_pc     <= 32'd0;
      last_fetch_instr  <= 32'd0;
      dmem_pending      <= 1'b0;
      dmem_pending_addr <= 32'd0;
      dmem_pending_wdata <= 32'd0;
      dmem_pending_wstrb <= 4'd0;
      dmem_pending_write <= 1'b0;
      dmem_delay        <= 0;
      dmem_rsp_valid    <= 1'b0;
      dmem_rsp_rdata    <= 32'd0;
      dmem_rsp_err      <= 1'b0;
      bus_cycle         <= 0;
    end else begin
      bus_cycle <= bus_cycle + 1;

      if (imem_rsp_valid && imem_rsp_ready) begin
        fetch_seen      <= !imem_rsp_err;
        last_fetch_pc   <= imem_pending_addr;
        last_fetch_instr <= imem_rsp_rdata;
        imem_rsp_valid <= 1'b0;
        imem_rsp_err   <= 1'b0;
      end
      if (!imem_pending && !imem_rsp_valid && imem_req_valid && imem_req_ready) begin
        imem_pending      <= 1'b1;
        imem_pending_addr <= imem_req_addr;
        imem_delay        <= bus_cycle % 3;
      end else if (imem_pending) begin
        if (imem_delay == 0) begin
          imem_rsp_valid <= 1'b1;
          imem_rsp_err   <= (force_imem_err != 0);
          if ((imem_pending_addr >> 2) < IMEM_WORDS)
            imem_rsp_rdata <= imem[imem_pending_addr >> 2];
          else begin
            imem_rsp_rdata <= 32'd0;
            imem_rsp_err   <= 1'b1;
          end
          imem_pending <= 1'b0;
        end else begin
          imem_delay <= imem_delay - 1;
        end
      end

      if (dmem_rsp_valid && dmem_rsp_ready) begin
        dmem_rsp_valid <= 1'b0;
        dmem_rsp_err   <= 1'b0;
      end
      if (!dmem_pending && !dmem_rsp_valid && dmem_req_valid && dmem_req_ready) begin
        dmem_pending       <= 1'b1;
        dmem_pending_addr  <= dmem_req_addr;
        dmem_pending_wdata <= dmem_req_wdata;
        dmem_pending_wstrb <= dmem_req_wstrb;
        dmem_pending_write <= dmem_req_write;
        dmem_delay         <= (bus_cycle + 1) % 4;
      end else if (dmem_pending) begin
        if (dmem_delay == 0) begin
          dmem_rsp_valid <= 1'b1;
          dmem_rsp_err   <= (force_dmem_err != 0);
          if ((dmem_pending_addr >> 2) < DMEM_WORDS) begin
            dmem_rsp_rdata <= dmem[dmem_pending_addr >> 2];
            if (dmem_pending_write && (force_dmem_err == 0)) begin
              if (dmem_pending_wstrb[0]) dmem[dmem_pending_addr >> 2][7:0]   <= dmem_pending_wdata[7:0];
              if (dmem_pending_wstrb[1]) dmem[dmem_pending_addr >> 2][15:8]  <= dmem_pending_wdata[15:8];
              if (dmem_pending_wstrb[2]) dmem[dmem_pending_addr >> 2][23:16] <= dmem_pending_wdata[23:16];
              if (dmem_pending_wstrb[3]) dmem[dmem_pending_addr >> 2][31:24] <= dmem_pending_wdata[31:24];
            end
          end else begin
            dmem_rsp_rdata <= 32'd0;
            dmem_rsp_err   <= 1'b1;
          end
          dmem_pending <= 1'b0;
        end else begin
          dmem_delay <= dmem_delay - 1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : portable_coverage
    logic [6:0] op;
    logic [2:0] f3;
    logic [6:0] f7;
    if (!rst_n) begin
      cov_op       <= '0;
      cov_op_imm   <= '0;
      cov_branch   <= '0;
      cov_load     <= '0;
      cov_store    <= '0;
      cov_control  <= '0;
      retired_count <= 0;
    end else if (retire_valid) begin
      if (!fetch_seen || retire_pc !== last_fetch_pc || retire_instr !== last_fetch_instr)
        $fatal(1, "retirement trace did not match the completed instruction fetch");
      if ((retire_rd == 5'd0) && (retire_wdata != 32'd0))
        $fatal(1, "retirement trace exposed a nonzero x0 write");
      op = retire_instr[6:0];
      f3 = retire_instr[14:12];
      f7 = retire_instr[31:25];
      retired_count <= retired_count + 1;
      unique case (op)
        OPCODE_OP: begin
          unique case ({f7, f3})
            {7'h00,3'h0}: cov_op[0] <= 1'b1;
            {7'h20,3'h0}: cov_op[1] <= 1'b1;
            {7'h00,3'h1}: cov_op[2] <= 1'b1;
            {7'h00,3'h2}: cov_op[3] <= 1'b1;
            {7'h00,3'h3}: cov_op[4] <= 1'b1;
            {7'h00,3'h4}: cov_op[5] <= 1'b1;
            {7'h00,3'h5}: cov_op[6] <= 1'b1;
            {7'h20,3'h5}: cov_op[7] <= 1'b1;
            {7'h00,3'h6}: cov_op[8] <= 1'b1;
            {7'h00,3'h7}: cov_op[9] <= 1'b1;
            default: ;
          endcase
        end
        OPCODE_OP_IMM: begin
          unique case (f3)
            3'h0: cov_op_imm[0] <= 1'b1;
            3'h2: cov_op_imm[1] <= 1'b1;
            3'h3: cov_op_imm[2] <= 1'b1;
            3'h4: cov_op_imm[3] <= 1'b1;
            3'h6: cov_op_imm[4] <= 1'b1;
            3'h7: cov_op_imm[5] <= 1'b1;
            3'h1: cov_op_imm[6] <= 1'b1;
            3'h5: if (f7 == 7'h00) cov_op_imm[7] <= 1'b1;
                  else if (f7 == 7'h20) cov_op_imm[8] <= 1'b1;
            default: ;
          endcase
        end
        OPCODE_BRANCH: begin
          case (f3)
            3'h0: cov_branch[0] <= 1'b1;
            3'h1: cov_branch[1] <= 1'b1;
            3'h4: cov_branch[2] <= 1'b1;
            3'h5: cov_branch[3] <= 1'b1;
            3'h6: cov_branch[4] <= 1'b1;
            3'h7: cov_branch[5] <= 1'b1;
            default: ;
          endcase
        end
        OPCODE_LOAD: begin
          case (f3)
            3'h0: cov_load[0] <= 1'b1;
            3'h1: cov_load[1] <= 1'b1;
            3'h2: cov_load[2] <= 1'b1;
            3'h4: cov_load[3] <= 1'b1;
            3'h5: cov_load[4] <= 1'b1;
            default: ;
          endcase
        end
        OPCODE_STORE: begin
          if (f3 <= 3'h2) cov_store[f3[1:0]] <= 1'b1;
        end
        OPCODE_LUI:      cov_control[0] <= 1'b1;
        OPCODE_AUIPC:    cov_control[1] <= 1'b1;
        OPCODE_JAL:      cov_control[2] <= 1'b1;
        OPCODE_JALR:     cov_control[3] <= 1'b1;
        OPCODE_MISC_MEM: cov_control[4] <= 1'b1;
        default: ;
      endcase
    end
  end

  task automatic report_error(input string message);
    begin
      $display("[ERROR] %s", message);
      errors = errors + 1;
    end
  endtask

  initial begin
    program_path    = "dv/programs/rv32i_smoke.hex";
    expected_path   = "dv/programs/rv32i_smoke_expected.hex";
    test_name       = "smoke";
    expected_cause  = -1;
    force_imem_err  = 0;
    force_dmem_err  = 0;
    errors          = 0;
    cycles          = 0;
    void'($value$plusargs("PROGRAM=%s", program_path));
    void'($value$plusargs("EXPECTED=%s", expected_path));
    void'($value$plusargs("TEST=%s", test_name));
    void'($value$plusargs("EXPECTED_CAUSE=%d", expected_cause));
    void'($value$plusargs("IMEM_ERROR=%d", force_imem_err));
    void'($value$plusargs("DMEM_ERROR=%d", force_dmem_err));

    for (idx = 0; idx < IMEM_WORDS; idx = idx + 1) imem[idx] = 32'h0010_0073;
    for (idx = 0; idx < DMEM_WORDS; idx = idx + 1) dmem[idx] = 32'd0;
    for (idx = 0; idx < SIG_WORDS; idx = idx + 1) expected_signature[idx] = 32'd0;
    $readmemh(program_path, imem);
    if (expected_cause < 0) $readmemh(expected_path, expected_signature);

    if ($test$plusargs("WAVES")) begin
      $dumpfile("results/rv32i_core.vcd");
      $dumpvars(0, rv32i_core_tb);
    end

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    while (!halted && !trap_valid && (cycles < MAX_CYCLES)) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    #1;

    if (cycles >= MAX_CYCLES)
      report_error($sformatf("timeout after %0d cycles", cycles));

    if (expected_cause >= 0) begin
      if (!trap_valid)
        report_error("expected a trap, but the core did not enter ST_TRAP");
      else if (trap_cause != expected_cause[4:0])
        report_error($sformatf("expected trap cause %0d, got %0d", expected_cause, trap_cause));
    end else begin
      if (trap_valid)
        report_error($sformatf("unexpected trap cause=%0d pc=%08x value=%08x", trap_cause, trap_pc, trap_value));
      if (!halted)
        report_error("smoke program did not halt through EBREAK");
      for (idx = 0; idx < SIG_WORDS; idx = idx + 1) begin
        if (dmem[SIG_BASE_WORD + idx] !== expected_signature[idx])
          report_error($sformatf("signature[%0d] expected=%08x actual=%08x", idx,
                                 expected_signature[idx], dmem[SIG_BASE_WORD + idx]));
      end
      if (cov_op !== 10'h3ff) report_error($sformatf("OP coverage gate failed: %03x", cov_op));
      if (cov_op_imm !== 9'h1ff) report_error($sformatf("OP-IMM coverage gate failed: %03x", cov_op_imm));
      if (cov_branch !== 6'h3f) report_error($sformatf("branch coverage gate failed: %02x", cov_branch));
      if (cov_load !== 5'h1f) report_error($sformatf("load coverage gate failed: %02x", cov_load));
      if (cov_store !== 3'h7) report_error($sformatf("store coverage gate failed: %x", cov_store));
      if (cov_control !== 5'h1f) report_error($sformatf("control coverage gate failed: %02x", cov_control));
    end

    if (errors == 0) begin
      $display("TEST_PASS name=%s cycles=%0d retired=%0d cause=%0d", test_name, cycles, retired_count, trap_cause);
      $finish;
    end else begin
      $fatal(1, "TEST_FAIL name=%s errors=%0d", test_name, errors);
    end
  end
endmodule
