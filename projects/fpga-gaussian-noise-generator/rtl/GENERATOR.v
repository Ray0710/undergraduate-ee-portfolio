// Working copy v2, 2026-11-07. Target wrapper: awgn_s7_25_top.
// See 04_報告/修正說明.md for changes, limits and validation.
`timescale 1ns / 1ps

module gaussian_noise_generator_fsm_4_28 #(
    parameter WIDTH = 32,
    parameter signed [31:0] GAIN_Q28 = 32'sh10000000 // =1.0；如需校正可改 0x1031AC68
)(
    input  wire clk,
    input  wire rst,
    input  wire sample_enable, // start a new pair only when enabled
    output reg  signed [31:0] z1, z2,         // Q4.28
    output reg  signed [95:0] z1_96, z2_96,   // Q12.84（供檔案輸出）
    output wire signed [31:0] cos, sin,       // Q4.28
    output wire signed [31:0] sqrt, ln,       // sqrt:Q4.28, ln:Q8.24
    output wire signed [31:0] sqrt_in, ln_in, // 觀察用
    output wire signed [31:0] theta_q428,     // [-pi,pi) Q4.28（未做象限符號）
    output reg  valid
);
    wire [31:0] u1_live, u2_live;
    reg [31:0] u1_q428, u2_q428;
    reg [27:0] angle_rnd;
    reg cs_hold, ss_hold;
    // Fixed, reproducible streams. U2 starts 2^64 steps after U1 via the
    // reference xoshiro128** jump() applied offline. Word order is s0,s1,s2,s3.
    xoshiro128ss_q4_28 #(.INITIAL_STATE(128'h3abaa123_3c763ca2_9e3779b9_243f6a88))
        U1(.clk(clk), .rst(rst), .q428(u1_live));
    xoshiro128ss_q4_28 #(.INITIAL_STATE(128'h0e552dd8_90e088be_3295fbb5_d3021917))
        U2(.clk(clk), .rst(rst), .q428(u2_live));

    wire [23:0] rnd24_a, rnd24_b;
    wire [27:0] rnd28_a, rnd28_b;
    wire [3:0]  rnd4_sqrt;
    lfsr24_4 RND(.clk(clk), .rst(rst),
                 .rnd24_a(rnd24_a), .rnd24_b(rnd24_b),
                 .rnd28_a(rnd28_a), .rnd28_b(rnd28_b),
                 .rnd4(rnd4_sqrt));

    wire signed [31:0] theta_raw;
    q428_to_angle ANG(.q428_rand(u2_q428), .rnd28(angle_rnd), .theta_q428(theta_raw));
    assign theta_q428 = theta_raw;

    wire signed [31:0] theta_cordic;
    wire cs_sig, ss_sig;
    cordic_angle_mapper MAP(.theta_in(theta_raw), .theta_cordic(theta_cordic),
                            .cos_sign(cs_sig), .sin_sign(ss_sig));

    // ===== ln / sqrt =====
    wire ln_done, sqrt_done, sc_done;
    reg ln_start=0, sqrt_start=0, sc_start=0;
    wire signed [31:0] ln_out_q824;
    cordic_ln_fsm_lutmix LN(
        .clk(clk), .rst(rst), .start(ln_start), .x(u1_q428), .rnd24(rnd24_a),
        .ln_out(ln_out_q824), .done(ln_done)
    );
    assign ln     = ln_out_q824;
    assign ln_in  = u1_q428;

    wire signed [31:0] sqrt_out_q428;
    sqrt_lutmix SQ(
        .clk(clk), .rst(rst), .start(sqrt_start), .x824(ln_out_q824),
        .rnd24(rnd24_b), .rnd4(rnd4_sqrt),
        .sqrt_out(sqrt_out_q428), .done(sqrt_done)
    );
    assign sqrt    = sqrt_out_q428;
    assign sqrt_in = ln_out_q824;

    // ===== sin/cos（CORDIC） =====
    wire signed [31:0] cos_raw, sin_raw;
    cordic_sin_cos_fsm SINCOS(
        .clk(clk), .rst(rst), .start(sc_start), .theta(theta_cordic),
        .cos_out(cos_raw), .sin_out(sin_raw), .done(sc_done)
    );
    assign cos = cs_hold ? -cos_raw :  cos_raw;
    assign sin = ss_hold ? -sin_raw :  sin_raw;

    wire signed [63:0] sqrt_scaled_full = $signed(sqrt_out_q428) * $signed(GAIN_Q28); // Q8.56
    wire signed [95:0] z1_prod96 = $signed(sqrt_scaled_full) * $signed(cos); // Q12.84
    wire signed [95:0] z2_prod96 = $signed(sqrt_scaled_full) * $signed(sin); // Q12.84

    // stochastic rounding >>>56：用 56-bit bump
    wire [55:0] rnd56_a = {rnd28_a, rnd28_b};
    wire [55:0] rnd56_b = {rnd28_b, rnd28_a};
    wire signed [95:0] bump1 = {{40{1'b0}}, rnd56_a};
    wire signed [95:0] bump2 = {{40{1'b0}}, rnd56_b};
    wire signed [31:0] z1_q428_sr = (z1_prod96 + bump1) >>> 56;
    wire signed [31:0] z2_q428_sr = (z2_prod96 + bump2) >>> 56;

    reg [1:0] st=0;
    always @(posedge clk) begin
        if (rst) begin
            st<=0; ln_start<=0; sqrt_start<=0; sc_start<=0; valid<=0;
            z1<=0; z2<=0; z1_96<=0; z2_96<=0;
            u1_q428<=1; u2_q428<=1; angle_rnd<=0; cs_hold<=0; ss_hold<=0;
        end else case(st)
            0: begin
                valid<=0;
                if (sample_enable) begin
                    u1_q428<=u1_live; u2_q428<=u2_live; angle_rnd<=rnd28_a;
                    ln_start<=1; st<=1;
                end
            end
            1: begin ln_start<=0; if(ln_done) begin sqrt_start<=1; st<=2; end end
            2: begin sqrt_start<=0; if(sqrt_done) begin sc_start<=1; cs_hold<=cs_sig; ss_hold<=ss_sig; st<=3; end end
            3: begin
                sc_start<=0;
                if (sc_done) begin
                    z1_96 <= z1_prod96; z2_96 <= z2_prod96;
                    z1    <= z1_q428_sr; z2    <= z2_q428_sr;
                    valid <= 1; st<=0;
                end else valid<=0;
            end
        endcase
    end
endmodule
//////////////////////////////////////////////////////
// Angle Mapper
//////////////////////////////////////////////////////
    module cordic_angle_mapper #(
    parameter WIDTH = 32
)(
    input  signed [WIDTH-1:0] theta_in,      // Q4.28, [-PI, PI)
    output reg signed [WIDTH-1:0] theta_cordic, // [0, PI/2]
    output reg cos_sign,
    output reg sin_sign
);
    localparam signed [WIDTH-1:0] TWO_PI = 32'sd1686629713;
    localparam signed [WIDTH-1:0] PI     = 32'sd843314857;
    localparam signed [WIDTH-1:0] PI_2   = 32'sd421657428;
    reg signed [WIDTH-1:0] t,a; reg [1:0] q;
    always @(*) begin
        if (theta_in < -PI)       t = theta_in + TWO_PI;
        else if (theta_in >= PI)  t = theta_in - TWO_PI;
        else                      t = theta_in;
        if (t < 0) t = t + TWO_PI;
        if (t < PI_2)           begin q=2'd0; a=t;                end
        else if (t < PI)        begin q=2'd1; a=t-PI_2;           end
        else if (t < (PI+PI_2)) begin q=2'd2; a=t-PI;             end
        else                    begin q=2'd3; a=t-(PI+PI_2);      end
        case(q)
            2'd0: begin theta_cordic=a;        cos_sign=0; sin_sign=0; end
            2'd1: begin theta_cordic=PI_2-a;   cos_sign=1; sin_sign=0; end
            2'd2: begin theta_cordic=a;   cos_sign=1; sin_sign=1; end
            2'd3: begin theta_cordic=PI_2-a;        cos_sign=0; sin_sign=1; end
        endcase
    end
endmodule
//////////////////////////////////////////////////////
// Angle Transformer(0 ~ 1 to -pi ~ pi)
//////////////////////////////////////////////////////
    module q428_to_angle #(
        parameter WIDTH = 32
    )(
        input  wire signed [WIDTH-1:0] q428_rand,  // Q4.28 in [0,1)
        input  wire [27:0]             rnd28,      // 28-bit 隨機位（來自小 LFSR）
        output wire signed [WIDTH-1:0] theta_q428  // Q4.28 in [-pi,pi)
    );
        localparam signed [WIDTH-1:0] TWO_PI_Q428 = 32'sd1686629713; // Q4.28
        localparam signed [WIDTH-1:0] PI_Q428     = 32'sd843314857;  // Q4.28

        // Q4.28 * Q4.28 = Q8.56
        wire signed [63:0] mult_full  = $signed(q428_rand) * $signed(TWO_PI_Q428); // Q8.56
        wire signed [63:0] pi_q856    = $signed(PI_Q428) <<< 28;                   // Q8.56
        wire signed [63:0] theta_full = mult_full - pi_q856;                       // Q8.56

        // ===== 隨機捨入 >>>28 =====
        wire signed [63:0] bump       = {{36{1'b0}}, rnd28};                       // +U[0,2^-28)
        assign theta_q428 = (theta_full + bump) >>> 28;                            // Q4.28
    endmodule
//////////////////////////////////////////////////////
// FSM-based cordic_sin_cos module
//////////////////////////////////////////////////////
    module cordic_sin_cos_fsm #(
    parameter WIDTH = 32,
    parameter ITER  = 28
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] theta,   // 建議 [0,PI/2]
    output reg  signed [31:0] cos_out, // Q4.28
    output reg  signed [31:0] sin_out, // Q4.28
    output reg                done
);
    reg signed [31:0] atan_table [0:27];

    initial begin
        atan_table[0]  = 32'd210828714;
        atan_table[1]  = 32'd124459457;
        atan_table[2]  = 32'd65760959;
        atan_table[3]  = 32'd33381290;
        atan_table[4]  = 32'd16755422;
        atan_table[5]  = 32'd8385879;
        atan_table[6]  = 32'd4193963;
        atan_table[7]  = 32'd2097109;
        atan_table[8]  = 32'd1048571;
        atan_table[9]  = 32'd524287;
        atan_table[10] = 32'd262144;
        atan_table[11] = 32'd131072;
        atan_table[12] = 32'd65536;
        atan_table[13] = 32'd32768;
        atan_table[14] = 32'd16384;
        atan_table[15] = 32'd8192;
        atan_table[16] = 32'd4096;
        atan_table[17] = 32'd2048;
        atan_table[18] = 32'd1024;
        atan_table[19] = 32'd512;
        atan_table[20] = 32'd256;
        atan_table[21] = 32'd128;
        atan_table[22] = 32'd64;
        atan_table[23] = 32'd32;
        atan_table[24] = 32'd16;
        atan_table[25] = 32'd8;
        atan_table[26] = 32'd4;
        atan_table[27] = 32'd2;
    end

    localparam signed [31:0] K = 32'sd163008218; // Q4.28

    localparam IDLE   = 2'd0;
    localparam ITER_S = 2'd1;
    localparam DONE_S = 2'd2;

    reg [1:0]  state;
    reg [5:0]  i;
    reg signed [31:0] x,y,z;

    // CORDIC result is already Q4.28; preserve the computed integer.
    function signed [31:0] rne_q428;
        input signed [31:0] v;
        begin
            rne_q428 = v; // already Q4.28: no bits discarded, no rounding bias
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            i       <= 0;
            x       <= 0;
            y       <= 0;
            z       <= 0;
            cos_out <= 0;
            sin_out <= 0;
            done    <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        x     <= K;
                        y     <= 0;
                        z     <= theta;
                        i     <= 0;
                        state <= ITER_S;
                    end
                end

                ITER_S: begin
                    if (i < ITER) begin
                        if (z >= 0) begin
                            x <= x - (y >>> i);
                            y <= y + (x >>> i);
                            z <= z - atan_table[i];
                        end else begin
                            x <= x + (y >>> i);
                            y <= y - (x >>> i);
                            z <= z + atan_table[i];
                        end
                        i <= i + 1;
                    end else begin
                        cos_out <= rne_q428(x);
                        sin_out <= rne_q428(y);
                        done    <= 1;
                        state   <= DONE_S;
                    end
                end

                DONE_S: begin
                    // 等 start 放掉再回到 IDLE，避免多發一次 done
                    if (!start) begin
                        state <= IDLE;
                        done  <= 0;
                    end
                end

                default: begin
                    // 防呆，某個 flip-flop 被打亂時可以自我恢復
                    state   <= IDLE;
                    done    <= 0;
                    cos_out <= 0;
                    sin_out <= 0;
                end
            endcase
        end
    end
endmodule
// xoshiro128** 1.1, adapted from Blackman and Vigna's public domain reference.
// https://prng.di.unimi.it/xoshiro128starstar.c
module xoshiro128ss_q4_28 #(
    parameter [127:0] INITIAL_STATE = 128'd1
)(
    input  wire clk,
    input  wire rst,
    output wire [31:0] q428
);
    localparam [127:0] RESET_STATE = INITIAL_STATE == 0 ? 128'd1 : INITIAL_STATE;
    reg [31:0] s0, s1, s2, s3;

    wire [31:0] s2_xor = s2 ^ s0;
    wire [31:0] s3_xor = s3 ^ s1;
    wire [31:0] times5 = s1 + (s1 << 2);
    wire [31:0] rot7 = {times5[24:0], times5[31:25]};
    wire [31:0] scrambled = rot7 + (rot7 << 3);
    wire [27:0] fraction = scrambled[31:4];

    // Use the upper 28 bits and keep u in (0,1) for the log stage.
    assign q428 = fraction == 0 ? 32'd1 : {4'b0, fraction};

    always @(posedge clk) begin
        if (rst) begin
            {s0, s1, s2, s3} <= RESET_STATE;
        end else begin
            s0 <= s0 ^ s3_xor;
            s1 <= s1 ^ s2_xor;
            s2 <= s2_xor ^ (s1 << 9);
            s3 <= {s3_xor[20:0], s3_xor[31:21]};
        end
    end
endmodule
///////////////////////////////////////////////////////////
// FSM-based ln module, input/output Q4.28, internal Q8.24
///////////////////////////////////////////////////////////
// Corrected LUT engines are in lut_math.v.

module lfsr24_4(
    input  wire clk,
    input  wire rst,
    output wire [23:0] rnd24_a,
    output wire [23:0] rnd24_b,
    output wire [27:0] rnd28_a,
    output wire [27:0] rnd28_b,
    output wire [3:0]  rnd4
);
    reg [24:0] s24a=25'h1FFFFF1, s24b=25'h0ABCDE1;
    reg [29:0] s28a=30'h3ABCDE1, s28b=30'h1FEDC23;
    reg [7:0]  s8  =8'hA7;
    always @(posedge clk) begin
        if (rst) begin
            s24a<=25'h1FFFFF1; s24b<=25'h0ABCDE1;
            s28a<=30'h3ABCDE1; s28b<=30'h1FEDC23;
            s8<=8'hA7;
        end else begin
            s24a <= {s24a[23:0], s24a[24]^s24a[23]^s24a[22]^s24a[17]};
            s24b <= {s24b[23:0], s24b[24]^s24b[22]^s24b[2]^s24b[0]};
            s28a <= {s28a[28:0], s28a[29]^s28a[5]^s28a[3]^s28a[0]};
            s28b <= {s28b[28:0], s28b[29]^s28b[7]^s28b[6]^s28b[1]};
            s8   <= {s8[6:0], s8[7]^s8[5]^s8[4]^s8[3]};
        end
    end
    // These slices must be valid even when reset rewrites the declaration seed.
    assign rnd24_a = s24a[23:0];
    assign rnd24_b = s24b[23:0];
    assign rnd28_a = s28a[27:0];
    assign rnd28_b = s28b[27:0];
    assign rnd4    = s8[3:0];
endmodule
