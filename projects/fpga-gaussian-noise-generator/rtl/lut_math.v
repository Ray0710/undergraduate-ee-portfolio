`timescale 1ns/1ps
// LUT_BITS=10 means 1024 intervals and 1025 endpoint values.
// SR rounds the interpolation fraction only. No fabricated low-bit dither.
module cordic_ln_fsm_lutmix (
  input wire clk, rst, start,
  input wire signed [31:0] x, input wire [23:0] rnd24,
  output reg signed [31:0] ln_out, output reg done);
    localparam N=1024;
    localparam signed [31:0] TWO_LN2_Q24=32'sd23258160;
    (* rom_style="block" *) reg signed [31:0] lut[0:N];
    initial $readmemh("log_norm_q824.mem",lut);
    reg [2:0] state;
    reg [10:0] idx;
    reg [17:0] frac, noise;
    reg [5:0] exponent;
    reg signed [31:0] y0, y1;
    reg signed [63:0] product;
    reg [31:0] clamped, mantissa;
    integer j, leading, exp_comb;
    always @* begin
        clamped=(x<=0)?32'd1:((x>=32'sh10000000)?32'h10000000:x);
        leading=0;
        for(j=0;j<29;j=j+1) if(clamped[j]) leading=j;
        exp_comb=28-leading;
        mantissa=clamped<<exp_comb; // u = m * 2^-exponent, 1 <= m < 2
    end
    wire signed [63:0] rounded=product+$signed({46'b0,noise});
    wire signed [63:0] interpolated=$signed(y0)+(rounded>>>18);
    wire signed [63:0] result=$signed({1'b0,exponent})*TWO_LN2_Q24+interpolated;
    // Separate synchronous ROM reads: no asynchronous reset on BRAM data registers.
    always @(posedge clk) if(state==1) begin y0<=lut[idx]; y1<=lut[idx+11'd1]; end
    always @(posedge clk) begin
        if(rst) begin
            state<=0; done<=0; ln_out<=0; idx<=0; frac<=0; noise<=0;
            exponent<=0; product<=0;
        end else begin
            done<=0;
            case(state)
            0: if(start) begin
                idx<={1'b0,mantissa[27:18]}; frac<=mantissa[17:0];
                exponent<=exp_comb; noise<=rnd24[17:0]; state<=1;
            end
            1: state<=2;
            2: begin product<=($signed(y1)-$signed(y0))*$signed({1'b0,frac}); state<=3; end
            3: begin ln_out<=result[31:0]; done<=1; state<=4; end
            4: if(!start) state<=0;
            default: state<=0;
            endcase
        end
    end
endmodule

module sqrt_lutmix (
  input wire clk, rst, start, input wire [31:0] x824,
  input wire [23:0] rnd24, input wire [3:0] rnd4,
  output reg [31:0] sqrt_out, output reg done);
    // The core supplies 0 <= x <= 38.82. Output is unsigned Q4.28.
    // rnd4 retained for the caller interface; intentionally unused.
    (* rom_style="block" *) reg [31:0] lut[0:1024];
    initial $readmemh("sqrt_norm_q824.mem",lut);
    reg [2:0] state;
    reg [10:0] idx;
    reg [15:0] frac, noise;
    reg signed [5:0] scale;
    reg zero;
    reg [31:0] y0,y1;
    reg [63:0] product;
    integer j,leading,k;
    reg [31:0] mantissa;
    always @* begin
        leading=0;
        for(j=0;j<32;j=j+1) if(x824[j]) leading=j;
        k=(leading-24)>>>1; // floor division, including negative exponents
        mantissa=(k>=0)?(x824>>(2*k)):(x824<<(-2*k));
    end
    wire [63:0] interp={32'b0,y0}+((product+noise)>>16);
    reg [63:0] scaled;
    always @* begin
        if(scale>=0) scaled=interp<<scale;
        else scaled=(interp+(64'd1<<(-scale-1)))>>(-scale);
    end
    always @(posedge clk) if(state==1) begin y0<=lut[idx]; y1<=lut[idx+11'd1]; end
    always @(posedge clk) begin
        if(rst) begin
            state<=0; done<=0; sqrt_out<=0; idx<=0; frac<=0; noise<=0;
            scale<=0; zero<=0; product<=0;
        end else begin
            done<=0;
            case(state)
            0: if(start) begin
                idx<={1'b0,mantissa[25:16]}; frac<=mantissa[15:0];
                scale<=k+4; zero<=(x824==0); noise<=rnd24[15:0]; state<=1;
            end
            1: state<=2;
            2: begin product<=(y1-y0)*frac; state<=3; end
            3: begin sqrt_out<=zero?32'd0:scaled[31:0]; done<=1; state<=4; end
            4: if(!start) state<=0;
            default: state<=0;
            endcase
        end
    end
endmodule
