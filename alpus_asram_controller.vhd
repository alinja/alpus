-- alpus_asram_controller
-- 
-- A Simple Wishbone to asynchronous SRAM memory chip controller. Supports 32/16/8 bit 
-- memory bus by splitting the 32-bit wishbone transfer in multiple phases as needed.
-- Supported memory configurations:
--
-- 1/2/4 x 8bit; 2/4 x 16bit; 1 x 32bit (single rank)
--
-- * Serialized transfers for narrow chip buses
-- * Configurable timing (one clk resolution), min 2 clk per transfer
-- * Full SRAM bus utilization for pipelined transfers
-- * IOB Registered outputs
-- 
--
-- Access timing is configured by SRAM_*_CLKS generics:
--                 ______________
-- addr         XXX______________XXX
--                 _________
-- data(wr)     --<_________>-----XXX
--              __           ____
-- nce/nwr/nbe    \___1*____/ 2* \XX
--
-- 1* SRAM_WR_CLKS: Active write (must be > T_WC_SRAM)
-- 2* SRAM_WREND_CLKS: Rising edge for nwe, bus turnaround
--
--                 ______________
-- addr         XXX______________XXX
--                        ____
-- data(rd)     ---------<____>-----
--              __           ____
-- nce/noe/nbe    \___1*____/ 2* \XX
--
-- 1* SRAM_RD_CLKS: Read setup (must be > T_CO + T_AA_SRAM + T_IDELAY)
-- 2* SRAM_RDEND_CLKS: Bus turnaround, skipped during read bursts
--
--
-- TODO: support for multiple ranks
-- TODO: more optimal wr access
-- TODO: falling edge noe/nwr 0.5clk delay?

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.alpus_wb32_pkg.all;

package alpus_asram_controller_pkg is
component alpus_asram_controller is
generic(
	SRAM_AWID : integer := 15;
	SRAM_DWID : integer := 8;
	SRAM_CEWID : integer := 1; -- num of chips
	SRAM_WRWID : integer := 1; -- num of chips
	SRAM_BEWID : integer := 1; -- num of byte enables (needed for 16x/32x chips)
	SRAM_HAS_BE : std_logic := '0'; -- 8bit rams have no nbe ports, use nce instead
	SRAM_RD_CLKS : integer := 2;
	SRAM_RDEND_CLKS : integer := 1;
	SRAM_WR_CLKS : integer := 2;
	SRAM_WREND_CLKS : integer := 1;
	FAST_READ_OPT : std_logic := '1'; -- skip idle if new stb active
	T_CO : time := 4.5 ns;
	T_IDELAY : time := 3 ns
);
port(
	clk : in std_logic;
	rst : in std_logic;

	sram_a : out std_logic_vector(SRAM_AWID-1 downto 0);
	sram_d : inout std_logic_vector(SRAM_DWID-1 downto 0);
	sram_nce : out std_logic_vector(SRAM_CEWID-1 downto 0);
	sram_noe : out std_logic_vector(SRAM_WRWID-1 downto 0);
	sram_nwr : out std_logic_vector(SRAM_WRWID-1 downto 0);
	sram_nbe : out std_logic_vector(SRAM_BEWID-1 downto 0);

	wb_tos : in alpus_wb32_tos_t;
	wb_tom : out alpus_wb32_tom_t
);
end component;
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.alpus_wb32_pkg.all;

