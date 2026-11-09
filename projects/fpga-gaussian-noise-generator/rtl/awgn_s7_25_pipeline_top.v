`timescale 1ns / 1ps

module awgn_s7_25_pipeline_top #(parameter UART_DIV = 12) (
    input wire CLK12MHZ, RESET_BTN,
    output wire [3:0] LED,
    output wire UART_TX
);
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_pipe = 2'b11;
    always @(posedge CLK12MHZ or posedge RESET_BTN)
        if (RESET_BTN) reset_pipe <= 2'b11;
        else reset_pipe <= {reset_pipe[0], 1'b0};
    wire rst = reset_pipe[1];

    wire valid, busy;
    wire signed [31:0] z1, z2;
    wire send = valid && !busy;
    reg [15:0] sequence_number;
    reg last_sign;
    reg [23:0] heartbeat;

    awgn_continuous_core core(.clk(CLK12MHZ), .rst(rst), .valid(valid), .z1(z1), .z2(z2));
    // UART monitors a subset of core outputs. The sequence counts transmitted packets.
    awgn_uart_packet #(.DIV(UART_DIV)) tx(
        .clk(CLK12MHZ), .rst(rst), .send(send),
        .payload({z2, z1, sequence_number, 16'h5AA5}), .tx(UART_TX), .busy(busy)
    );

    always @(posedge CLK12MHZ) begin
        if (rst) begin
            sequence_number <= 0;
            last_sign <= 0;
            heartbeat <= 0;
        end else begin
            heartbeat <= heartbeat + 1'b1;
            if (send) begin
                sequence_number <= sequence_number + 1'b1;
                last_sign <= z1[31];
            end
        end
    end
    assign LED = {heartbeat[23], last_sign, sequence_number[7], busy};
endmodule
