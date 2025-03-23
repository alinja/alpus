# Alpus VDHL - Alpus Library of Probably Useful Stuff

Alpus is a library of VHDL components, promoting good design practices for FPGA designs. Alpus is:

- Easy to use
- High quality for professional use
- Technology independent, but optimizable for most vendor architectures
 
The components are mostly implemented as single files, including a package for easy instantiation. Often there are
function implementations as well for flexible use.

## alpus_resetsync.vhd

Reset synchronizer. Arst and locked signal inputs are first synchronised to slow_clk, guaranteeing a minimum reset length 
for all clocks. This common reset is then synchronized separately to multiple reset outputs, one for each clock.

```
	rstsync: alpus_resetsync generic map (
		NUM_CLOCKS => 1
	) port map (
		slow_clk => clk,  -- connect to slowest clock
		arst => rst_ah,   -- optional
		locked => locked, -- optional
		clk(0) => clk_i,
		rst(0) => rst_i	);
```

## alpus_pll.vhd

Unified interface for arhcitecure specific instantiation for a simple PLL. The architecture can be chosen from following values:

- "SIMULA": simple simulation model
- "DUMMYX": dummy clock connection with no pll functionality
- "X7MMCM": 600 - 1600MHz (Xilinx 7 series MMCM, integer dividers only supported)
- "X7PLLE": 800 - 1600MHz (Xilinx 7 series PLL)
- "GWRPLL": 400 - 1200MHz (Gowin rPLL, limited outputs available)
- "ALTPLL": 600 - 1600MHz (Altera PLL)

Supports four output clocks, frequencies selectable by *input divider, vco multiplier*, and *output dividers*. Supports 
phase shifing for outputs.

```
	pll: alpus_pll generic map (
		ARCH => alpus_pll_arch_synth_or_sim(PLL_ARCH, "SIMULA"), -- selects automatically "SIMULA" in simulator
		IN_FREQ_MHZ => 12.0,
		IN_DIV => 1,
		IN_MUL => 100,
		OUT0_DIV => 12,
		OUT1_DIV => 24
	) port map (
		in_clk => clk,
		in_rst => rst_ah,
		out_clk0 => clk0,
		out_clk1 => clk1,
		out_locked => locked );
```

## alpus_led_blinker.vhd

Blinks a led. Every design starts with blinking a led to see that configuration succeeds and clocks and reset are working.
```
	blink: alpus_led_blinker generic map (
		PERIOD_LEN => 24
	) port map (
		clk => clk_i,
		rst => rst_i,
		led => led );
```

## alpus_filler.vhd

For filling a chip with dummy logic for evaluating clock frequency in a full chip, power consuption etc.

```
	fill: alpus_filler generic map (
		ADDER_LEN => 16,
		ADDER_NUM => 1000
	) port map (
		clk => clk_i,
		rst => rst_i,
		o => o );
```

## alpus_example_design.vhd

Template for starting a new project.

## alpus_wb32_all.vhd

Easy to use, high-performance and flexible VHDL implementation of Pipelined Wishbone B4 bus interconnect. 
Intended to provide similar easyness and functionality to generation based tools, but without generating.

Record types ```alpus_wb32_tos_t``` and ```alpus_wb32_tom_t``` are named according to **signal direction** 
to master (**tom**) or to slave (**tos**). This makes signal naming simple and consistent.