entity alpus_asram_controller is
generic(
	SRAM_AWID : integer := 15;
	SRAM_DWID : integer := 8;
	SRAM_CEWID : integer := 1; -- num of chips
	SRAM_WRWID : integer := 1; -- num of chips (nwr/noe outputs)
	SRAM_BEWID : integer := 1; -- num of byte enables (needed for 16x/32x chips)
	SRAM_HAS_BE : std_logic := '0'; -- 8bit rams have no nbe ports, use nce instead
	SRAM_RD_CLKS : integer := 2;
	SRAM_RDEND_CLKS : integer := 1;
	SRAM_WR_CLKS : integer := 1;
	SRAM_WREND_CLKS : integer := 1;
	FAST_READ_OPT : std_logic := '0'; -- skip idle if new stb active
	T_CO : time := 0 ns;
	T_IDELAY : time := 0 ns
);
port(
	clk : in std_logic;
	rst : in std_logic;

	sram_a : out std_logic_vector(SRAM_AWID-1 downto 0);
	sram_d : inout std_logic_vector(SRAM_DWID-1 downto 0);
	sram_nce : out std_logic_vector(SRAM_CEWID-1 downto 0);
	sram_noe : out std_logic_vector(SRAM_WRWID-1 downto 0);
	sram_nwr : out std_logic_vector(SRAM_WRWID-1 downto 0);
	sram_nbe : out std_logic_vector(SRAM_BEWID-1 downto 0);

	wb_tos : in alpus_wb32_tos_t;
	wb_tom : out alpus_wb32_tom_t
);
end entity alpus_asram_controller;

architecture rtl of alpus_asram_controller is
	constant WB_DWID : integer := wb_tos.data'length;
	constant WB_SELWID : integer := WB_DWID/8;

	function is_zero(a : std_logic_vector) return boolean is
	begin
		if unsigned(a) = 0 then
			return true;
		else
			return false;
		end if;
	end function;

	function lowest_sel_block(sel : std_logic_vector(WB_SELWID-1 downto 0)) return integer is
		variable j : integer range 0 to WB_SELWID/SRAM_BEWID-1 := 0;
	begin
		for i in WB_SELWID/SRAM_BEWID-1 downto 0 loop
			if not is_zero(sel(SRAM_BEWID-1+i*SRAM_BEWID downto i*SRAM_BEWID)) then
				j := i;
			end if;
		end loop;
		return j;
	end function;

	function wb_to_addr(wb : alpus_wb32_tos_t; sel : std_logic_vector(WB_SELWID-1 downto 0)) return std_logic_vector is
		variable wb_wordmux_addr2 : std_logic_vector(1 downto 0);
		variable wb_wordmux_addr1 : std_logic_vector(0 downto 0);
	begin
		if SRAM_BEWID = 1 then
			wb_wordmux_addr2 := std_logic_vector(to_unsigned(lowest_sel_block(sel), 2));
			return wb.adr(SRAM_AWID-1 downto 2) & wb_wordmux_addr2;
		elsif SRAM_BEWID = 2 then
			wb_wordmux_addr1 := std_logic_vector(to_unsigned(lowest_sel_block(sel), 1));
			return wb.adr(SRAM_AWID-1+1 downto 2) & wb_wordmux_addr1;
		else
			return wb.adr(SRAM_AWID-1+2 downto 2);
		end if;
	end function;

	function wb_to_d(wb : alpus_wb32_tos_t; sel : std_logic_vector(WB_SELWID-1 downto 0)) return std_logic_vector is
		variable RET : std_logic_vector(SRAM_DWID-1 downto 0);
		variable j : integer range 0 to WB_SELWID/SRAM_BEWID-1;
	begin
		j := lowest_sel_block(sel);
		return wb.data(SRAM_DWID-1+j*SRAM_DWID downto j*SRAM_DWID);
	end function;

	function sel_to_nbe(sel : std_logic_vector(WB_SELWID-1 downto 0)) return std_logic_vector is
		variable RET : std_logic_vector(SRAM_BEWID-1 downto 0);
		variable j : integer range 0 to WB_SELWID/SRAM_BEWID-1;
	begin
		j := lowest_sel_block(sel);
		return not sel(SRAM_BEWID-1+j*SRAM_BEWID downto j*SRAM_BEWID);
	end function;

	function next_sel(sel : std_logic_vector(WB_SELWID-1 downto 0)) return std_logic_vector is
		variable RET : std_logic_vector(WB_SELWID-1 downto 0);
		variable j : integer range 0 to WB_SELWID/SRAM_BEWID-1;
	begin
		RET := sel;
		j := lowest_sel_block(sel);
		RET(SRAM_BEWID-1+j*SRAM_BEWID downto j*SRAM_BEWID) := (others => '0');
		return RET;
	end function;


	signal sel_i : std_logic_vector(WB_SELWID-1 downto 0);
	signal sel_block_idx : integer range 0 to WB_DWID/SRAM_BEWID-1;
	signal clk_ctr : integer range 0 to 7;
	type asram_fsm_t is (idle, rd, bus_turn, wr_start, wr, wr_end);
	signal asram_fsm : asram_fsm_t;
	signal wb_tos_r : alpus_wb32_tos_t;

	signal sram_a_out : std_logic_vector(SRAM_AWID-1 downto 0);
	signal sram_nce_out : std_logic_vector(SRAM_CEWID-1 downto 0);
	signal sram_noe_out : std_logic_vector(SRAM_WRWID-1 downto 0);
	signal sram_nwr_out : std_logic_vector(SRAM_WRWID-1 downto 0);
	signal sram_nbe_out : std_logic_vector(SRAM_BEWID-1 downto 0);
	signal sram_d_hiz : std_logic;
	signal sram_d_hiz_vec : std_logic_vector(SRAM_DWID-1 downto 0);
	signal sram_d_outz : std_logic_vector(SRAM_DWID-1 downto 0);
	signal sram_d_out : std_logic_vector(SRAM_DWID-1 downto 0);
	signal sram_d_in : std_logic_vector(SRAM_DWID-1 downto 0);
	
	attribute IOB : string;
	attribute IOB of sram_a_out : signal is "true";
	attribute IOB of sram_nce_out : signal is "true";
	attribute IOB of sram_noe_out : signal is "true";
	attribute IOB of sram_nwr_out : signal is "true";
	attribute IOB of sram_nbe_out : signal is "true";
	attribute IOB of sram_d_outz : signal is "true";
	attribute IOB of sram_d_out : signal is "true";
	--attribute IOB of sram_d_hiz : signal is "true";
	attribute IOB of sram_d_hiz_vec : signal is "true";
	--attribute DONT_TOUCH : string;
	--attribute DONT_TOUCH of sram_d_hiz_vec : signal is "true";
