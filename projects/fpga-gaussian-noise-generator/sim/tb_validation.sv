`timescale 1ns/1ps
module tb_validation;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,enable=0;
    wire signed [31:0] z1,z2,lnv,sqv,cv,sv,uin,theta;
    wire valid;
    gaussian_noise_generator_fsm_4_28 dut(
        .clk(clk),.rst(rst),.sample_enable(enable),.z1(z1),.z2(z2),.valid(valid),
        .ln(lnv),.sqrt(sqv),.cos(cv),.sin(sv),.ln_in(uin),.theta_q428(theta),
        .sqrt_in(),.z1_96(),.z2_96()
    );
    reg ls=0,ss=0;
    reg signed [31:0] lx=1;
    reg [31:0] sx=0;
    wire signed [31:0] ly;
    wire [31:0] sy;
    wire ld,sd;
    cordic_ln_fsm_lutmix logtest(.clk(clk),.rst(rst),.start(ls),.x(lx),.rnd24(24'h812345),.ln_out(ly),.done(ld));
    sqrt_lutmix sqtest(.clk(clk),.rst(rst),.start(ss),.x824(sx),.rnd24(24'h345678),.rnd4(4'h0),.sqrt_out(sy),.done(sd));
    integer i,n,f,unitfile,seed=32'h36245211,cycles=0,prevcycle=0;
    real expected,err,maximum_ln=0,maximum_sqrt=0,maximum_z=0,u,a,r,e1,e2;
    reg [31:0] value;
    reg signed [31:0] first_z1[0:31],first_z2[0:31];
    always @(posedge clk) cycles<=cycles+1;
    task log_case(input integer v);
        begin
            @(negedge clk); lx=v; ls=1;
            @(negedge clk); ls=0; lx=32'h08012345; // input must be latched
            wait(ld); @(negedge clk);
            expected=-2.0*$ln((v<1?1:(v>268435456?268435456:v))/268435456.0);
            err=$itor(ly)/16777216.0-expected; if(err<0)err=-err;
            if(err>maximum_ln) maximum_ln=err;
            if(err>0.000002) $fatal(1,"LN input=%d error=%g",v,err);
            $fdisplay(unitfile,"log %0d %0d %.12f %.12g",v,ly,expected,err);
            repeat(2) @(negedge clk);
        end
    endtask
    task sqrt_case(input reg[31:0] v);
        begin
            @(negedge clk); sx=v; ss=1;
            @(negedge clk); ss=0; sx=32'h02012345;
            wait(sd); @(negedge clk);
            expected=$sqrt(v/16777216.0);
            err=sy/268435456.0-expected; if(err<0)err=-err;
            if(err>maximum_sqrt) maximum_sqrt=err;
            if(err>0.000007) $fatal(1,"SQRT input=%d error=%g",v,err);
            $fdisplay(unitfile,"sqrt %0d %0d %.12f %.12g",v,sy,expected,err);
            repeat(2) @(negedge clk);
        end
    endtask
    initial begin
        unitfile=$fopen("math_unit_output.txt","w");
        if(!unitfile) $fatal(1,"Cannot open math output");
        $fdisplay(unitfile,"function input_integer output_integer expected_real abs_error");
        repeat(5) @(negedge clk); rst=0;
        log_case(0); log_case(-1); log_case(268435456); log_case(268435457);
        sqrt_case(0);
        for(i=0;i<28;i=i+1) begin
            log_case(1<<i); log_case((1<<i)+1); if(i>0)log_case((1<<i)-1);
        end
        for(i=0;i<30;i=i+1) begin
            sqrt_case(1<<i); sqrt_case((1<<i)+1); if(i>0)sqrt_case((1<<i)-1);
        end
        // LUT knots and their immediate neighbours.
        for(i=1;i<1024;i=i+1) begin
            log_case(134217728+(i<<17));
            log_case(134217728+(i<<17)-1);
            sqrt_case(16777216+(i<<14));
        end
        for(i=0;i<5000;i=i+1) begin
            value=$random(seed)&32'h0fffffff; log_case(value);
            value=$random(seed)&32'h3fffffff; sqrt_case(value);
        end
        $fclose(unitfile);
        $display("PASS math: max_ln_error=%g max_sqrt_error=%g",maximum_ln,maximum_sqrt);
        f=$fopen("gaussian_output.txt","w");
        if(!f) $fatal(1,"Cannot open gaussian output");
        $fdisplay(f,"sample u1_Q28 u2_Q28 ln_Q24 sqrt_Q28 cos_Q28 sin_Q28 z1_Q28 z2_Q28 cycles");
        rst=1; repeat(5)@(negedge clk); rst=0; enable=1;
        for(n=0;n<100000;n=n+1) begin
            @(negedge clk); while(!valid) @(negedge clk);
            if((^{z1,z2,lnv,sqv,cv,sv})===1'bx) $fatal(1,"X/Z output");
            u=$itor(uin)/268435456.0;
            a=$itor(theta)/268435456.0; r=$sqrt(-2.0*$ln(u));
            e1=$itor(z1)/268435456.0-r*$cos(a);
            e2=$itor(z2)/268435456.0-r*$sin(a);
            if(e1<0)e1=-e1; if(e2<0)e2=-e2;
            if(e1>maximum_z)maximum_z=e1; if(e2>maximum_z)maximum_z=e2;
            if(e1>0.00002 || e2>0.00002) $fatal(1,"Gaussian sample %d mismatch %g %g",n,e1,e2);
            if(n<32)begin first_z1[n]=z1; first_z2[n]=z2; end
            $fdisplay(f,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",n,uin,dut.u2_q428,lnv,sqv,cv,sv,z1,z2,cycles-prevcycle);
            prevcycle=cycles;
            // Pause the producer; no output is allowed while disabled.
            if(n==49999) begin
                enable=0; @(negedge clk);
                repeat(20)begin @(negedge clk); if(valid)$fatal(1,"valid while paused"); end
                enable=1;
            end
        end
        enable=0; $fclose(f);
        $display("PASS 100000 Gaussian pairs; max_absolute_error=%g",maximum_z);
        @(negedge clk); rst=1; repeat(5)@(negedge clk); rst=0; enable=1;
        for(n=0;n<32;n=n+1)begin
            @(negedge clk); while(!valid)@(negedge clk);
            if(z1!==first_z1[n] || z2!==first_z2[n])$fatal(1,"Reset reproducibility failed");
        end
        $display("PASS reset reproducibility: first 32 pairs match exactly");
        $finish;
    end
    initial begin #100000000; $fatal(1,"simulation timeout"); end
endmodule
