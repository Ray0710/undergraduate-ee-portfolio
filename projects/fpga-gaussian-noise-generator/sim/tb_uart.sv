`timescale 1ns/1ps
module tb_uart;
    reg clk=0; always #5 clk=~clk;
    reg reset=1; wire tx; wire[3:0] led;
    localparam DIV=104;
    awgn_s7_25_top #(.UART_DIV(DIV)) dut(.CLK12MHZ(clk),.RESET_BTN(reset),.LED(led),.UART_TX(tx));
    reg[95:0] expected[0:31];
    reg[95:0] received;
    reg[7:0] bytevalue;
    integer sent=0,i,j,b;
    integer cycle=0, previous_pair=0;
    real u1, u2, radius, angle, error_z1, error_z2;
    localparam real Q28=268435456.0;
    localparam real PI=3.141592653589793;
    localparam integer PAIR_CLOCKS=12*10*DIV+43;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!dut.rst && dut.valid) begin
            if(dut.busy)$fatal(1,"Packet overrun");
            if((^{dut.z1,dut.z2,dut.core.u1_q428,dut.core.u2_q428,dut.core.angle_rnd}) === 1'bx)
                $fatal(1,"Unknown signal in pair %0d",sent);
            if(sent>0 && cycle-previous_pair!=PAIR_CLOCKS)
                $fatal(1,"Pair interval %0d, expected %0d",cycle-previous_pair,PAIR_CLOCKS);
            previous_pair=cycle;

            // Check board-level numerical results as well as framing, including pair 0.
            u1=$itor(dut.core.u1_q428)/Q28;
            u2=$itor(dut.core.u2_q428)/Q28;
            radius=$sqrt(-2.0*$ln(u1));
            angle=2.0*PI*u2-PI;
            error_z1=$itor(dut.z1)/Q28-radius*$cos(angle);
            error_z2=$itor(dut.z2)/Q28-radius*$sin(angle);
            if(error_z1>0.00002 || error_z1< -0.00002 || error_z2>0.00002 || error_z2< -0.00002)
                $fatal(1,"Pair %0d differs from Box-Muller: %g, %g",sent,error_z1,error_z2);
            expected[sent]={dut.z2,dut.z1,dut.sequence_number,16'h5AA5};
            sent=sent+1;
        end
    end
    initial begin
        repeat(5)@(negedge clk); reset=0;
        for(i=0;i<24;i=i+1) begin
            for(j=0;j<12;j=j+1) begin
                @(negedge tx);
                repeat(DIV+DIV/2)@(posedge clk); #1;
                bytevalue[0]=tx;
                for(b=1;b<8;b=b+1) begin repeat(DIV)@(posedge clk); #1; bytevalue[b]=tx; end
                repeat(DIV)@(posedge clk); #1;
                if(tx!==1'b1)$fatal(1,"UART stop bit");
                received[j*8+:8]=bytevalue;
            end
            if(received!==expected[i])$fatal(1,"UART packet %d mismatch",i);
        end
        $display("PASS UART: 24 complete packets, start-up numerical check, %0d clocks/pair",PAIR_CLOCKS);
        $finish;
    end
    initial begin #10000000; $fatal(1,"UART timeout"); end
endmodule
