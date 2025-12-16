-- alpus_example_design
--
-- Template for starting a new project.
--
-- This file is in Public Domain
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use work.config_pkg.all;
use work.alpus_pll_pkg.all;
use work.alpus_resetsync_pkg.all;
use work.alpus_led_blinker_pkg.all;
use work.alpus_filler_pkg.all;

entity alpus_example_design is
generic(
	HAS_RST : std_logic := '1';
	RST_ACTIVE : std_logic := '1'
);
port(
	clk : in std_logic;         -- use slowest clock
	rst : in std_logic := '0';
	o : out std_logic;
	led : out std_logic
);
end entity alpus_example_design;

architecture rtl of alpus_example_design is

	signal rst_ctr : unsigned(3 downto 0) := x"0";
	signal rst_ah : std_logic;
	signal locked : std_logic;
	signal rst_i : std_logic;
	signal clk_i : std_logic;

begin

	-- Convert to active high reset if available
	rst_ah <= rst xor not RST_ACTIVE when HAS_RST = '1' else '0';

	-- Unified interface for arhcitecure specific instantiations
	pll: alpus_pll generic map (
		ARCH => alpus_pll_arch_synth_or_sim("X7MMCM", "SIMULA"),
		IN_FREQ_MHZ => 12.0,
		OUT0_DIV => 2,
		IN_DIV => 1,
		IN_MUL => 50
	) port map (
		in_clk => clk,
		in_rst => rst_ah,
		out_clk0 => clk_i,
		out_locked => locked );

	-- Reset synchronizer
	rstsync: alpus_resetsync generic map (
		NUM_CLOCKS => 1
	) port map (
		slow_clk => clk,
		arst => rst_ah,
		locked => locked,
		clk(0) => clk_i,
		rst(0) => rst_i	);

	-- Blinking led to prove device is configured properly and clock is running
	blink: alpus_led_blinker generic map (
		PREDIV_LEN => 12,
		PERIOD_LEN => 12
	) port map (
		clk => clk_i,
		rst => rst_i,
		led => led );

	fill: alpus_filler generic map (
		ADDER_LEN => 16,
		ADDER_NUM => 20,
		HAS_RST => '1'
	) port map (
		clk => clk_i,
		rst => rst_i,
		o => o );

end;







-- synthesis translate_off
library ieee;
use ieee.std_logic_1164.all;

entity alpus_example_design_tb is
end entity alpus_example_design_tb;

architecture tb of alpus_example_design_tb is
	signal clk : std_logic := '0';
	signal rst : std_logic := '1';
begin
	clk <= not clk after 10 ns /2;
	rst <= '0' after 500 ns;
	dut: entity work.alpus_example_design port map (
		clk => clk,
		rst => rst,
		led => open );
end;
-- synthesis translate_on