Consists of components for connecting multiple bus masters to one bus, multiple bus slaves to one bus and pipeline
bridges and adapters:
```
             _____________       ________       ____________
[master0]<->|             |     |pipeline|     |            |<->[slave0]
            |master_select| <-> |_bridge | <-> |slave_select|<->[slave1]
[master1]<->|_____________|     |________|     |____________|<->[std_slave_adapter]<->[slave2] 
```
More details in its own [repo](https://github.com/alinja/alpus_wb).

## alpus_riscv_cpu.vhd

Instantiation of an open-source RISC-V soft CPU, a tightly coupled memory and wishbone peripheral bus interface. 
Currently supports SERV and VexRiscCPU instantiation. An example design with a minimal C++ environment is included
in [alpus_riscv_cpu repo](https://github.com/alinja/alpus_riscv_cpu).

## alpus_wb32_spi_slave.vhd

VHDL SPI slave providing memory mapped access to a 32-bit pipelined Wishbone bus. Use with 
[alpus_wb](https://github.com/alinja/alpus_wb) Wishbone interconnect framework to connect 
any wishbone ip to an external CPU using a SPI bus. Features include:
- Easy to use synchronous design - component package included
- Provides access to Pipelined Wishbone B4 bus 
- SPI burst access support with >10MHz spi bus clock
- All four SPI modes supported
- 32-bit data bus with byte select
- 24-bit address, auto-incrementing within bursts
- Address high bits (31:24) can be preset when instantiating
- Includes SPI master model for simulation in VHDL testbench
- Includes C code for register access from MCU

```
use work.alpus_wb32_pkg.all;
use work.alpus_spi_slave_phy_pkg.all;

	spim: alpus_wb32_spi_slave port map (
		clk => clk,
		clk_sampling => clk_sampling,
		rst => rst,

		-- SPI slave
		ncs => ncs,
		sclk => sclk,
		mosi => mosi,
		miso => miso,

		-- Wishbone master
		wb_tos => spim_tos,
		wb_tom => spim_tom );
```
More documentation in [alpus_spi_slave repo](https://github.com/alinja/alpus_spi_slave).

## alpus_asram_controller.vhd

 A Simple Wishbone to asynchronous SRAM memory chip controller. Supports 32/16/8 bit 
 memory bus by splitting the 32-bit wishbone transfer in multiple phases as needed.
 Supported memory configurations:

 1/2/4 x 8bit; 2/4 x 16bit; 1 x 32bit (single rank)

 * Serialized transfers for narrow chip buses
 * Configurable timing (one clk resolution), min 2 clk per transfer
 * Full SRAM bus utilization for pipelined transfers
 * IOB Registered outputs
 
```
	ramif: alpus_asram_controller generic map(
		SRAM_RD_CLKS => 3,
		SRAM_RDEND_CLKS => 1,
		SRAM_WR_CLKS => 2,
		SRAM_WREND_CLKS => 1,
		SRAM_AWID => 19,
		SRAM_DWID => 32,
		SRAM_CEWID => 1,
		SRAM_WRWID => 1,
		SRAM_BEWID => 1
	) port map (
		clk => clk_i,
		rst => rst_i,
		sram_a => sram_a,
		sram_d => sram_d,
		sram_nce => sram_nce,
		sram_noe => sram_noe,
		sram_nwr => sram_nwr,
		sram_nbe => sram_nbe,
		wb_tos => wb_asram_tos,
		wb_tom => wb_asram_tom );
```
 Access timing is configured by SRAM_*_CLKS generics:
```
                 ______________
 addr         XXX______________XXX
                 _________
 data(wr)     --<_________>-----XXX
              __           ____
 nce/nwr/nbe    \___1*____/ 2* \XX

 1* SRAM_WR_CLKS: Active write (must be > T_WC_SRAM)
 2* SRAM_WREND_CLKS: Rising edge for nwe, bus turnaround
                 ______________
 addr         XXX______________XXX
                        ____
 data(rd)     ---------<____>-----
              __           ____
 nce/noe/nbe    \___1*____/ 2* \XX

 1* SRAM_RD_CLKS: Read setup (must be > T_CO + T_AA_SRAM + T_IDELAY)
 2* SRAM_RDEND_CLKS: Bus turnaround, skipped during read bursts

```

## alpus_sin_lookup.vhd

Quadrant-flipping sin(x)/cos(x) lookup, using a rom lookup of one quadrant of pre-calculated values. Instantiate as function 
calls embedded in your pipeline or as a component.

Optional linear interpolation stage gives a better SNR/SFDR at the expense of two additional multipliers.
Current approximation works for 4 to 6 additional phase bits.

```
	dut: alpus_sin_lookup generic map (
		PHASE_WID => 12,
		D_WID => 16,
	) port map (
		clk => clk,
		phase => phase_acc,
		sin => sin_val_out,
		cos => cos_val_out );
```

Includes Simulation testbench calculating SNR. Performance examples for some parameter combinations:

```
Lookup only:
     8   10   11   12   14   16  phase bits
 7 40.5                          dB
 8 42.4 48.8 49.6                dB
10 42.9 54.2 58.4 60.8           dB
12      55.0 60.9 66.2 72.8      dB
14      55.0      67.1 78.4 84.9 dB
16                67.1 79.1 90.4 dB
Lookup with 4 bit interpolation (2pi=6.0):
     8   10   12   14   16  20   phase bits total
10      48.9 56.3 58.5
12           60.4 68.3 70.9
14                72.6 80.5 84.5
16                72.8 84.4 94.7
Lookup with 8 bit interpolation (2pi=25/8):
    16   18   20    22   phase bits total
12 70.0 70.3
14 80.0 82.4 82.6
16 83.2 91.7 94.3  94.6 
18      95.2 103.9 106.4
```

```
Sin only 12bit phase x 10bit data: 60.8 dB
Artix7:         16 LUT, 22 FF, 1 MEM18K, >300MHz
Cyclone10LP:    24 LUT, 14 FF, 1 MEM9K, >250MHz
CertusNX:       32 LUT, 12 FF, 1 MEM18K, >200MHz
Gowin GW2A:     25 LUT, 12 FF, 1 MEM9K, >250MHz
Efinity T13:    32 LUT, 32 FF, 4 RAM5K, >200MHz

Sin only 9bit phase x 8bit data: 46.3 dB
Artix7:      26 LUT, 25 FF, 0 MEM18K, >500MHz
Cyclone10LP: 80 LUT, 25 FF, 0 MEM9K, >250MHz
CertusNX:    79 LUT, 24 FF, 0 MEM18K, >200MHz

Sin/cos interpolated with 12+4 phase bits, 16 data bits: 84.4 dB
Artix7 -1:        67 LUT,  93 FF, 1 MEM18K, 2 DSP, >280MHz (REG:0111110)
Cyclone10GX -6:  100 LUT, 142 FF, 1 MEM20K, 1 DSP, >300MHz (REG:1101100)
Cyclone10LP -7:  174 LUT,  94 FF, 5 MEM9K,  2 DSP, >200MHz (REG:0111110)
LFD2NX-17 -8hp:  187 LUT, 142 FF, 2 EBR,    2 DSP, >180MHz (REG:1101100)
GW5A -C0:        167 LUT, 115 FF, 2 BSRAM,  2 DSP, >130MHz (REG:1111101)
Efinity T13 -4:  150 LUT, 189 FF, 8 RAM5K,  2 DSP, >250MHz (REG:1111100)
Efinity Tz50 -3: 139 LUT, 134 FF, 4 RAM10K, 2 DSP, >350MHz (REG:1101100)
```
