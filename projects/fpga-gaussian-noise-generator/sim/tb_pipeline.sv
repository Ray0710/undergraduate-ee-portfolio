`timescale 1ns / 1ps

module tb_pipeline;
    localparam integer DENSE_PAIRS = 100000;
    localparam integer REGISTER_STAGES = 11;
    localparam real Q28 = 268435456.0;
    localparam real PI = 3.141592653589793;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, in_valid = 0, dense = 0;
    reg [27:0] directed_u1 = 0, directed_u2 = 0;
    wire [31:0] rng_u1, rng_u2;
    wire [27:0] u1 = dense ? rng_u1[27:0] : directed_u1;
    wire [27:0] u2 = dense ? rng_u2[27:0] : directed_u2;
    wire out_valid;
    wire signed [31:0] z1, z2;

    xoshiro128ss_q4_28 #(.INITIAL_STATE(128'h3abaa123_3c763ca2_9e3779b9_243f6a88))
        rng_radius(.clk(clk), .rst(rst), .q428(rng_u1));
    xoshiro128ss_q4_28 #(.INITIAL_STATE(128'h0e552dd8_90e088be_3295fbb5_d3021917))
        rng_angle(.clk(clk), .rst(rst), .q428(rng_u2));
    awgn_box_muller_pipeline dut(.clk(clk), .rst(rst), .in_valid(in_valid),
        .u1(u1), .u2(u2), .out_valid(out_valid), .z1(z1), .z2(z2));

    reg pending [0:REGISTER_STAGES-1];
    reg pending_dense [0:REGISTER_STAGES-1];
    real expected_z1 [0:REGISTER_STAGES-1], expected_z2 [0:REGISTER_STAGES-1];
    reg [27:0] expected_u1 [0:REGISTER_STAGES-1], expected_u2 [0:REGISTER_STAGES-1];
    integer cycle = 0, checked = 0, dense_checked = 0, previous_dense = 0;
    integer output_file, slot, i;
    real radius, theta, error_z1, error_z2, max_error = 0;

    always @(posedge clk) begin
        cycle = cycle + 1;
        // A slot is read on the eleventh edge, including the accepting edge.
        if (rst) begin
            for (slot = 0; slot < REGISTER_STAGES; slot = slot + 1) pending[slot] = 0;
        end else begin
            slot = (cycle + REGISTER_STAGES - 1) % REGISTER_STAGES;
            pending[slot] = in_valid;
            if (in_valid) begin
                radius = $sqrt(-2.0 * $ln($itor(u1 == 0 ? 28'd1 : u1) / Q28));
                theta = 2.0 * PI * $itor(u2) / Q28 - PI;
                expected_z1[slot] = radius * $cos(theta);
                expected_z2[slot] = radius * $sin(theta);
                expected_u1[slot] = u1;
                expected_u2[slot] = u2;
                pending_dense[slot] = dense;
            end
        end

        slot = cycle % REGISTER_STAGES;
        #1;
        if (out_valid !== pending[slot]) $fatal(1, "Wrong valid at cycle %0d", cycle);
        if (pending[slot]) begin
            if ((^{z1, z2}) === 1'bx) $fatal(1, "Unknown result at cycle %0d", cycle);
            error_z1 = $itor(z1) / Q28 - expected_z1[slot];
            error_z2 = $itor(z2) / Q28 - expected_z2[slot];
            if (error_z1 < 0) error_z1 = -error_z1;
            if (error_z2 < 0) error_z2 = -error_z2;
            if (error_z1 > max_error) max_error = error_z1;
            if (error_z2 > max_error) max_error = error_z2;
            if (error_z1 > 0.00002 || error_z2 > 0.00002)
                $fatal(1, "Box-Muller error: u1=%07h u2=%07h z1=%0d z2=%0d error=%g,%g",
                    expected_u1[slot], expected_u2[slot], z1, z2, error_z1, error_z2);
            checked = checked + 1;
            if (pending_dense[slot]) begin
                if (dense_checked != 0 && cycle != previous_dense + 1)
                    $fatal(1, "Gap in continuous output at pair %0d", dense_checked);
                previous_dense = cycle;
                dense_checked = dense_checked + 1;
                $fwrite(output_file, "%0d %0d\n", z1, z2);
            end
        end
    end

    task drive(input [27:0] radius_uniform, angle_uniform);
        @(negedge clk);
        in_valid = 1;
        directed_u1 = radius_uniform;
        directed_u2 = angle_uniform;
    endtask

    initial begin
        output_file = $fopen("pipeline_gaussian_q428.txt", "w");
        if (!output_file) $fatal(1, "Cannot open output file");
        $fdisplay(output_file, "z1_q428 z2_q428");
        repeat (3) @(negedge clk);
        rst = 0;
        drive(28'h0000000, 28'h0000000);
        drive(28'h0000001, 28'h4000000);
        drive(28'h0000002, 28'h8000000);
        drive(28'h0000003, 28'hc000000);
        drive(28'hfffffff, 28'hfffffff);
        @(negedge clk);
        in_valid = 0;
        drive(28'hfffff00, 28'h3ffffff);
        drive(28'h8000000, 28'h7ffffff);
        drive(28'h8000001, 28'hbffffff);
        drive(28'h0000001, 28'h1554000);
        @(negedge clk);
        in_valid = 0;
        repeat (REGISTER_STAGES) @(negedge clk);

        drive(28'h8123456, 28'hf012345);
        @(negedge clk);
        rst = 1; // Flush a pair still in flight.
        in_valid = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        dense = 1;
        in_valid = 1;
        repeat (DENSE_PAIRS) @(negedge clk);
        in_valid = 0;
        dense = 0;
        repeat (REGISTER_STAGES) @(negedge clk);

        if (dense_checked != DENSE_PAIRS || checked != DENSE_PAIRS + 9)
            $fatal(1, "Expected %0d consecutive pairs plus 9 directed pairs, checked %0d (%0d consecutive)",
                DENSE_PAIRS, checked, dense_checked);
        $fclose(output_file);
        $display("PASS pipeline: %0d consecutive pairs, 11 stages, 1 clock/pair; max absolute error=%g", dense_checked, max_error);
        $finish;
    end
endmodule
