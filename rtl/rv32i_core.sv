`timescale 1ns/1ps
module rv32i_core #(
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_rsp_valid,
  output logic        imem_rsp_ready,
  input  logic [31:0] imem_rsp_rdata,
  input  logic        imem_rsp_err,

  output logic        dmem_req_valid,
  input  logic        dmem_req_ready,
  output logic        dmem_req_write,
  output logic [31:0] dmem_req_addr,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0]  dmem_req_wstrb,
  input  logic        dmem_rsp_valid,
  output logic        dmem_rsp_ready,
  input  logic [31:0] dmem_rsp_rdata,
  input  logic        dmem_rsp_err,

  output logic        halted,
  output logic        trap_valid,
  output logic [4:0]  trap_cause,
  output logic [31:0] trap_pc,
  output logic [31:0] trap_value,

  output logic        retire_valid,
  output logic [31:0] retire_pc,
  output logic [31:0] retire_instr,
  output logic [4:0]  retire_rd,
  output logic [31:0] retire_wdata
);
  import rv32i_pkg::*;

  core_state_e state_q;
  logic [31:0] pc_q;
  logic [31:0] instr_q;
  logic [31:0] instr_pc_q;
  logic [31:0] regs [0:31];

  logic        mem_write_q;
  logic [31:0] mem_addr_q;
  logic [31:0] mem_wdata_q;
  logic [3:0]  mem_wstrb_q;
  logic [1:0]  mem_offset_q;
  logic [2:0]  mem_funct3_q;
  logic [4:0]  mem_rd_q;
  logic [31:0] mem_pc_q;
  logic [31:0] mem_instr_q;

  logic [4:0]  trap_cause_q;
  logic [31:0] trap_pc_q;
  logic [31:0] trap_value_q;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [4:0] rd;
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_b;
  logic [31:0] imm_u;
  logic [31:0] imm_j;

  logic        dec_trap;
  logic [4:0]  dec_trap_cause;
  logic [31:0] dec_trap_value;
  logic        dec_halt;
  logic        dec_rd_we;
  logic [31:0] dec_rd_wdata;
  logic [31:0] dec_next_pc;
  logic        dec_mem_start;
  logic        dec_mem_write;
  logic [31:0] dec_mem_addr;
  logic [31:0] dec_mem_wdata;
  logic [3:0]  dec_mem_wstrb;
  logic [1:0]  dec_mem_offset;

  integer i;

  assign opcode    = instr_q[6:0];
  assign rd        = instr_q[11:7];
  assign funct3    = instr_q[14:12];
  assign rs1       = instr_q[19:15];
  assign rs2       = instr_q[24:20];
  assign funct7    = instr_q[31:25];
  assign rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  assign rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

  assign imm_i = {{20{instr_q[31]}}, instr_q[31:20]};
  assign imm_s = {{20{instr_q[31]}}, instr_q[31:25], instr_q[11:7]};
  assign imm_b = {{19{instr_q[31]}}, instr_q[31], instr_q[7],
                  instr_q[30:25], instr_q[11:8], 1'b0};
  assign imm_u = {instr_q[31:12], 12'b0};
  assign imm_j = {{11{instr_q[31]}}, instr_q[31], instr_q[19:12],
                  instr_q[20], instr_q[30:21], 1'b0};

  assign imem_req_valid = rst_n && (state_q == ST_FETCH_REQ) && (pc_q[1:0] == 2'b00);
  assign imem_req_addr  = pc_q;
  assign imem_rsp_ready = rst_n && (state_q == ST_FETCH_RSP);

  assign dmem_req_valid = rst_n && (state_q == ST_DMEM_REQ);
  assign dmem_req_write = mem_write_q;
  assign dmem_req_addr  = mem_addr_q;
  assign dmem_req_wdata = mem_wdata_q;
  assign dmem_req_wstrb = mem_wstrb_q;
  assign dmem_rsp_ready = rst_n && (state_q == ST_DMEM_RSP);

  assign halted     = (state_q == ST_HALT);
  assign trap_valid = (state_q == ST_TRAP);
  assign trap_cause = trap_cause_q;
  assign trap_pc    = trap_pc_q;
  assign trap_value = trap_value_q;

  function automatic logic [31:0] load_result(
    input logic [31:0] word,
    input logic [1:0]  offset,
    input logic [2:0]  size
  );
    logic [7:0] byte_value;
    logic [15:0] half_value;
    begin
      byte_value = word[offset*8 +: 8];
      half_value = offset[1] ? word[31:16] : word[15:0];
      unique case (size)
        3'b000: load_result = {{24{byte_value[7]}}, byte_value};
        3'b001: load_result = {{16{half_value[15]}}, half_value};
        3'b010: load_result = word;
        3'b100: load_result = {24'd0, byte_value};
        3'b101: load_result = {16'd0, half_value};
        default: load_result = 32'h0;
      endcase
    end
  endfunction

  always_comb begin : decode_execute
    logic [31:0] target;
    logic [31:0] effective_addr;
    logic        branch_taken;

    dec_trap       = 1'b0;
    dec_trap_cause = CAUSE_ILLEGAL_INSTRUCTION;
    dec_trap_value = instr_q;
    dec_halt       = 1'b0;
    dec_rd_we      = 1'b0;
    dec_rd_wdata   = 32'd0;
    dec_next_pc    = instr_pc_q + 32'd4;
    dec_mem_start  = 1'b0;
    dec_mem_write  = 1'b0;
    dec_mem_addr   = 32'd0;
    dec_mem_wdata  = 32'd0;
    dec_mem_wstrb  = 4'd0;
    dec_mem_offset = 2'd0;
    target         = 32'd0;
    effective_addr = 32'd0;
    branch_taken   = 1'b0;

    unique case (opcode)
      OPCODE_LUI: begin
        dec_rd_we    = 1'b1;
        dec_rd_wdata = imm_u;
      end

      OPCODE_AUIPC: begin
        dec_rd_we    = 1'b1;
        dec_rd_wdata = instr_pc_q + imm_u;
      end

      OPCODE_JAL: begin
        target = instr_pc_q + imm_j;
        if (target[1:0] != 2'b00) begin
          dec_trap       = 1'b1;
          dec_trap_cause = CAUSE_INSTR_ADDR_MISALIGNED;
          dec_trap_value = target;
        end else begin
          dec_rd_we      = 1'b1;
          dec_rd_wdata   = instr_pc_q + 32'd4;
          dec_next_pc    = target;
        end
      end

      OPCODE_JALR: begin
        target = (rs1_value + imm_i) & 32'hffff_fffe;
        if (funct3 != 3'b000) begin
          dec_trap = 1'b1;
        end else if (target[1:0] != 2'b00) begin
          dec_trap       = 1'b1;
          dec_trap_cause = CAUSE_INSTR_ADDR_MISALIGNED;
          dec_trap_value = target;
        end else begin
          dec_rd_we      = 1'b1;
          dec_rd_wdata   = instr_pc_q + 32'd4;
          dec_next_pc    = target;
        end
      end

      OPCODE_BRANCH: begin
        unique case (funct3)
          3'b000: branch_taken = (rs1_value == rs2_value); // BEQ
          3'b001: branch_taken = (rs1_value != rs2_value); // BNE
          3'b100: branch_taken = ($signed(rs1_value) <  $signed(rs2_value));
          3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));
          3'b110: branch_taken = (rs1_value < rs2_value);
          3'b111: branch_taken = (rs1_value >= rs2_value);
          default: dec_trap = 1'b1;
        endcase
        target = instr_pc_q + imm_b;
        if (!dec_trap && branch_taken) begin
          if (target[1:0] != 2'b00) begin
            dec_trap       = 1'b1;
            dec_trap_cause = CAUSE_INSTR_ADDR_MISALIGNED;
            dec_trap_value = target;
          end else begin
            dec_next_pc = target;
          end
        end
      end

      OPCODE_LOAD: begin
        effective_addr = rs1_value + imm_i;
        unique case (funct3)
          3'b000, 3'b100: ; // LB/LBU
          3'b001, 3'b101: begin // LH/LHU
            if (effective_addr[0]) begin
              dec_trap       = 1'b1;
              dec_trap_cause = CAUSE_LOAD_ADDR_MISALIGNED;
              dec_trap_value = effective_addr;
            end
          end
          3'b010: begin // LW
            if (effective_addr[1:0] != 2'b00) begin
              dec_trap       = 1'b1;
              dec_trap_cause = CAUSE_LOAD_ADDR_MISALIGNED;
              dec_trap_value = effective_addr;
            end
          end
          default: dec_trap = 1'b1;
        endcase
        if (!dec_trap) begin
          dec_mem_start = 1'b1;
          dec_mem_addr  = {effective_addr[31:2], 2'b00};
          dec_mem_offset = effective_addr[1:0];
        end
      end

      OPCODE_STORE: begin
        effective_addr = rs1_value + imm_s;
        dec_mem_write  = 1'b1;
        unique case (funct3)
          3'b000: begin // SB
            dec_mem_wstrb = 4'b0001 << effective_addr[1:0];
            dec_mem_wdata = rs2_value << (8 * effective_addr[1:0]);
          end
          3'b001: begin // SH
            if (effective_addr[0]) begin
              dec_trap       = 1'b1;
              dec_trap_cause = CAUSE_STORE_ADDR_MISALIGNED;
              dec_trap_value = effective_addr;
            end else begin
              dec_mem_wstrb = effective_addr[1] ? 4'b1100 : 4'b0011;
              dec_mem_wdata = rs2_value << (16 * effective_addr[1]);
            end
          end
          3'b010: begin // SW
            if (effective_addr[1:0] != 2'b00) begin
              dec_trap       = 1'b1;
              dec_trap_cause = CAUSE_STORE_ADDR_MISALIGNED;
              dec_trap_value = effective_addr;
            end else begin
              dec_mem_wstrb = 4'b1111;
              dec_mem_wdata = rs2_value;
            end
          end
          default: dec_trap = 1'b1;
        endcase
        if (!dec_trap) begin
          dec_mem_start = 1'b1;
          dec_mem_addr  = {effective_addr[31:2], 2'b00};
          dec_mem_offset = effective_addr[1:0];
        end
      end

      OPCODE_OP_IMM: begin
        dec_rd_we = 1'b1;
        unique case (funct3)
          3'b000: dec_rd_wdata = rs1_value + imm_i; // ADDI
          3'b010: dec_rd_wdata = {31'd0, $signed(rs1_value) < $signed(imm_i)};
          3'b011: dec_rd_wdata = {31'd0, rs1_value < imm_i};
          3'b100: dec_rd_wdata = rs1_value ^ imm_i;
          3'b110: dec_rd_wdata = rs1_value | imm_i;
          3'b111: dec_rd_wdata = rs1_value & imm_i;
          3'b001: begin
            if (instr_q[31:25] == 7'b0000000)
              dec_rd_wdata = rs1_value << instr_q[24:20];
            else
              dec_trap = 1'b1;
          end
          3'b101: begin
            if (instr_q[31:25] == 7'b0000000)
              dec_rd_wdata = rs1_value >> instr_q[24:20];
            else if (instr_q[31:25] == 7'b0100000)
              dec_rd_wdata = $signed(rs1_value) >>> instr_q[24:20];
            else
              dec_trap = 1'b1;
          end
          default: dec_trap = 1'b1;
        endcase
      end

      OPCODE_OP: begin
        dec_rd_we = 1'b1;
        unique case ({funct7, funct3})
          {7'b0000000, 3'b000}: dec_rd_wdata = rs1_value + rs2_value;
          {7'b0100000, 3'b000}: dec_rd_wdata = rs1_value - rs2_value;
          {7'b0000000, 3'b001}: dec_rd_wdata = rs1_value << rs2_value[4:0];
          {7'b0000000, 3'b010}: dec_rd_wdata = {31'd0, $signed(rs1_value) < $signed(rs2_value)};
          {7'b0000000, 3'b011}: dec_rd_wdata = {31'd0, rs1_value < rs2_value};
          {7'b0000000, 3'b100}: dec_rd_wdata = rs1_value ^ rs2_value;
          {7'b0000000, 3'b101}: dec_rd_wdata = rs1_value >> rs2_value[4:0];
          {7'b0100000, 3'b101}: dec_rd_wdata = $signed(rs1_value) >>> rs2_value[4:0];
          {7'b0000000, 3'b110}: dec_rd_wdata = rs1_value | rs2_value;
          {7'b0000000, 3'b111}: dec_rd_wdata = rs1_value & rs2_value;
          default: dec_trap = 1'b1;
        endcase
      end

      OPCODE_MISC_MEM: begin
        // Base FENCE is ordering metadata. This simple, non-speculative core has
        // at most one transaction in flight, so a legal FENCE retires as a NOP.
        if (funct3 != 3'b000)
          dec_trap = 1'b1;
      end

      OPCODE_SYSTEM: begin
        if (instr_q == 32'h0010_0073) begin // EBREAK: verification halt
          dec_halt = 1'b1;
        end else if (instr_q == 32'h0000_0073) begin // ECALL
          dec_trap       = 1'b1;
          dec_trap_cause = CAUSE_ECALL_MMODE;
          dec_trap_value = 32'd0;
        end else begin
          dec_trap = 1'b1;
        end
      end

      default: dec_trap = 1'b1;
    endcase

    // A trap has no architectural destination write.
    if (dec_trap)
      dec_rd_we = 1'b0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= ST_FETCH_REQ;
      pc_q          <= RESET_VECTOR;
      instr_q       <= 32'h0000_0013;
      instr_pc_q    <= RESET_VECTOR;
      mem_write_q   <= 1'b0;
      mem_addr_q    <= 32'd0;
      mem_wdata_q   <= 32'd0;
      mem_wstrb_q   <= 4'd0;
      mem_offset_q  <= 2'd0;
      mem_funct3_q  <= 3'd0;
      mem_rd_q      <= 5'd0;
      mem_pc_q      <= 32'd0;
      mem_instr_q   <= 32'd0;
      trap_cause_q  <= 5'd0;
      trap_pc_q     <= 32'd0;
      trap_value_q  <= 32'd0;
      retire_valid  <= 1'b0;
      retire_pc     <= 32'd0;
      retire_instr  <= 32'd0;
      retire_rd     <= 5'd0;
      retire_wdata  <= 32'd0;
      for (i = 0; i < 32; i = i + 1)
        regs[i] <= 32'd0;
    end else begin
      retire_valid <= 1'b0;
      regs[0]      <= 32'd0;

      unique case (state_q)
        ST_FETCH_REQ: begin
          if (pc_q[1:0] != 2'b00) begin
            trap_cause_q <= CAUSE_INSTR_ADDR_MISALIGNED;
            trap_pc_q    <= pc_q;
            trap_value_q <= pc_q;
            state_q      <= ST_TRAP;
          end else if (imem_req_valid && imem_req_ready) begin
            state_q <= ST_FETCH_RSP;
          end
        end

        ST_FETCH_RSP: begin
          if (imem_rsp_valid && imem_rsp_ready) begin
            if (imem_rsp_err) begin
              trap_cause_q <= CAUSE_INSTR_ACCESS_FAULT;
              trap_pc_q    <= pc_q;
              trap_value_q <= pc_q;
              state_q      <= ST_TRAP;
            end else begin
              instr_q    <= imem_rsp_rdata;
              instr_pc_q <= pc_q;
              state_q    <= ST_EXECUTE;
            end
          end
        end

        ST_EXECUTE: begin
          if (dec_trap) begin
            trap_cause_q <= dec_trap_cause;
            trap_pc_q    <= instr_pc_q;
            trap_value_q <= dec_trap_value;
            state_q      <= ST_TRAP;
          end else if (dec_halt) begin
            trap_cause_q <= CAUSE_BREAKPOINT;
            trap_pc_q    <= instr_pc_q;
            trap_value_q <= instr_pc_q;
            state_q      <= ST_HALT;
          end else if (dec_mem_start) begin
            mem_write_q  <= dec_mem_write;
            mem_addr_q   <= dec_mem_addr;
            mem_wdata_q  <= dec_mem_wdata;
            mem_wstrb_q  <= dec_mem_wstrb;
            mem_offset_q <= dec_mem_offset;
            mem_funct3_q <= funct3;
            mem_rd_q     <= rd;
            mem_pc_q     <= instr_pc_q;
            mem_instr_q  <= instr_q;
            state_q      <= ST_DMEM_REQ;
          end else begin
            if (dec_rd_we && (rd != 5'd0))
              regs[rd] <= dec_rd_wdata;
            pc_q         <= dec_next_pc;
            retire_valid <= 1'b1;
            retire_pc    <= instr_pc_q;
            retire_instr <= instr_q;
            retire_rd    <= dec_rd_we ? rd : 5'd0;
            retire_wdata <= (dec_rd_we && (rd != 5'd0)) ? dec_rd_wdata : 32'd0;
            state_q      <= ST_FETCH_REQ;
          end
        end

        ST_DMEM_REQ: begin
          if (dmem_req_valid && dmem_req_ready)
            state_q <= ST_DMEM_RSP;
        end

        ST_DMEM_RSP: begin
          if (dmem_rsp_valid && dmem_rsp_ready) begin
            if (dmem_rsp_err) begin
              trap_cause_q <= mem_write_q ? CAUSE_STORE_ACCESS_FAULT
                                          : CAUSE_LOAD_ACCESS_FAULT;
              trap_pc_q    <= mem_pc_q;
              trap_value_q <= mem_addr_q + {30'd0, mem_offset_q};
              state_q      <= ST_TRAP;
            end else begin
              if (!mem_write_q && (mem_rd_q != 5'd0))
                regs[mem_rd_q] <= load_result(dmem_rsp_rdata,
                                               mem_offset_q,
                                               mem_funct3_q);
              pc_q         <= mem_pc_q + 32'd4;
              retire_valid <= 1'b1;
              retire_pc    <= mem_pc_q;
              retire_instr <= mem_instr_q;
              retire_rd    <= mem_write_q ? 5'd0 : mem_rd_q;
              retire_wdata <= (!mem_write_q && (mem_rd_q != 5'd0))
                              ? load_result(dmem_rsp_rdata,
                                            mem_offset_q,
                                            mem_funct3_q)
                              : 32'd0;
              state_q <= ST_FETCH_REQ;
            end
          end
        end

        ST_HALT, ST_TRAP: state_q <= state_q;
        default: begin
          trap_cause_q <= CAUSE_ILLEGAL_INSTRUCTION;
          trap_pc_q    <= pc_q;
          trap_value_q <= 32'hffff_ffff;
          state_q      <= ST_TRAP;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (RESET_VECTOR[1:0] == 2'b00)
      else $error("RESET_VECTOR must be 4-byte aligned");
  end
`endif
endmodule
