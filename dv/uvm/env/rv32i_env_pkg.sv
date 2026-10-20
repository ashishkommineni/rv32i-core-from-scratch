package rv32i_env_pkg;
  import uvm_pkg::*;
  import rv32i_pkg::*;
  import rv32i_mem_pkg::*;
  import rv32i_trace_pkg::*;
  `include "uvm_macros.svh"

  `uvm_analysis_imp_decl(_imem)
  `uvm_analysis_imp_decl(_dmem)
  `uvm_analysis_imp_decl(_trace)

  class rv32i_scoreboard extends uvm_component;
    `uvm_component_utils(rv32i_scoreboard)
    uvm_analysis_imp_imem #(rv32i_mem_item, rv32i_scoreboard) imem_imp;
    uvm_analysis_imp_dmem #(rv32i_mem_item, rv32i_scoreboard) dmem_imp;
    uvm_analysis_imp_trace #(rv32i_trace_item, rv32i_scoreboard) trace_imp;

    rv32i_mem_item imem_q[$];
    rv32i_mem_item dmem_q[$];
    bit [31:0] regs[32];
    bit [31:0] expected_pc;
    int unsigned checked_retirements;
    bit saw_halt;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      imem_imp = new("imem_imp", this);
      dmem_imp = new("dmem_imp", this);
      trace_imp = new("trace_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      foreach (regs[i]) regs[i] = 0;
      expected_pc = 0;
    endfunction

    function automatic bit [31:0] sx(input bit [31:0] value, input int bits);
      bit [31:0] mask;
      mask = 32'hffff_ffff << bits;
      return value[bits-1] ? (value | mask) : (value & ~mask);
    endfunction

    function automatic bit signed [31:0] as_signed(input bit [31:0] value);
      return $signed(value);
    endfunction

    function void write_imem(rv32i_mem_item item);
      rv32i_mem_item copy;
      $cast(copy, item.clone());
      imem_q.push_back(copy);
    endfunction

    function void write_dmem(rv32i_mem_item item);
      rv32i_mem_item copy;
      $cast(copy, item.clone());
      dmem_q.push_back(copy);
    endfunction

    function void check_rd(rv32i_trace_item trace, bit expected_we,
                           bit [4:0] expected_rd, bit [31:0] expected_data);
      bit [4:0] visible_rd;
      bit [31:0] visible_data;
      visible_rd = (expected_we && expected_rd != 0) ? expected_rd : 0;
      visible_data = (visible_rd != 0) ? expected_data : 0;
      if (trace.rd != visible_rd || trace.wdata != visible_data)
        `uvm_error("SB/RD", $sformatf("pc=%08x expected x%0d=%08x got x%0d=%08x",
                   trace.pc, visible_rd, visible_data, trace.rd, trace.wdata))
      if (visible_rd != 0) regs[visible_rd] = visible_data;
      regs[0] = 0;
    endfunction

    function void check_terminal(rv32i_trace_item trace);
      rv32i_mem_item fetch;
      rv32i_mem_item data;
      bit [31:0] insn, a, imm_i, imm_s, imm_b, imm_j, expected_value;
      bit [6:0] op;
      bit [4:0] rs1;
      if (trace.pc != expected_pc)
        `uvm_error("SB/TERM_PC", $sformatf("terminal pc expected=%08x actual=%08x",
                   expected_pc, trace.pc))
      if (imem_q.size() == 0) begin
        `uvm_error("SB/TERM_FETCH", "terminal event has no matching fetch response")
        return;
      end
      fetch = imem_q.pop_front();
      if (fetch.addr != trace.pc)
        `uvm_error("SB/TERM_FETCH", $sformatf("terminal fetch addr=%08x pc=%08x",
                   fetch.addr, trace.pc))

      if (trace.kind == TRACE_HALT) begin
        saw_halt = 1'b1;
        if (fetch.err || fetch.rdata != 32'h0010_0073 || trace.cause != CAUSE_BREAKPOINT ||
            trace.value != trace.pc)
          `uvm_error("SB/HALT", "host EBREAK halt metadata or instruction mismatch")
        return;
      end

      if (trace.cause == CAUSE_INSTR_ACCESS_FAULT) begin
        if (!fetch.err || trace.value != trace.pc)
          `uvm_error("SB/IFETCH_FAULT", "instruction access fault did not match failed fetch")
        return;
      end
      if (fetch.err)
        `uvm_error("SB/TERM_FETCH", "non-fetch terminal cause followed an errored fetch")

      insn = fetch.rdata;
      op = insn[6:0];
      rs1 = insn[19:15];
      a = regs[rs1];
      imm_i = sx(insn[31:20], 12);
      imm_s = sx({insn[31:25], insn[11:7]}, 12);
      imm_b = sx({insn[31], insn[7], insn[30:25], insn[11:8], 1'b0}, 13);
      imm_j = sx({insn[31], insn[19:12], insn[20], insn[30:21], 1'b0}, 21);
      expected_value = 0;

      case (trace.cause)
        CAUSE_INSTR_ADDR_MISALIGNED: begin
          case (op)
            OPCODE_JAL: expected_value = trace.pc + imm_j;
            OPCODE_JALR: expected_value = (a + imm_i) & 32'hffff_fffe;
            OPCODE_BRANCH: expected_value = trace.pc + imm_b;
            default: `uvm_error("SB/IAM", "misaligned-instruction trap came from wrong opcode")
          endcase
          if (trace.value != expected_value || trace.value[1:0] == 0)
            `uvm_error("SB/IAM", $sformatf("target expected=%08x actual=%08x",
                       expected_value, trace.value))
        end
        CAUSE_ILLEGAL_INSTRUCTION: begin
          if (trace.value != insn)
            `uvm_error("SB/ILLEGAL", "illegal-instruction tval must hold the instruction")
        end
        CAUSE_LOAD_ADDR_MISALIGNED,
        CAUSE_STORE_ADDR_MISALIGNED: begin
          expected_value = a + ((op == OPCODE_LOAD) ? imm_i : imm_s);
          if (trace.value != expected_value)
            `uvm_error("SB/ALIGN", $sformatf("bad address expected=%08x actual=%08x",
                       expected_value, trace.value))
        end
        CAUSE_LOAD_ACCESS_FAULT,
        CAUSE_STORE_ACCESS_FAULT: begin
          expected_value = a + ((op == OPCODE_LOAD) ? imm_i : imm_s);
          if (dmem_q.size() == 0) begin
            `uvm_error("SB/ACCESS", "data access trap has no failed data response")
          end else begin
            data = dmem_q.pop_front();
            if (!data.err || data.addr != {expected_value[31:2], 2'b00} ||
                data.write != (op == OPCODE_STORE))
              `uvm_error("SB/ACCESS", "failed data response does not match trapped instruction")
          end
          if (trace.value != expected_value)
            `uvm_error("SB/ACCESS", $sformatf("fault address expected=%08x actual=%08x",
                       expected_value, trace.value))
        end
        CAUSE_ECALL_MMODE: begin
          if (insn != 32'h0000_0073 || trace.value != 0)
            `uvm_error("SB/ECALL", "ECALL encoding or trap value mismatch")
        end
        default: `uvm_error("SB/CAUSE", $sformatf("unhandled terminal cause %0d", trace.cause))
      endcase
    endfunction

    function void write_trace(rv32i_trace_item trace);
      rv32i_mem_item bus;
      bit [31:0] insn, a, b, imm_i, imm_s, imm_b, imm_j;
      bit [31:0] result, next_pc, eff, raw;
      bit [6:0] op, f7;
      bit [4:0] rd, rs1, rs2;
      bit [2:0] f3;
      bit expected_we;
      int unsigned size;

      if (trace.kind != TRACE_RETIRE) begin
        check_terminal(trace);
        return;
      end
      if (trace.pc != expected_pc)
        `uvm_error("SB/PC", $sformatf("expected pc=%08x got=%08x", expected_pc, trace.pc))

      if (imem_q.size() == 0) begin
        `uvm_error("SB/IMEM", "retirement has no completed instruction fetch")
      end else begin
        bus = imem_q.pop_front();
        if (bus.addr != trace.pc || bus.rdata != trace.instr || bus.err)
          `uvm_error("SB/IMEM", $sformatf("fetch/retire mismatch addr=%08x data=%08x",
                     bus.addr, bus.rdata))
      end

      insn = trace.instr;
      op = insn[6:0]; rd = insn[11:7]; f3 = insn[14:12];
      rs1 = insn[19:15]; rs2 = insn[24:20]; f7 = insn[31:25];
      a = regs[rs1]; b = regs[rs2];
      imm_i = sx(insn[31:20], 12);
      imm_s = sx({insn[31:25], insn[11:7]}, 12);
      imm_b = sx({insn[31], insn[7], insn[30:25], insn[11:8], 1'b0}, 13);
      imm_j = sx({insn[31], insn[19:12], insn[20], insn[30:21], 1'b0}, 21);
      next_pc = trace.pc + 4;
      result = 0;
      expected_we = 0;

      case (op)
        OPCODE_LUI: begin expected_we = 1; result = {insn[31:12],12'd0}; end
        OPCODE_AUIPC: begin expected_we = 1; result = trace.pc + {insn[31:12],12'd0}; end
        OPCODE_JAL: begin expected_we = 1; result = trace.pc + 4; next_pc = trace.pc + imm_j; end
        OPCODE_JALR: begin expected_we = 1; result = trace.pc + 4; next_pc = (a + imm_i) & 32'hffff_fffe; end
        OPCODE_BRANCH: begin
          case (f3)
            3'h0: if (a == b) next_pc = trace.pc + imm_b;
            3'h1: if (a != b) next_pc = trace.pc + imm_b;
            3'h4: if (as_signed(a) < as_signed(b)) next_pc = trace.pc + imm_b;
            3'h5: if (as_signed(a) >= as_signed(b)) next_pc = trace.pc + imm_b;
            3'h6: if (a < b) next_pc = trace.pc + imm_b;
            3'h7: if (a >= b) next_pc = trace.pc + imm_b;
          endcase
        end
        OPCODE_OP_IMM: begin
          expected_we = 1;
          case (f3)
            3'h0: result = a + imm_i;
            3'h2: result = {31'd0, as_signed(a) < as_signed(imm_i)};
            3'h3: result = {31'd0, a < imm_i};
            3'h4: result = a ^ imm_i;
            3'h6: result = a | imm_i;
            3'h7: result = a & imm_i;
            3'h1: result = a << insn[24:20];
            3'h5: result = f7[5] ? as_signed(a) >>> insn[24:20] : a >> insn[24:20];
          endcase
        end
        OPCODE_OP: begin
          expected_we = 1;
          case ({f7,f3})
            {7'h00,3'h0}: result = a + b;
            {7'h20,3'h0}: result = a - b;
            {7'h00,3'h1}: result = a << b[4:0];
            {7'h00,3'h2}: result = {31'd0, as_signed(a) < as_signed(b)};
            {7'h00,3'h3}: result = {31'd0, a < b};
            {7'h00,3'h4}: result = a ^ b;
            {7'h00,3'h5}: result = a >> b[4:0];
            {7'h20,3'h5}: result = as_signed(a) >>> b[4:0];
            {7'h00,3'h6}: result = a | b;
            {7'h00,3'h7}: result = a & b;
          endcase
        end
        OPCODE_LOAD: begin
          expected_we = 1;
          eff = a + imm_i;
          if (dmem_q.size() == 0) begin
            `uvm_error("SB/DMEM", "load retired without completed data response")
          end else begin
            bus = dmem_q.pop_front();
            if (bus.write || bus.addr != {eff[31:2],2'b00} || bus.err)
              `uvm_error("SB/LOAD", $sformatf("load bus mismatch eff=%08x bus=%08x", eff, bus.addr))
            raw = bus.rdata >> (8 * eff[1:0]);
            case (f3)
              3'h0: result = sx(raw[7:0], 8);
              3'h1: result = sx(raw[15:0], 16);
              3'h2: result = bus.rdata;
              3'h4: result = {24'd0, raw[7:0]};
              3'h5: result = {16'd0, raw[15:0]};
            endcase
          end
        end
        OPCODE_STORE: begin
          eff = a + imm_s;
          if (dmem_q.size() == 0) begin
            `uvm_error("SB/DMEM", "store retired without completed data response")
          end else begin
            bus = dmem_q.pop_front();
            if (!bus.write || bus.addr != {eff[31:2],2'b00} || bus.err)
              `uvm_error("SB/STORE", $sformatf("store bus mismatch eff=%08x bus=%08x", eff, bus.addr))
            case (f3)
              3'h0: begin
                if (bus.wstrb != (4'b0001 << eff[1:0]) ||
                    bus.wdata != (b << (8 * eff[1:0])))
                  `uvm_error("SB/STORE", "SB lane data/strobe mismatch")
              end
              3'h1: begin
                if (bus.wstrb != (eff[1] ? 4'b1100 : 4'b0011) ||
                    bus.wdata != (b << (16 * eff[1])))
                  `uvm_error("SB/STORE", "SH lane data/strobe mismatch")
              end
              3'h2: if (bus.wstrb != 4'hf || bus.wdata != b)
                `uvm_error("SB/STORE", "SW data/strobe mismatch")
            endcase
          end
        end
        OPCODE_MISC_MEM: ;
        default: `uvm_error("SB/DECODE", $sformatf("unexpected retired opcode %02x", op))
      endcase

      check_rd(trace, expected_we, rd, result);
      expected_pc = next_pc;
      checked_retirements++;
    endfunction

    function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (saw_halt && checked_retirements == 0)
        `uvm_error("SB/EMPTY", "no instructions were checked")
      if (dmem_q.size() != 0)
        `uvm_error("SB/DMEM", $sformatf("%0d data transactions remained unmatched", dmem_q.size()))
      if (imem_q.size() != 0)
        `uvm_error("SB/IMEM", $sformatf("%0d instruction transactions remained unmatched", imem_q.size()))
    endfunction
  endclass

  class rv32i_env extends uvm_env;
    `uvm_component_utils(rv32i_env)
    rv32i_mem_agent imem_agent;
    rv32i_mem_agent dmem_agent;
    rv32i_trace_agent trace_agent;
    rv32i_scoreboard scoreboard;
    rv32i_mem_agent_cfg imem_cfg;
    rv32i_mem_agent_cfg dmem_cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "imem_cfg", imem_cfg))
        `uvm_fatal("ENV/CFG", "imem_cfg missing")
      if (!uvm_config_db#(rv32i_mem_agent_cfg)::get(this, "", "dmem_cfg", dmem_cfg))
        `uvm_fatal("ENV/CFG", "dmem_cfg missing")
      uvm_config_db#(rv32i_mem_agent_cfg)::set(this, "imem_agent*", "cfg", imem_cfg);
      uvm_config_db#(rv32i_mem_agent_cfg)::set(this, "dmem_agent*", "cfg", dmem_cfg);
      imem_agent = rv32i_mem_agent::type_id::create("imem_agent", this);
      dmem_agent = rv32i_mem_agent::type_id::create("dmem_agent", this);
      trace_agent = rv32i_trace_agent::type_id::create("trace_agent", this);
      scoreboard = rv32i_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      imem_agent.monitor.ap.connect(scoreboard.imem_imp);
      dmem_agent.monitor.ap.connect(scoreboard.dmem_imp);
      trace_agent.monitor.ap.connect(scoreboard.trace_imp);
    endfunction
  endclass
endpackage
