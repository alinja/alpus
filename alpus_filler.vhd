-- alpus_filler
--
-- For filling a chip with dummy logic for evaluating clock frequency in a full chip, power consuption etc.
-- 
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;

package alpus_filler_pkg is
component alpus_filler is
generic(
	ADDER_LEN : integer := 16;
	ADDER_NUM : integer := 2;
	ENA_LEN : integer := 16;
	HAS_RST : std_logic := '0'
);
port(
	clk : in std_logic;
	rst : in std_logic := '0';
	ena : in std_logic := '1';
	o : out std_logic
);
end component;
end package;



library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alpus_filler is
generic(
	ADDER_LEN : integer := 16;
	ADDER_NUM : integer := 2;
	ENA_LEN : integer := 16;
	HAS_RST : std_logic := '0'
);
port(
	clk : in std_logic;
	rst : in std_logic := '0';
	ena : in std_logic := '1';
	o : out std_logic
);
end entity alpus_filler;

architecture rtl of alpus_filler is

	type adder_t is array (integer range<>) of unsigned(ADDER_LEN-1 downto 0);
	signal adder : adder_t(0 to ADDER_NUM-1) := (others => (others => '0'));
	signal ena_chain : std_logic_vector(ADDER_NUM/ENA_LEN downto 0);

begin

	process(clk)
	begin
		if rising_edge(clk) then
			ena_chain <= ena_chain(ena_chain'high-1 downto 0) & ena;
			
			if ena_chain(0) = '1' then
				adder(0) <= adder(0) + 1;
			end if;
			for i in 1 to ADDER_NUM-1 loop
				if ena_chain(i/ENA_LEN) = '1' then
					adder(i) <= adder(i) + adder(i-1);
				end if;
			end loop;
			
			o <= adder(ADDER_NUM-1)(ADDER_LEN-1);
			
			if rst = '1' then
				if HAS_RST = '1' then
					adder <= (others => (others => '0'));
				end if;
				o <= '0';
			end if;
		end if;
	end process;

end;