begin
	assert SRAM_RD_CLKS > 0 report "SRAM_RD_CLKS must be > 0" severity failure;
	assert SRAM_RDEND_CLKS > 0 report "SRAM_RDEND_CLKS must be > 0" severity failure;
	assert SRAM_WR_CLKS > 0 report "SRAM_WR_CLKS must be > 0" severity failure;
	assert SRAM_WREND_CLKS > 0 report "SRAM_WREND_CLKS must be > 0" severity failure;
	assert not (FAST_READ_OPT = '1' and SRAM_RD_CLKS = 1) report "FAST_READ_OPT = '1' and SRAM_RD_CLKS = 1" severity failure;
	
	process(clk)
	begin
		if rising_edge(clk) then

			wb_tom.ack <= '0';
			case asram_fsm is
			when idle =>
				sram_d_outz <= (others => 'Z');
				sram_d_out <= (others => 'X');
				sram_d_hiz <= '1';
				sram_d_hiz_vec <= (others => '1');
				sram_noe_out <= (others => '1');
				sram_nwr_out <= (others => '1');
				sram_nce_out <= (others => '1');
				sram_nbe_out <= (others => '1');
				wb_tom.stall <= '0';
				if wb_tos.cyc = '1' and wb_tos.stb = '1' then
					if wb_tos.we = '1' then
						-- start write access
						wb_tom.stall <= '1';
						wb_tom.ack <= '1';
						wb_tos_r <= wb_tos;
						sram_a_out <= wb_to_addr(wb_tos, wb_tos.sel);
						sram_d_outz <= wb_to_d(wb_tos, wb_tos.sel);
						sram_d_out <= wb_to_d(wb_tos, wb_tos.sel);
						sram_d_hiz <= '0';
						sram_d_hiz_vec <= (others => '0');
						sram_nwr_out <= (others => '0');
						if SRAM_HAS_BE = '1' then
							sram_nce_out <= (others => '0');
							sram_nbe_out <= sel_to_nbe(wb_tos.sel);
						else
							sram_nce_out <= sel_to_nbe(wb_tos.sel);
							sram_nbe_out <= (others => '1');
						end if;
						sel_i <= next_sel(wb_tos.sel);
						clk_ctr <= SRAM_WR_CLKS-1;
						asram_fsm <= wr;
					else
						-- start read access
						wb_tos_r <= wb_tos;
						sram_a_out <= wb_to_addr(wb_tos, wb_tos.sel);
						sram_d_outz <= (others => 'Z');
						sram_d_out <= (others => 'X');
						sram_d_hiz <= '1';
						sram_d_hiz_vec <= (others => '1');
						sram_noe_out <= (others => '0');
						if SRAM_HAS_BE = '1' then
							sram_nce_out <= (others => '0');
							sram_nbe_out <= sel_to_nbe(wb_tos.sel);
						else
							sram_nce_out <= sel_to_nbe(wb_tos.sel);
							sram_nbe_out <= (others => '1');
						end if;
						wb_tom.stall <= '1';
						sel_i <= next_sel(wb_tos.sel);
						sel_block_idx <= lowest_sel_block(wb_tos.sel);
						clk_ctr <= SRAM_RD_CLKS-1;
						asram_fsm <= rd;
					end if;
				end if;
			when rd =>
				wb_tom.stall <= '1';
				if clk_ctr = 0 then
					wb_tom.data(SRAM_DWID-1+sel_block_idx*SRAM_DWID downto sel_block_idx*SRAM_DWID) <= to_stdlogicvector(to_bitvector(sram_d_in));
					if is_zero(sel_i) then
						wb_tom.ack <= '1';
						if FAST_READ_OPT = '1' and wb_tos.cyc = '1' and wb_tos.stb = '1' and wb_tos.we = '0' then
							-- Continue directly to next read
							wb_tos_r <= wb_tos;
							sram_a_out <= wb_to_addr(wb_tos, wb_tos.sel);
							if SRAM_HAS_BE = '1' then
								sram_nce_out <= (others => '0');
								sram_nbe_out <= sel_to_nbe(wb_tos.sel);
							else
								sram_nce_out <= sel_to_nbe(wb_tos.sel);
								sram_nbe_out <= (others => '1');
							end if;
							wb_tom.stall <= '0'; --TODO SRAM_RD_CLKS=1
							sel_i <= next_sel(wb_tos.sel);
							sel_block_idx <= lowest_sel_block(wb_tos.sel);
							clk_ctr <= SRAM_RD_CLKS-1;
						else
							-- End read access
							sram_noe_out <= (others => '1');
							sram_nce_out <= (others => '1');
							sram_nbe_out <= (others => '1');
							wb_tom.stall <= '0';
							wb_tom.ack <= '1';
							if SRAM_RDEND_CLKS = 1 then
								asram_fsm <= idle;
							else
								clk_ctr <= SRAM_RDEND_CLKS-2;
								asram_fsm <= bus_turn;
							end if;
						end if;
					else
						-- Continue read access, start next read phase
						sram_a_out <= wb_to_addr(wb_tos_r, sel_i);
						if SRAM_HAS_BE = '1' then
							sram_nce_out <= (others => '0');
							sram_nbe_out <= sel_to_nbe(sel_i);
						else
							sram_nce_out <= sel_to_nbe(sel_i);
							sram_nbe_out <= (others => '1');
						end if;
						sel_i <= next_sel(sel_i);
						sel_block_idx <= lowest_sel_block(sel_i);
						clk_ctr <= SRAM_RD_CLKS-1;
						asram_fsm <= rd;
					end if;
				else
					clk_ctr <= clk_ctr - 1;
				end if;
			when bus_turn =>
				-- Extra bus turnaround if needed - idle state will always add one
				if clk_ctr = 0 then
					asram_fsm <= idle;
				else
					clk_ctr <= clk_ctr - 1;
				end if;
			when wr_start =>
				-- TODO: First half of write phase: activate nwe
				if clk_ctr = 0 then
					sram_nwr_out <= (others => '0');
					if SRAM_HAS_BE = '1' then
						sram_nce_out <= (others => '0');
						sram_nbe_out <= sel_to_nbe(sel_i);
					else
						sram_nce_out <= sel_to_nbe(sel_i);
						sram_nbe_out <= (others => '1');
					end if;
					clk_ctr <= SRAM_WR_CLKS-1;
					asram_fsm <= wr;
				else
					clk_ctr <= clk_ctr - 1;
				end if;
			when wr =>
				-- Write active
				if clk_ctr = 0 then
					sram_d_outz <= (others => 'Z');
					sram_d_out <= (others => 'X');
					sram_d_hiz <= '1';
					sram_d_hiz_vec <= (others => '1');
					sram_nwr_out <= (others => '1');
					sram_nce_out <= (others => '1');
					sram_nbe_out <= (others => '1');
					if SRAM_WREND_CLKS = 1 then
						if is_zero(sel_i) then
							wb_tom.stall <= '0';
							--wb_tom.ack <= '1';
							asram_fsm <= idle;
						else
							clk_ctr <= SRAM_WREND_CLKS-1;
							asram_fsm <= wr_end;
						end if;
					else
						clk_ctr <= SRAM_WREND_CLKS-1;
						asram_fsm <= wr_end;
					end if;
				else
					clk_ctr <= clk_ctr - 1;
				end if;
			--when wr_end =>
			when others =>
				-- Second half of write phase: rising edge of nwe, bus turnaround
				if clk_ctr = 0 then
					if is_zero(sel_i) then
						sram_d_outz <= (others => 'Z');
						sram_d_out <= (others => 'X');
						sram_d_hiz <= '1';
						sram_d_hiz_vec <= (others => '1');
						wb_tom.stall <= '0';
						--wb_tom.ack <= '1';
						--TODO block
						asram_fsm <= idle;
					else
						sram_a_out <= wb_to_addr(wb_tos_r, sel_i);
						sram_d_outz <= wb_to_d(wb_tos_r, sel_i);
						sram_d_out <= wb_to_d(wb_tos_r, sel_i);
						sram_d_hiz <= '0';
						sram_d_hiz_vec <= (others => '0');
						sram_nwr_out <= (others => '0');
						if SRAM_HAS_BE = '1' then
							sram_nce_out <= (others => '0');
							sram_nbe_out <= sel_to_nbe(sel_i);
						else
							sram_nce_out <= sel_to_nbe(sel_i);
							sram_nbe_out <= (others => '1');
						end if;
						sel_i <= next_sel(sel_i);
						clk_ctr <= SRAM_WR_CLKS-1;
						asram_fsm <= wr;
					end if;
				else
					clk_ctr <= clk_ctr - 1;
				end if;
			end case;

			if SRAM_HAS_BE = '0' then
				sram_nbe_out <= (others => 'X');
			end if;
			
			if rst = '1' then
				wb_tom <= alpus_wb32_tom_init;
				asram_fsm <= idle;
				sram_nce_out <= (others => '1');
				sram_noe_out <= (others => '1');
				sram_nwr_out <= (others => '1');
				sram_nbe_out <= (others => '1');
				sram_d_outz <= (others => 'Z');
				sram_d_out <= (others => '1');
				sram_d_hiz <= '1';
				sram_d_hiz_vec <= (others => '1');
				sram_a_out <= (others => 'X');
			end if;
		end if;
	end process;
	sram_d_in <= sram_d after T_IDELAY;
	sram_nce <= sram_nce_out after T_CO;
	sram_noe <= sram_noe_out after T_CO;
	sram_nwr <= sram_nwr_out after T_CO;
	sram_nbe <= sram_nbe_out after T_CO;
	sram_a <= sram_a_out after T_CO;
	--sram_d <= sram_d_outz after T_CO;
	--sram_d <= sram_d_out after T_CO when sram_d_hiz = '0' else (others => 'Z') after T_CO ;
	process(sram_d_out, sram_d_hiz_vec) -- stupid process to work around vivado problems
	begin
		for i in sram_d_out'range loop
			if sram_d_hiz_vec(i) = '0' then
				sram_d(i) <= sram_d_out(i) after T_CO;
			else
				sram_d(i) <= 'Z' after T_CO;
			end if;
		end loop;
	end process;
end;