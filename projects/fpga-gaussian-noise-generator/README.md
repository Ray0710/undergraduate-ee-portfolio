# Fixed-point Gaussian noise generator

**Undergraduate capstone · Verilog · MATLAB · FPGA signal processing**

The core generates two approximately standard-normal samples from two uniform inputs using the Box–Muller transform. I implemented the undergraduate fixed-point datapath and control logic in Verilog and compared its simulated output with the target distribution in MATLAB. The later, AI-assisted implementations target the Digilent Arty S7-25 (`xc7s25csga324-1`).

## Arty S7-25 v3 pipeline

The original design used LFSRs for the uniform inputs, iterative CORDIC for sine and cosine, and a finite-state machine to coordinate logarithm and square-root lookup stages. The v2 board implementation adopted two deterministic `xoshiro128**` streams and a 12-byte UART packet. v3 keeps those uniform streams and the packet format. It pipelines the logarithm and square root, replaces the iterative CORDIC with a quarter-wave lookup and linear interpolation, and aligns the radius and angle paths before the final multiplications.

The 11-stage pipeline emits one pair of signed Q4.28 samples per 12 MHz clock after it fills. The UART captures a pair every 1,441 clocks and the core keeps running during transmission. The interface uses the same seven external pins. [Board constraints](constraints/arty_s7_25_awgn.xdc) · [Pipeline RTL](rtl/awgn_pipeline_core.v) · [Box–Muller pipeline reference](https://www.doc.ic.ac.uk/~wl/papers/06/tc06dul.pdf)

| Result | v2 FSM | v3 pipeline |
| --- | ---: | ---: |
| Core clocks per output pair in RTL simulation | 42 | 1 |
| Core throughput at 12 MHz | 285,714 pairs/s | 12,000,000 pairs/s |
| UART setting (8N1) | 115,200 baud | 1,000,000 baud |
| PC receive rate, 60-second board capture | 958.14 pairs/s | **8,324.11 pairs/s** |
| Complete packets received | 57,489 | **499,459** |
| Sequence gaps or duplicate packets | 0 | 0 |
| Post-route setup / hold slack at 12 MHz | +55.164 / +0.048 ns | +66.434 / +0.086 ns |
| Post-route LUTs / registers / DSPs / BRAM tiles | 2,033 / 1,032 / 27 / 4 | 1,345 / 935 / 22 / 11 |

### Verification

- **v3 behavioral simulation.** The core produced 100,000 consecutive pairs with one pair per clock. The testbench also checked nine boundary inputs and reset behavior. The maximum observed absolute error against double-precision Box–Muller was 3.115 × 10⁻⁶. A separate UART simulation decoded 64 packets at the TX pin and checked their contents and spacing.
- **v3 physical board capture.** All 499,459 complete pairs matched a bit-accurate fixed-point reference. The reference first reproduced 100,000 RTL simulation pairs and then reconstructed the uniform inputs for each received sequence number. The maximum observed absolute error against double precision was 2.751 × 10⁻⁶. The two measured means were 0.00101 and 0.00140, and the variances were 1.00216 and 0.99903. [Capture summary](results/v3/capture_summary.json) · [Accuracy summary](results/v3/accuracy_summary.json) · [32 decoded pairs](results/v3/capture_excerpt.txt)
- **v2 baseline.** Behavioral simulation checked 100,000 pairs and reproduced the first 32 after reset. The maximum observed absolute error was 2.636 × 10⁻⁶, with simulated variances of 0.99818 and 1.00239. The board-capture variances were 0.99956 and 1.01076.

![v2 simulated distributions of 100,000 Gaussian sample pairs compared with a standard normal density](assets/gaussian-distribution.png)

## Build and simulate

Run from this FPGA project directory in a Vivado shell. The commands were checked with Vivado 2026.1. The v3 bitstream is generated at `project_v3/awgn_s7_25.runs/impl_1/awgn_s7_25_pipeline_top.bit`.

```text
vivado -mode batch -source build_vivado.tcl -tclargs v3
vivado -mode batch -source check_v3_project_sim.tcl
```

Open `project_v3/awgn_s7_25.xpr` to run Behavioral Simulation in the GUI. The default testbench is `tb_pipeline`. To check the UART pin, set `tb_pipeline_uart` as the simulation top. Build v2 with `vivado -mode batch -source build_vivado.tcl` and open `project/awgn_s7_25.xpr` for its `tb_validation` and `tb_uart` testbenches.

v3 uses `log_norm_q832.mem`, `sin_pair_q428.mem` and the shared `sqrt_norm_q824.mem`. Run `python scripts/generate_v3_luts.py` to regenerate the v3 logarithm and sine tables.

## Capture and decode

Program the v3 bitstream in Hardware Manager and keep the board connected through J10 USB. On Windows with the Digilent FTDI D2XX driver installed, run the following from the FPGA project directory.

```powershell
python scripts/capture_uart_d2xx.py capture_v3_60s --profile v3 --seconds 60
```

The script creates a new output directory with `uart_raw.bin`, `gaussian_samples.txt`, and `capture_summary.json`. The last two text columns, `z1_real` and `z2_real`, are the scaled sample values. To decode an existing raw file, run `python scripts/decode_uart_capture.py uart_raw.bin decoded.txt`. Use `--profile v2` when capturing the v2 bitstream.

The packet layout is `A5 5A`, a little-endian 16-bit sequence number, and two little-endian signed 32-bit samples. The sequence counts transmitted pairs and wraps from 65,535 to 0. It supports gap and duplicate detection. Payload accuracy in the board measurement was checked separately against the fixed-point model.
