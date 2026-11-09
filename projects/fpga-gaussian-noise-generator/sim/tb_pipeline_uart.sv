`timescale 1ns / 1ps

module tb_pipeline_uart;
    localparam integer DIV = 12;
    localparam integer PACKETS = 64;
    localparam integer PAIR_CLOCKS = 12 * 10 * DIV + 1;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    wire tx;
    wire [3:0] led;
    awgn_s7_25_pipeline_top #(.UART_DIV(DIV)) dut(
        .CLK12MHZ(clk), .RESET_BTN(reset), .LED(led), .UART_TX(tx));

    reg [95:0] expected [0:PACKETS-1], received;
    reg [7:0] byte_value;
    integer sent = 0, cycle = 0, last_send = 0;
    integer packet_index, byte_index, bit_index;

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (!dut.rst && sent > 0 && dut.valid !== 1'b1)
            $fatal(1, "Core stalled after UART started at cycle %0d", cycle);
        if (!dut.rst && dut.send) begin
            if (sent > 0 && cycle - last_send != PAIR_CLOCKS)
                $fatal(1, "Send interval %0d, expected %0d", cycle - last_send, PAIR_CLOCKS);
            if (dut.sequence_number !== sent[15:0]) $fatal(1, "Wrong packet sequence");
            if ((^{dut.z1, dut.z2}) === 1'bx) $fatal(1, "Unknown UART sample");
            if (sent < PACKETS) expected[sent] = {dut.z2, dut.z1, sent[15:0], 16'h5AA5};
            last_send = cycle;
            sent = sent + 1;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        reset = 0;
        for (packet_index = 0; packet_index < PACKETS; packet_index = packet_index + 1) begin
            for (byte_index = 0; byte_index < 12; byte_index = byte_index + 1) begin
                @(negedge tx);
                repeat (DIV / 2) @(posedge clk); #1;
                if (tx !== 1'b0) $fatal(1, "UART start bit");
                for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                    repeat (DIV) @(posedge clk); #1;
                    byte_value[bit_index] = tx;
                end
                repeat (DIV) @(posedge clk); #1;
                if (tx !== 1'b1) $fatal(1, "UART stop bit");
                received[byte_index*8+:8] = byte_value;
            end
            if (received !== expected[packet_index]) $fatal(1, "UART packet %0d mismatch", packet_index);
        end
        $display("PASS UART: %0d packets match, %0d clocks/packet, core stayed valid", PACKETS, PAIR_CLOCKS);
        $finish;
    end

    initial begin #2000000; $fatal(1, "UART timeout"); end
endmodule
