`timescale 1ns / 1ps

// The consumer can use every valid output. There is no downstream backpressure.
module awgn_box_muller_pipeline (
    input wire clk, rst, in_valid,
    input wire [27:0] u1, u2,
    output wire out_valid,
    output reg signed [31:0] z1, z2
);
    localparam integer PIPE_STAGES = 11;
    reg [PIPE_STAGES-1:0] valid_pipe;
    wire [39:0] log_q832;
    wire [31:0] radius_q428;
    wire signed [31:0] trig_cos, trig_sin;
    reg signed [31:0] cos_aligned[0:3], sin_aligned[0:3];
    reg signed [63:0] product_z1, product_z2;
    integer stage;

    awgn_log_pipeline log_stage(.clk(clk), .uniform_in(u1), .log_q832(log_q832));
    awgn_sqrt_pipeline sqrt_stage(.clk(clk), .log_q832(log_q832), .radius_q428(radius_q428));
    awgn_trig_pipeline trig_stage(.clk(clk), .uniform_in(u2), .cosine_q428(trig_cos), .sine_q428(trig_sin));

    always @(posedge clk) begin
        if (rst) valid_pipe <= 0;
        else valid_pipe <= {valid_pipe[PIPE_STAGES-2:0], in_valid};

        // The radius path has nine registers and the angle path has five.
        cos_aligned[0] <= trig_cos;
        sin_aligned[0] <= trig_sin;
        for (stage = 1; stage < 4; stage = stage + 1) begin
            cos_aligned[stage] <= cos_aligned[stage-1];
            sin_aligned[stage] <= sin_aligned[stage-1];
        end

        product_z1 <= $signed(radius_q428) * cos_aligned[3];
        product_z2 <= $signed(radius_q428) * sin_aligned[3];
        // Q8.56 to Q4.28, nearest with ties toward positive infinity.
        z1 <= (product_z1 + 64'sd134217728) >>> 28;
        z2 <= (product_z2 + 64'sd134217728) >>> 28;
    end
    assign out_valid = valid_pipe[PIPE_STAGES-1];
endmodule

module awgn_continuous_core (
    input wire clk, rst,
    output wire valid,
    output wire signed [31:0] z1, z2
);
    wire [31:0] u1, u2;
    xoshiro128ss_q4_28 #(.INITIAL_STATE(128'h3abaa123_3c763ca2_9e3779b9_243f6a88))
        rng_radius(.clk(clk), .rst(rst), .q428(u1));
    xoshiro128ss_q4_28 #(.INITIAL_STATE(128'h0e552dd8_90e088be_3295fbb5_d3021917))
        rng_angle(.clk(clk), .rst(rst), .q428(u2));
    awgn_box_muller_pipeline transform(
        .clk(clk), .rst(rst), .in_valid(1'b1), .u1(u1[27:0]), .u2(u2[27:0]),
        .out_valid(valid), .z1(z1), .z2(z2)
    );
endmodule
