module rv32i_isa_coverage (
  input logic        clk,
  input logic        rst_n,
  input logic        retire_valid,
  input logic [31:0] retire_instr,
  input logic [31:0] retire_pc,
  input logic [4:0]  retire_rd,
  input logic        trap_valid,
  input logic [4:0]  trap_cause,
  input logic        imem_req_valid,
  input logic        imem_req_ready,
  input logic        dmem_req_valid,
  input logic        dmem_req_ready,
  input logic        dmem_req_write,
  input logic [3:0]  dmem_req_wstrb,
  input logic [1:0]  dmem_byte_offset,
  input logic        dmem_rsp_valid,
  input logic        dmem_rsp_ready,
  input logic        dmem_rsp_err
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  assign opcode = retire_instr[6:0];
  assign funct3 = retire_instr[14:12];
  assign funct7 = retire_instr[31:25];

  logic pending_branch;
  logic [31:0] pending_branch_pc;
  logic [2:0] pending_branch_funct3;
  logic imem_stalled;
  logic dmem_stalled;
  logic outstanding_write;

  covergroup isa_cg @(posedge clk);
    option.per_instance = 1;
    cp_opcode: coverpoint opcode iff (rst_n && retire_valid) {
      bins load     = {7'h03};
      bins misc_mem = {7'h0f};
      bins op_imm   = {7'h13};
      bins auipc    = {7'h17};
      bins store    = {7'h23};
      bins op       = {7'h33};
      bins lui      = {7'h37};
      bins branch   = {7'h63};
      bins jalr     = {7'h67};
      bins jal      = {7'h6f};
    }
    cp_branch_funct3: coverpoint funct3 iff (rst_n && retire_valid && opcode == 7'h63) {
      bins legal[] = {3'h0, 3'h1, 3'h4, 3'h5, 3'h6, 3'h7};
      illegal_bins reserved[] = {3'h2, 3'h3};
    }
    cp_load_funct3: coverpoint funct3 iff (rst_n && retire_valid && opcode == 7'h03) {
      bins legal[] = {3'h0, 3'h1, 3'h2, 3'h4, 3'h5};
      illegal_bins reserved[] = {3'h3, 3'h6, 3'h7};
    }
    cp_store_funct3: coverpoint funct3 iff (rst_n && retire_valid && opcode == 7'h23) {
      bins legal[] = {3'h0, 3'h1, 3'h2};
      illegal_bins reserved[] = {[3'h3:3'h7]};
    }
    cp_op_funct: coverpoint {funct7, funct3} iff (rst_n && retire_valid && opcode == 7'h33) {
      bins add  = {10'b0000000_000}; bins sub  = {10'b0100000_000};
      bins sll  = {10'b0000000_001}; bins slt  = {10'b0000000_010};
      bins sltu = {10'b0000000_011}; bins xor_ = {10'b0000000_100};
      bins srl  = {10'b0000000_101}; bins sra  = {10'b0100000_101};
      bins or_  = {10'b0000000_110}; bins and_ = {10'b0000000_111};
    }
    cp_op_imm_funct3: coverpoint funct3 iff (rst_n && retire_valid && opcode == 7'h13) {
      bins addi  = {3'h0}; bins slli = {3'h1}; bins slti  = {3'h2};
      bins sltiu = {3'h3}; bins xori = {3'h4}; bins shift_right = {3'h5};
      bins ori   = {3'h6}; bins andi = {3'h7};
    }
    cp_op_imm_shift: coverpoint {funct7, funct3}
      iff (rst_n && retire_valid && opcode == 7'h13 &&
           (funct3 == 3'h1 || funct3 == 3'h5)) {
      bins slli = {10'b0000000_001};
      bins srli = {10'b0000000_101};
      bins srai = {10'b0100000_101};
      illegal_bins bad_shift_encoding = default;
    }
    cp_jalr_funct3: coverpoint funct3 iff (rst_n && retire_valid && opcode == 7'h67) {
      bins legal = {3'h0};
      illegal_bins reserved = default;
    }
    cp_fence_funct3: coverpoint funct3 iff (rst_n && retire_valid && opcode == 7'h0f) {
      bins fence = {3'h0};
      illegal_bins unsupported = default;
    }
    cp_rd: coverpoint retire_rd iff (rst_n && retire_valid) {
      bins x0 = {0};
      bins caller_saved[] = {[1:7], [10:17], [28:31]};
      bins callee_saved[] = {[8:9], [18:27]};
    }
  endgroup

  covergroup trap_cg @(posedge clk);
    option.per_instance = 1;
    cp_cause: coverpoint trap_cause iff (rst_n && trap_valid) {
      bins instr_misaligned = {0};
      bins instr_fault      = {1};
      bins illegal          = {2};
      bins load_misaligned  = {4};
      bins load_fault       = {5};
      bins store_misaligned = {6};
      bins store_fault      = {7};
      bins ecall            = {11};
    }
  endgroup

  covergroup branch_outcome_cg with function sample(logic [2:0] branch_f3,
                                                     logic taken);
    cp_branch: coverpoint branch_f3 {
      bins legal[] = {3'h0, 3'h1, 3'h4, 3'h5, 3'h6, 3'h7};
    }
    cp_outcome: coverpoint taken { bins not_taken = {0}; bins taken = {1}; }
    branch_x_outcome: cross cp_branch, cp_outcome;
  endgroup

  covergroup request_cg with function sample(logic write,
                                              logic [1:0] byte_offset,
                                              logic [3:0] strobe,
                                              logic stalled);
    cp_kind: coverpoint write { bins load = {0}; bins store = {1}; }
    cp_offset: coverpoint byte_offset { bins lanes[] = {[0:3]}; }
    cp_strobe: coverpoint strobe iff (write) {
      bins byte_lanes[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
      bins half_lanes[] = {4'b0011, 4'b1100};
      bins word = {4'b1111};
      illegal_bins malformed = default;
    }
    cp_stall: coverpoint stalled { bins no_wait = {0}; bins waited = {1}; }
    kind_x_stall: cross cp_kind, cp_stall;
    kind_x_offset: cross cp_kind, cp_offset;
  endgroup

  covergroup response_cg with function sample(logic write, logic error);
    cp_kind: coverpoint write { bins load = {0}; bins store = {1}; }
    cp_error: coverpoint error { bins success = {0}; bins error = {1}; }
    kind_x_error: cross cp_kind, cp_error;
  endgroup

  covergroup fetch_stall_cg with function sample(logic stalled);
    cp_stall: coverpoint stalled { bins no_wait = {0}; bins waited = {1}; }
  endgroup

  isa_cg isa_cov = new();
  trap_cg trap_cov = new();
  branch_outcome_cg branch_cov = new();
  request_cg request_cov = new();
  response_cg response_cov = new();
  fetch_stall_cg fetch_cov = new();

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_branch       <= 1'b0;
      pending_branch_pc    <= 32'd0;
      pending_branch_funct3 <= 3'd0;
      imem_stalled         <= 1'b0;
      dmem_stalled         <= 1'b0;
      outstanding_write    <= 1'b0;
    end else begin
      if (imem_req_valid && !imem_req_ready)
        imem_stalled <= 1'b1;
      if (imem_req_valid && imem_req_ready) begin
        fetch_cov.sample(imem_stalled);
        imem_stalled <= 1'b0;
      end

      if (dmem_req_valid && !dmem_req_ready)
        dmem_stalled <= 1'b1;
      if (dmem_req_valid && dmem_req_ready) begin
        request_cov.sample(dmem_req_write, dmem_byte_offset,
                           dmem_req_wstrb, dmem_stalled);
        outstanding_write <= dmem_req_write;
        dmem_stalled <= 1'b0;
      end
      if (dmem_rsp_valid && dmem_rsp_ready)
        response_cov.sample(outstanding_write, dmem_rsp_err);

      if (retire_valid) begin
        if (pending_branch)
          branch_cov.sample(pending_branch_funct3,
                            retire_pc != (pending_branch_pc + 32'd4));
        pending_branch <= (retire_instr[6:0] == 7'h63);
        if (retire_instr[6:0] == 7'h63) begin
          pending_branch_pc <= retire_pc;
          pending_branch_funct3 <= retire_instr[14:12];
        end
      end
    end
  end
endmodule
