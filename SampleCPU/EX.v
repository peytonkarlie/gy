`include "lib/defines.vh"
module EX(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,

    output wire stallreq_for_ex,

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,

    output wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus,

    output wire data_sram_en,
    output wire [3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata
);

    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        // else if (flush) begin
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus;
        end
    end

    wire [31:0] ex_pc, inst;
    wire [11:0] alu_op;
    wire [7:0] hilo_op;
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire [3:0] data_ram_sel;
    wire rf_we;
    wire [7:0]mem_op;
    wire [31:0]hi_i,lo_i;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [31:0] rf_rdata1, rf_rdata2;
    reg is_in_delayslot;

    assign {
        lo_i,           // 228:197
        hi_i,           // 196:165
        hilo_op,        // 164:157
        mem_op,         // 156:149
        ex_pc,          // 148:117
        inst,           // 116:85
        alu_op,         // 84:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rf_rdata1,         // 63:32
        rf_rdata2          // 31:0
    } = id_to_ex_bus_r;

    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]};
    assign imm_zero_extend = {16'b0, inst[15:0]};
    assign sa_zero_extend = {27'b0,inst[10:6]};

    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : rf_rdata1;

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend : rf_rdata2;
    
    alu u_alu(
    	.alu_control (alu_op ),
        .alu_src1    (alu_src1    ),
        .alu_src2    (alu_src2    ),
        .alu_result  (alu_result  )
    );



    wire inst_sw,inst_lw;
    wire inst_lb,inst_lbu,inst_lh,inst_lhu,inst_sb,inst_sh;


    assign{inst_sw,inst_lw,inst_lb,inst_lbu,inst_lh,inst_lhu,inst_sb,inst_sh}=mem_op;

    wire [3:0] byte_sel;
    decoder_2_4 u_decoder_2_4(
    .in  (ex_result[1:0]),
    .out (byte_sel      )
    );


    assign data_ram_sel =inst_sb | inst_lb | inst_lbu ? byte_sel :
                         inst_sh | inst_lh | inst_lhu ? {{2{byte_sel[2]}},{2{byte_sel[0]}}} :
                         inst_sw | inst_lw            ? 4'b1111 : 4'b0000;

    assign data_sram_en     = data_ram_en;
    assign data_sram_wen    = {4{data_ram_wen}}&data_ram_sel;
    assign data_sram_addr   = ex_result; 
    assign data_sram_wdata  = inst_sb ? {4{rf_rdata2[7:0]}}  :
                              inst_sh ? {2{rf_rdata2[15:0]}} : 
                              rf_rdata2;


    wire inst_mflo,inst_mfhi,inst_mthi,inst_mtlo;
    wire inst_mult,inst_multu,inst_div,inst_divu;
    assign {inst_mflo,inst_mfhi,inst_mthi,inst_mtlo,inst_mult,inst_multu,inst_div,inst_divu}=hilo_op;
    wire hi_we,lo_we;
    wire [31:0] hi_o,lo_o;
    wire [63:0] mul_result,div_result;
    wire op_mul,op_div;
    assign op_mul=inst_mult | inst_multu;
    assign op_div=inst_div |inst_divu;

    // MUL part
    wire mul_signed = inst_mult; // 有符号乘法标记

    mul u_mul(
    	.clk        (clk            ),
        .resetn     (~rst           ),
        .mul_signed (mul_signed     ),
        .ina        (rf_rdata1      ), // 乘法源操作数1
        .inb        (rf_rdata2      ), // 乘法源操作数2
        .result     (mul_result     ) // 乘法结果 64bit
    );

    // DIV part
    wire div_ready_i;
    reg stallreq_for_div;
    assign stallreq_for_ex = stallreq_for_div;

    reg [31:0] div_opdata1_o;
    reg [31:0] div_opdata2_o;
    reg div_start_o;
    reg signed_div_o;

    div u_div(
    	.rst          (rst          ),
        .clk          (clk          ),
        .signed_div_i (signed_div_o ),
        .opdata1_i    (div_opdata1_o    ),
        .opdata2_i    (div_opdata2_o    ),
        .start_i      (div_start_o      ),
        .annul_i      (1'b0      ),
        .result_o     (div_result     ), // 除法结果 64bit
        .ready_o      (div_ready_i      )
    );

    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end

    // mul_result 和 div_result 可以直接使用
    assign hi_we=inst_mthi | inst_div | inst_divu | inst_mult | inst_multu;
    assign lo_we=inst_mtlo | inst_div | inst_divu | inst_mult | inst_multu;

    assign hi_o=inst_mthi ? rf_rdata1         :
                op_mul    ? mul_result[63:32] :
                op_div    ? div_result[63:32] : 32'b0;

    assign lo_o=inst_mtlo ? rf_rdata1         :
                op_mul    ? mul_result[31:0]  :
                op_div    ? div_result[31:0]  : 32'b0;

    assign ex_result = inst_mflo?lo_i
                     : inst_mfhi?hi_i
                     : alu_result;

    assign ex_to_mem_bus = {
        lo_o,           // 152:121
        lo_we,          // 120
        hi_o,           // 119:88
        hi_we,          // 87
        mem_op,         // 86:79
        data_ram_sel,   // 78:76
        ex_pc,          // 75:44
        data_ram_en,    // 43
        data_ram_wen,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };



    assign ex_to_rf_bus={
        lo_o,
        lo_we,
        hi_o,
        hi_we,
        rf_we,
        rf_waddr,
        ex_result
    };
    
    
endmodule