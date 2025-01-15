-- alpus_resetsync
--
-- Reset synchronizer
-- * Supports multiple unrelated clocks
-- * Async reset and pll locked signals
-- * Reset stretching to guarantee reset for all clocks
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;

package alpus_resetsync_pkg is
component alpus_resetsync is
generic(
	NUM_CLOCKS : integer := 1;
	ARST_ACTIVE : std_logic := '1';
	RST_SYNC_LEN : integer := 3
);
port(
	slow_clk : in std_logic;         -- use slowest clock
	arst     : in std_logic := '0';
	locked   : in std_logic := '1';

	clk : in std_logic_vector(NUM_CLOCKS-1 downto 0);
	rst : out std_logic_vector(NUM_CLOCKS-1 downto 0)
);
end component;
end package;

package body alpus_resetsync_pkg is
end package body;




library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;

entity alpus_resetsync is
generic(
	NUM_CLOCKS : integer := 1;
	ARST_ACTIVE : std_logic := '1';
	RST_SYNC_LEN : integer := 3
);
port(
	slow_clk : in std_logic;         -- use slowest clock
	arst     : in std_logic := '0';
	locked   : in std_logic := '1';

	clk : in std_logic_vector(NUM_CLOCKS-1 downto 0);
	rst : out std_logic_vector(NUM_CLOCKS-1 downto 0)
);
end entity alpus_resetsync;

architecture rtl of alpus_resetsync is

	signal arst_combined :  std_logic;
	signal rst_shr : std_logic_vector(RST_SYNC_LEN-2 downto 0) := (others => '0');
	signal rst_i :  std_logic;

	signal rst_sample      : std_logic_vector(NUM_CLOCKS-1 downto 0);
	signal rst_sample_meta : std_logic_vector(NUM_CLOCKS-1 downto 0);
	attribute ASYNC_REG : string;
	attribute ASYNC_REG of rst_shr: signal is "TRUE";
	attribute ASYNC_REG of rst_sample: signal is "TRUE";
	attribute ASYNC_REG of rst_sample_meta: signal is "TRUE";
begin

	arst_combined <= (arst or not locked) when ARST_ACTIVE = '1' else (not arst or not locked);

	--
	-- Make a single stretched registered (slow_clk) reset signal
	--
	-- * Reset must be long enough to guarantee reset for all synchronizer registers
	-- * When reset is removed, only lowest bit can be metastable
	-- * Synchronizer should be long enough both to cover recovery from metastability and to
	--   provide long enough reset
	-- * Use slowest incoming continuous clock for slow_clk
	--
	process(slow_clk, arst_combined)
	begin
		if arst_combined = '1' then
			rst_shr <= (others => '1');
			rst_i <= '1';
		elsif rising_edge(slow_clk) then
			-- Synchronizes possible metastabilites from asynchronous path from reset
			rst_shr <= rst_shr(RST_SYNC_LEN-3 downto 0) & '0';
			rst_i <= rst_shr(rst_shr'high);
		end if;
	end process;


	--
	-- Synchronize the registered reset separately to each clock domain
	--
	g0: for i in 0 to NUM_CLOCKS-1 generate
		process(clk(i))
		begin
			if rising_edge(clk(i)) then
				rst_sample(i) <= rst_i;
				rst_sample_meta(i) <= rst_sample(i);
				rst(i) <= rst_sample_meta(i);
			end if;
		end process;
	end generate;
end;



