`timescale 1ns / 1ps

// Four registers. Extra log fraction bits protect small radii near u = 1.
module awgn_log_pipeline (
    input wire clk,
    input wire [27:0] uniform_in,
    output reg [39:0] log_q832
);
    localparam signed [39:0] TWO_LN2_Q32 = 40'sd5954088944;
    (* rom_style="block" *) reg signed [39:0] table_log[0:1024];
    initial $readmemh("log_norm_q832.mem", table_log);

    wire [27:0] u = uniform_in == 0 ? 28'd1 : uniform_in;
    reg [4:0] leading;
    integer bit_index;
    always @* begin
        leading = 0;
        for (bit_index = 0; bit_index < 28; bit_index = bit_index + 1)
            if (u[bit_index]) leading = bit_index[4:0];
    end
    wire [4:0] exponent = 5'd28 - leading;
    wire [28:0] mantissa = {1'b0, u} << exponent;
    reg [10:0] address_1;
    reg [17:0] fraction_1, fraction_2;
    reg [4:0] exponent_1;
    reg signed [39:0] base_2, next_2, exponent_2, base_3, exponent_3;
    reg signed [63:0] product_3;
    wire signed [63:0] correction = (product_3 + 64'sd131072) >>> 18;

    always @(posedge clk) begin
        address_1 <= {1'b0, mantissa[27:18]};
        fraction_1 <= mantissa[17:0];
        exponent_1 <= exponent;

        base_2 <= table_log[address_1];
        next_2 <= table_log[address_1 + 11'd1];
        fraction_2 <= fraction_1;
        exponent_2 <= $signed({1'b0, exponent_1}) * TWO_LN2_Q32;

        product_3 <= (next_2 - base_2) * $signed({1'b0, fraction_2});
        base_3 <= base_2;
        exponent_3 <= exponent_2;

        log_q832 <= exponent_3 + base_3 + correction[39:0];
    end
endmodule

// Five registers. Keep the validated Q8.24 sqrt table and normalize in Q8.32.
module awgn_sqrt_pipeline (
    input wire clk,
    input wire [39:0] log_q832,
    output reg [31:0] radius_q428
);
    (* rom_style="block" *) reg [31:0] table_sqrt[0:1024];
    initial $readmemh("sqrt_norm_q824.mem", table_sqrt);

    reg [5:0] leading;
    integer bit_index;
    always @* begin
        leading = 0;
        for (bit_index = 0; bit_index < 40; bit_index = bit_index + 1)
            if (log_q832[bit_index]) leading = bit_index[5:0];
    end
    wire signed [6:0] log_exponent = $signed({1'b0, leading}) - 7'sd32;
    wire signed [6:0] scale = log_exponent >>> 1;
    wire signed [6:0] even_exponent = scale <<< 1;
    wire [39:0] mantissa = even_exponent >= 0
                            ? log_q832 >> even_exponent : log_q832 << -even_exponent;
    reg [10:0] address_1;
    reg [15:0] fraction_1, fraction_2;
    reg signed [5:0] scale_1, scale_2, scale_3, scale_4;
    reg zero_1, zero_2, zero_3, zero_4;
    reg [31:0] base_2, next_2, base_3, interp_4;
    reg [63:0] product_3;
    wire [63:0] extended = {32'd0, interp_4};
    wire [5:0] right_shift = -scale_4;
    wire [63:0] rounded_downscale = (extended + (64'd1 << (right_shift - 6'd1))) >> right_shift;

    always @(posedge clk) begin
        address_1 <= {1'b0, mantissa[33:24]};
        fraction_1 <= mantissa[23:8];
        scale_1 <= scale + 7'sd4;
        zero_1 <= log_q832 == 0;

        base_2 <= table_sqrt[address_1];
        next_2 <= table_sqrt[address_1 + 11'd1];
        fraction_2 <= fraction_1;
        scale_2 <= scale_1;
        zero_2 <= zero_1;

        product_3 <= (next_2 - base_2) * fraction_2;
        base_3 <= base_2;
        scale_3 <= scale_2;
        zero_3 <= zero_2;

        interp_4 <= base_3 + ((product_3 + 64'd32768) >> 16);
        scale_4 <= scale_3;
        zero_4 <= zero_3;

        if (zero_4) radius_q428 <= 0;
        else if (scale_4 >= 0) radius_q428 <= interp_4 << scale_4;
        else radius_q428 <= rounded_downscale[31:0];
    end
endmodule

// Five registers. A shared quarter-wave ROM supplies both functions.
module awgn_trig_pipeline (
    input wire clk,
    input wire [27:0] uniform_in,
    output reg signed [31:0] cosine_q428,
    output reg signed [31:0] sine_q428
);
    (* rom_style="block" *) reg [63:0] quarter_wave[0:1024];
    initial $readmemh("sin_pair_q428.mem", quarter_wave);

    wire [25:0] phase = uniform_in[25:0];
    wire [26:0] reflected_phase = 27'd67108864 - {1'b0, phase};
    reg [10:0] sin_address_1, cos_address_1;
    reg [15:0] sin_fraction_1, sin_fraction_2, cos_fraction_1, cos_fraction_2;
    reg [1:0] quadrant_1, quadrant_2, quadrant_3, quadrant_4;
    reg [63:0] sin_pair_2, cos_pair_2, sin_product_3, cos_product_3;
    reg [31:0] sin_base_3, cos_base_3;
    reg signed [31:0] sin_first_4, cos_first_4;

    always @(posedge clk) begin
        sin_address_1 <= {1'b0, phase[25:16]};
        cos_address_1 <= reflected_phase[26:16];
        sin_fraction_1 <= phase[15:0];
        cos_fraction_1 <= reflected_phase[15:0];
        quadrant_1 <= uniform_in[27:26];

        sin_pair_2 <= quarter_wave[sin_address_1];
        cos_pair_2 <= quarter_wave[cos_address_1];
        sin_fraction_2 <= sin_fraction_1;
        cos_fraction_2 <= cos_fraction_1;
        quadrant_2 <= quadrant_1;

        sin_base_3 <= sin_pair_2[63:32];
        cos_base_3 <= cos_pair_2[63:32];
        sin_product_3 <= (sin_pair_2[31:0] - sin_pair_2[63:32]) * sin_fraction_2;
        cos_product_3 <= (cos_pair_2[31:0] - cos_pair_2[63:32]) * cos_fraction_2;
        quadrant_3 <= quadrant_2;

        sin_first_4 <= sin_base_3 + ((sin_product_3 + 64'd32768) >> 16);
        cos_first_4 <= cos_base_3 + ((cos_product_3 + 64'd32768) >> 16);
        quadrant_4 <= quadrant_3;

        // theta = 2*pi*u - pi, so quadrant 0 starts at -pi.
        case (quadrant_4)
            2'd0: begin cosine_q428 <= -cos_first_4; sine_q428 <= -sin_first_4; end
            2'd1: begin cosine_q428 <=  sin_first_4; sine_q428 <= -cos_first_4; end
            2'd2: begin cosine_q428 <=  cos_first_4; sine_q428 <=  sin_first_4; end
            2'd3: begin cosine_q428 <= -sin_first_4; sine_q428 <=  cos_first_4; end
        endcase
    end
endmodule
