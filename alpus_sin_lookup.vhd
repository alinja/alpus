-- alpus_sin_lookup
--
-- Quadrant-flipping sin(x)/cos(x) lookup, using a rom lookup of one quadrant of pre-calculated values. Instantiate as function 
-- calls embedded in your pipeline or as a component.
--
-- Optional linear interpolation stage gives a better SNR/SFDR at the expense of two additional multipliers.
-- Current approximation works for 4 to 6 additional phase bits.
--
--
-- Includes Simulation testbench calculating SNR. Performance examples for some parameter combinations:
--
-- Lookup only:
--      8   10   11   12   14   16  phase bits
--  7 40.5                          dB
--  8 42.4 48.8 49.6                dB
-- 10 42.9 54.2 58.4 60.8           dB
-- 12      55.0 60.9 66.2 72.8      dB
-- 14      55.0      67.1 78.4 84.9 dB
-- 16                67.1 79.1 90.4 dB
-- Lookup with 4 bit interpolation (2pi=6.0):
--      8   10   12   14   16  20   phase bits total
-- 10      48.9 56.3 58.5
-- 12           60.4 68.3 70.9
-- 14                72.6 80.5 84.5
-- 16                72.8 84.4 94.7
-- Lookup with 8 bit interpolation (2pi=25/8, uncomment below to use):
--     16   18   20    22   phase bits total
-- 12 70.0 70.3
-- 14 80.0 82.4 82.6
-- 16 83.2 91.7 94.3  94.6 
-- 18      95.2 103.9 106.4
--
--
--
--
-- Sin only 12bit phase x 10bit data: 60.8 dB
-- Artix7:         16 LUT, 22 FF, 1 MEM18K, >300MHz
-- Cyclone10LP:    24 LUT, 14 FF, 1 MEM9K, >250MHz
-- CertusNX:       32 LUT, 12 FF, 1 MEM18K, >200MHz
-- Gowin GW2A:     25 LUT, 12 FF, 1 MEM9K, >250MHz
-- Efinity T13:    32 LUT, 32 FF, 4 RAM5K, >200MHz
--
-- Sin only 9bit phase x 8bit data: 46.3 dB
-- Artix7:      26 LUT, 25 FF, 0 MEM18K, >500MHz
-- Cyclone10LP: 80 LUT, 25 FF, 0 MEM9K, >250MHz
-- CertusNX:    79 LUT, 24 FF, 0 MEM18K, >200MHz
--
-- Sin/cos interpolated with 12+4 phase bits, 16 data bits: 84.4 dB
-- Artix7 -1:        67 LUT,  93 FF, 1 MEM18K, 2 DSP, >280MHz (REG:0111110)
-- Cyclone10GX -6:  100 LUT, 142 FF, 1 MEM20K, 1 DSP, >300MHz (REG:1101100)
-- Cyclone10LP -7:  174 LUT,  94 FF, 5 MEM9K,  2 DSP, >200MHz (REG:0111110)
-- LFD2NX-17 -8hp:  187 LUT, 142 FF, 2 EBR,    2 DSP, >180MHz (REG:1101100)
-- GW5A -C0:        167 LUT, 115 FF, 2 BSRAM,  2 DSP, >130MHz (REG:1111101)
-- Efinity T13 -4:  150 LUT, 189 FF, 8 RAM5K,  2 DSP, >250MHz (REG:1111100)
-- Efinity Tz50 -3: 139 LUT, 134 FF, 4 RAM10K, 2 DSP, >350MHz (REG:1101100)
--
--
--
--
-- Tips: 
-- * Uncomment 2pi=25/8 for more bits, useful for 8 to 10 interpolated phase bits, 
-- * Remove rounding error compensation
--
-- Simple 3-level pipeline would look like this:
--
-- sin_lookup_quadrant   <= alpus_sin_lookup_quadrant(phase);
-- sin_lookup_addr       <= alpus_sin_lookup_addr(phase);
-- sin_lookup_quadrant_i <= sin_lookup_quadrant;
-- sin_val_lookup_i      <= sin_lookup_mem(to_integer(sin_lookup_addr));
-- sin                   <= to_signed(alpus_sin_lookup_out(sin_val_lookup_i, sin_lookup_quadrant_i), sin'length);
--
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package alpus_sin_lookup_pkg is

	type alpus_sin_lookup_init_t is array (integer range <>) of integer;
	
	-- Init a sin table (phase offset +1/2 LSB)
	function alpus_sin_lookup_init( phase_resolution : integer := 2**12;
	                                ampl : real := 2.0**15-1.0; offset : real := 0.0 ) return alpus_sin_lookup_init_t;

	-- TODO: alpus_sin_lookup_init_4q

	-- Quadrant and addr separately when registering needed
	function alpus_sin_lookup_quadrant( phase : unsigned ) return unsigned;
	function alpus_sin_lookup_addr( phase : unsigned ) return unsigned;
	function alpus_sin_lookup_out( lookup_val : integer;             quadrant : unsigned ) return integer;

	function alpus_cos_lookup_quadrant( phase : unsigned ) return unsigned;
	function alpus_cos_lookup_addr( phase : unsigned ) return unsigned;
	function alpus_cos_lookup_out( lookup_val : integer;             quadrant : unsigned ) return integer;

	function alpus_sin_interpolate_fract_x2pi_3(phase_fract : unsigned; quadrant : unsigned) return integer;
	function alpus_sin_interpolate_term( cos_val : integer; phase_fract_x2pi : integer; 
	                                     phase_int_bits : integer; phase_fract_bits : integer; val_bits : integer ) return integer;
	function alpus_sin_interpolate_term( product : integer; 
	                                     phase_int_bits : integer; phase_fract_bits : integer; val_bits : integer ) return integer;
	function alpus_sin_lookup_out( lookup_val : integer; iterm : integer; quadrant : unsigned ) return integer;
	function alpus_cos_lookup_out( lookup_val : integer; iterm : integer; quadrant : unsigned ) return integer;
	
	--TODO: triangle, saw, square
	
	component alpus_sin_lookup is
	generic(
		PHASE_WID : integer := 12;       -- bits of quadrant+lookup
		PHASE_FRACT_WID : integer := 4;  -- bits interpolated
		D_WID : integer := 16;
		HAS_SIN : std_logic := '1';
		HAS_COS : std_logic := '1';
		INTERPOLATE : std_logic := '1';
		ADDR_REG : std_logic := '0';
		MEMOUT_REG : std_logic := '1';
		MEMOUT_REG2 : std_logic := '1'; --quartus needs this instead of ADDR_REG
		INTERPOLATE_REGM1 : std_logic := '1';
		INTERPOLATE_REGM2 : std_logic := '1';
		INTERPOLATE_REGM3 : std_logic := '1';
		INTERPOLATE_REG2XOUT : std_logic := '0';
		AMPLITUDE_SCALE : real := 0.94
	); port(
		clk : in std_logic;
		phase : in unsigned(PHASE_WID+PHASE_FRACT_WID-1 downto 0); -- full range corresponds to full sin period
		sin : out signed(D_WID-1 downto 0);
		cos : out signed(D_WID-1 downto 0)
	);
	end component;

end package;


package body alpus_sin_lookup_pkg is

	function alpus_sin_lookup_init(	phase_resolution : integer := 2**12;
                                    ampl : real := 2.0**15-1.0; offset : real := 0.0 ) return alpus_sin_lookup_init_t is
		variable RET : alpus_sin_lookup_init_t(0 to phase_resolution/4-1);
	begin
		for i in 0 to phase_resolution/4-1 loop
			RET(i) := integer(round(real(ampl) * sin(2.0*MATH_PI * (real(i)+0.5)/real(phase_resolution)) + offset)); 
		end loop;
		return RET;
	end function;




	function alpus_sin_lookup_quadrant( phase : unsigned ) return unsigned is
	begin
		return phase(phase'high downto phase'high-1);
	end function;

	function alpus_sin_lookup_addr( phase : unsigned ) return unsigned is
	begin
		if phase(phase'high-1) = '1' then
			-- quadrant with downward slope 
			return not phase(phase'high-2 downto 0);
		else
			-- quadrant with upward slope 
			return     phase(phase'high-2 downto 0);
		end if;
	end function;

	function alpus_sin_lookup_out( lookup_val : integer; quadrant : unsigned ) return integer is
	begin
		if quadrant(quadrant'high) = '0' then
			return lookup_val;
		else
			return -lookup_val;
		end if;
	end function;

	function alpus_sin_lookup_out( lookup_val : integer; iterm : integer; quadrant : unsigned ) return integer is
		variable lookup_term : integer;
		variable interp_term : integer;
	begin
		if quadrant(quadrant'high) = '0' then
			lookup_term := lookup_val;
			interp_term := iterm;
		else
			lookup_term := -lookup_val;
			interp_term := -iterm;
		end if;
		return lookup_term + interp_term;
	end function;




	function alpus_cos_lookup_quadrant( phase : unsigned ) return unsigned is
	begin
		return phase(phase'high downto phase'high-1) + 1;
	end function;

	function alpus_cos_lookup_addr( phase : unsigned ) return unsigned is
	begin
		if phase(phase'high-1) = '1' then -- quadrant+1 = 0
			-- quadrant with upward slope in sin lookup
			return     phase(phase'high-2 downto 0);
		else
			-- quadrant with downward slope 
			return not phase(phase'high-2 downto 0);
		end if;
	end function;

	function alpus_cos_lookup_out( lookup_val : integer; quadrant : unsigned ) return integer is
	begin
		return alpus_sin_lookup_out(lookup_val, quadrant);
	end function;

	function alpus_cos_lookup_out( lookup_val : integer; iterm : integer; quadrant : unsigned ) return integer is
	begin
		return alpus_sin_lookup_out(lookup_val, iterm, quadrant);
	end function;


	--
	-- sin_interpolated = sinval + (phase_fract-phase_fract_max/2)/phase_fract_max*cosval*2*pi/phasemax
	--

	-- approximate sin = 3
	function alpus_sin_interpolate_fract_x2pi_3(phase_fract : unsigned; quadrant : unsigned ) return integer is
		variable phase_fract_quadrant : unsigned(phase_fract'range);
		variable phase_fract_centered : signed(phase_fract'range);
	begin
		if quadrant(0) = '0' then
			phase_fract_quadrant := phase_fract;
		else
			phase_fract_quadrant := not phase_fract;
		end if;
		phase_fract_centered := signed(phase_fract_quadrant - (2**(phase_fract_quadrant'length-1))); --signed, zero corresponds half lsb
		return to_integer(2*phase_fract_centered) + to_integer(4*phase_fract_centered); -- 2*pi=6, 4...6 phase interp bits
		--return to_integer(2*phase_fract_centered + 4*phase_fract_centered + phase_fract_centered/4); -- 2*pi=25/4, 8...10 interpbits, TODO div round to 0
		--return to_integer(2*phase_fract_centered + 4*phase_fract_centered + phase_fract_centered/4 + phase_fract_centered/32); -- 2*pi=201/32
	end function;

	function alpus_sin_interpolate_term( cos_val : integer; phase_fract_x2pi : integer; 
	                                     phase_int_bits : integer; phase_fract_bits : integer; val_bits : integer ) return integer is
	begin
		return alpus_sin_interpolate_term(phase_fract_x2pi*cos_val, phase_int_bits, phase_fract_bits, val_bits);
	end function;

	function alpus_sin_interpolate_term( product : integer; 
	                                     phase_int_bits : integer; phase_fract_bits : integer; val_bits : integer ) return integer is
		variable post_div_bits : integer := phase_fract_bits + phase_int_bits;
		--variable round_compensation : integer := 0;
		variable round_compensation : integer := 2**(post_div_bits-1);
		variable sin_fract_term : signed(phase_fract_bits+4+val_bits-1 downto 0);
	begin
		sin_fract_term := to_signed(product + round_compensation, sin_fract_term'length);
		return to_integer(sin_fract_term(sin_fract_term'high downto post_div_bits));
	end function;

end;









library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.alpus_sin_lookup_pkg.all;

entity alpus_sin_lookup is
generic(
	PHASE_WID : integer := 12;       -- bits of quadrant+lookup
	PHASE_FRACT_WID : integer := 4;  -- bits interpolated
	D_WID : integer := 16;
	HAS_SIN : std_logic := '1';
	HAS_COS : std_logic := '1';
	INTERPOLATE : std_logic := '1';  -- enables both sin and cos
	ADDR_REG : std_logic := '0';
	MEMOUT_REG : std_logic := '1';
	MEMOUT_REG2 : std_logic := '1';  --quartus may need this instead of ADDR_REG
	INTERPOLATE_REGM1 : std_logic := '1';
	INTERPOLATE_REGM2 : std_logic := '1';
	INTERPOLATE_REGM3 : std_logic := '1';
	INTERPOLATE_REG2XOUT : std_logic := '0';
	AMPLITUDE_SCALE : real := 0.94
); port(
	clk : in std_logic;
	phase : in unsigned(PHASE_WID+PHASE_FRACT_WID-1 downto 0); -- full range corresponds to full sin period
	sin : out signed(D_WID-1 downto 0);
	cos : out signed(D_WID-1 downto 0)
);
end entity alpus_sin_lookup;

architecture rtl of alpus_sin_lookup is
	constant VAL_VALUES : integer := 2**D_WID;
	constant PHASE_VALUES : integer := 2**PHASE_WID;
	constant PHASE_FRACT_X2P_VALUES : integer := 2**(PHASE_FRACT_WID+4);
	constant OFFSET_1S_COMPLEMENT : real := 0.0;
	
	subtype value_integer is integer range -VAL_VALUES/2 to VAL_VALUES/2-1;
	
	signal sin_lookup_quadrant : unsigned(1 downto 0);
	signal sin_lookup_addr : unsigned(PHASE_WID-2-1 downto 0);
	signal sin_lookup_fract : unsigned(PHASE_FRACT_WID-1 downto 0);
	signal cos_lookup_quadrant : unsigned(1 downto 0);
	signal cos_lookup_addr : unsigned(PHASE_WID-2-1 downto 0);

	type alpus_sin_lookup_init_t2 is array (integer range <>) of integer range -VAL_VALUES/2 to VAL_VALUES/2-1;
	signal sin_lookup_mem : alpus_sin_lookup_init_t2(0 to PHASE_VALUES/4-1) 
	                        := alpus_sin_lookup_init_t2(alpus_sin_lookup_init(PHASE_VALUES, AMPLITUDE_SCALE*real(VAL_VALUES/2-1), OFFSET_1S_COMPLEMENT));

	signal sin_lookup_quadrant_i : unsigned(1 downto 0);
	signal sin_val_lookup_i : value_integer;
	signal sin_lookup_fract_x2pin_i : integer := 0;
	signal cos_lookup_quadrant_i : unsigned(1 downto 0);
	signal cos_val_lookup_i : value_integer;
	signal cos_lookup_fract_x2pin_i : integer := 0;

	signal sin_lookup_quadrant_ii : unsigned(1 downto 0);
	signal sin_val_lookup_ii : value_integer;
	signal sin_lookup_fract_x2pin_ii : integer := 0;
	signal cos_lookup_quadrant_ii : unsigned(1 downto 0);
	signal cos_val_lookup_ii : value_integer;
	signal cos_lookup_fract_x2pin_ii : integer := 0;

	--int pl

	signal sin_lookup_quadrant_iii : unsigned(1 downto 0);
	signal sin_val_lookup_iii : value_integer;
	signal sin_val_lookup_iii2 : value_integer;
	signal sin_val_lookup_iii2s : signed(D_WID-1 downto 0) := (others => 'X');
	signal sin_lookup_fract_x2pin_iii : integer := 0;
	signal sin_lookup_fract_x2pin_iiis : signed(PHASE_FRACT_WID+4-1 downto 0) := (others => 'X');
	signal cos_lookup_quadrant_iii : unsigned(1 downto 0);
	signal cos_val_lookup_iii : value_integer;
	signal cos_val_lookup_iii2 : value_integer;
	signal cos_val_lookup_iii2s : signed(D_WID-1 downto 0) := (others => 'X');
	signal cos_lookup_fract_x2pin_iii : integer := 0;
	signal cos_lookup_fract_x2pin_iiis : signed(PHASE_FRACT_WID+4-1 downto 0) := (others => 'X');

	signal sin_lookup_quadrant_iiii : unsigned(1 downto 0);
	signal sin_val_lookup_iiii : value_integer;
	signal sin_iterm_iiii : integer;
	signal cos_lookup_quadrant_iiii : unsigned(1 downto 0);
	signal cos_val_lookup_iiii : value_integer;
	signal cos_iterm_iiii : integer;

	signal sin_lookup_quadrant_iiiii : unsigned(1 downto 0);
	signal sin_val_lookup_iiiii : value_integer;
	signal sin_iterm_iiiii : integer;
	signal cos_lookup_quadrant_iiiii : unsigned(1 downto 0);
	signal cos_val_lookup_iiiii : value_integer;
	signal cos_iterm_iiiii : integer;

	signal sin_iiiiii : integer;
	signal cos_iiiiii : integer;

	attribute ram_style : string;
	attribute ram_style of sin_lookup_mem : signal is "block"; --Vivado: auto/distributed/registers/block/ultra
	attribute syn_romstyle : string;
	attribute syn_romstyle of sin_lookup_mem : signal is "block_rom"; --Synplify: auto/distributed/registers/block_rom
	attribute ramstyle : string;
	attribute ramstyle of sin_lookup_mem : signal is "M20K"; --Quartus: no_rw_check, "logic", "M9K", "M10K", "M20K", "M144K", "MLAB"

	attribute keep : boolean;
	--attribute keep of sin_val_lookup_iii : signal is true;
	--attribute keep of cos_val_lookup_iii : signal is true;
	attribute dont_touch : boolean;
	attribute dont_merge : boolean;
	attribute dont_merge of sin_val_lookup_iii : signal is true;
	attribute dont_merge of cos_val_lookup_iii : signal is true;

begin
	process(clk)
		variable phase_int_v : unsigned(PHASE_WID-1 downto 0);
		variable phase_fract_v : unsigned(PHASE_FRACT_WID-1 downto 0);
		variable sin_lookup_quadrant_v : unsigned(1 downto 0);
		variable sin_lookup_addr_v : unsigned(PHASE_WID-2-1 downto 0);
		variable sin_lookup_fract_v : unsigned(PHASE_FRACT_WID-1 downto 0);
		variable cos_lookup_quadrant_v : unsigned(1 downto 0);
		variable cos_lookup_addr_v : unsigned(PHASE_WID-2-1 downto 0);

		variable sin_lookup_quadrant_iv : unsigned(1 downto 0);
		variable sin_val_lookup_iv : value_integer;
		variable sin_lookup_fract_x2pin_iv : integer;
		variable cos_lookup_quadrant_iv : unsigned(1 downto 0);
		variable cos_val_lookup_iv : value_integer;
		variable cos_lookup_fract_x2pin_iv : integer;

		variable sin_lookup_quadrant_iiv : unsigned(1 downto 0);
		variable sin_val_lookup_iiv : value_integer;
		variable sin_lookup_fract_x2pin_iiv : integer;
		variable cos_lookup_quadrant_iiv : unsigned(1 downto 0);
		variable cos_val_lookup_iiv : value_integer;
		variable cos_lookup_fract_x2pin_iiv : integer;

		variable sin_lookup_quadrant_iiiv : unsigned(1 downto 0);
		variable sin_val_lookup_iiiv : value_integer;
		variable sin_val_lookup_iiiv2 : value_integer;
		variable sin_val_lookup_iiiv2s : signed(D_WID-1 downto 0);
		variable sin_lookup_fract_x2pin_iiiv : integer range -PHASE_FRACT_X2P_VALUES/2 to PHASE_FRACT_X2P_VALUES/2-1;
		variable sin_lookup_fract_x2pin_iiivs : signed(PHASE_FRACT_WID+4-1 downto 0) := (others => 'X');
		variable cos_lookup_quadrant_iiiv : unsigned(1 downto 0);
		variable cos_val_lookup_iiiv : value_integer;
		variable cos_val_lookup_iiiv2 : value_integer;
		variable cos_val_lookup_iiiv2s : signed(D_WID-1 downto 0);
		variable cos_lookup_fract_x2pin_iiiv : integer range -PHASE_FRACT_X2P_VALUES/2 to PHASE_FRACT_X2P_VALUES/2-1;
		variable cos_lookup_fract_x2pin_iiivs : signed(PHASE_FRACT_WID+4-1 downto 0) := (others => 'X');

		variable sin_lookup_quadrant_iiiiv : unsigned(1 downto 0);
		variable sin_val_lookup_iiiiv : value_integer;
		variable sin_iterm_iiiiv : integer;
		variable cos_lookup_quadrant_iiiiv : unsigned(1 downto 0);
		variable cos_val_lookup_iiiiv : value_integer;
		variable cos_iterm_iiiiv : integer;

		variable sin_lookup_quadrant_iiiiiv : unsigned(1 downto 0);
		variable sin_val_lookup_iiiiiv : value_integer;
		variable sin_iterm_iiiiiv : integer;
		variable cos_lookup_quadrant_iiiiiv : unsigned(1 downto 0);
		variable cos_val_lookup_iiiiiv : value_integer;
		variable cos_iterm_iiiiiv : integer;

		variable sin_iiiiiv : integer;
		variable cos_iiiiiv : integer;
	begin
		if rising_edge(clk) then
			phase_int_v := phase(phase'high downto phase'high-PHASE_WID+1);
			phase_fract_v := phase(PHASE_FRACT_WID-1 downto 0);
			
			if HAS_SIN = '1' or INTERPOLATE = '1' then
				if ADDR_REG = '1' then
					sin_lookup_quadrant <= alpus_sin_lookup_quadrant(phase_int_v);
					sin_lookup_addr <= alpus_sin_lookup_addr(phase_int_v);
					sin_lookup_fract <= phase_fract_v;
					sin_lookup_quadrant_v := sin_lookup_quadrant;
					sin_lookup_addr_v := sin_lookup_addr;
					sin_lookup_fract_v := sin_lookup_fract;
				else
					sin_lookup_quadrant_v := alpus_sin_lookup_quadrant(phase_int_v);
					sin_lookup_addr_v := alpus_sin_lookup_addr(phase_int_v);
					sin_lookup_fract_v := phase_fract_v;
				end if;

				if MEMOUT_REG = '1' then
					sin_lookup_quadrant_i <= sin_lookup_quadrant_v;
					sin_val_lookup_i <= sin_lookup_mem(to_integer(sin_lookup_addr_v));
					sin_lookup_fract_x2pin_i <= alpus_sin_interpolate_fract_x2pi_3(sin_lookup_fract_v, sin_lookup_quadrant_v);
					sin_lookup_quadrant_iv := sin_lookup_quadrant_i;
					sin_val_lookup_iv := sin_val_lookup_i;
					sin_lookup_fract_x2pin_iv := sin_lookup_fract_x2pin_i;
				else
					sin_lookup_quadrant_iv := sin_lookup_quadrant_v;
					sin_val_lookup_iv := sin_lookup_mem(to_integer(sin_lookup_addr_v));
					sin_lookup_fract_x2pin_iv := alpus_sin_interpolate_fract_x2pi_3(sin_lookup_fract_v, sin_lookup_quadrant_v);
				end if;
				
				if MEMOUT_REG2 = '1' then
					sin_lookup_quadrant_ii <= sin_lookup_quadrant_iv;
					sin_val_lookup_ii <= sin_val_lookup_iv;
					sin_lookup_fract_x2pin_ii <= sin_lookup_fract_x2pin_iv;
					sin_lookup_quadrant_iiv := sin_lookup_quadrant_ii;
					sin_val_lookup_iiv := sin_val_lookup_ii;
					sin_lookup_fract_x2pin_iiv := sin_lookup_fract_x2pin_ii;
				else
					sin_lookup_quadrant_iiv := sin_lookup_quadrant_iv;
					sin_val_lookup_iiv := sin_val_lookup_iv;
					sin_lookup_fract_x2pin_iiv := sin_lookup_fract_x2pin_iv;
				end if;

				if INTERPOLATE = '0' then
					sin_iiiiiv := alpus_sin_lookup_out(sin_val_lookup_iiv, sin_lookup_quadrant_iiv);		
					sin <= to_signed(sin_iiiiiv, sin'length);
				end if;
			else
				sin <= (others => 'X'); --override below
			end if;

			if HAS_COS = '1' or INTERPOLATE = '1' then
				if ADDR_REG = '1' then
					cos_lookup_quadrant <= alpus_cos_lookup_quadrant(phase_int_v);
					cos_lookup_addr <= alpus_cos_lookup_addr(phase_int_v);
					cos_lookup_quadrant_v := cos_lookup_quadrant;
					cos_lookup_addr_v := cos_lookup_addr;
				else
					cos_lookup_quadrant_v := alpus_cos_lookup_quadrant(phase_int_v);
					cos_lookup_addr_v := alpus_cos_lookup_addr(phase_int_v);
				end if;

				if MEMOUT_REG = '1' then
					cos_lookup_quadrant_i <= cos_lookup_quadrant_v;
					cos_val_lookup_i <= sin_lookup_mem(to_integer(cos_lookup_addr_v));
					cos_lookup_fract_x2pin_i <= alpus_sin_interpolate_fract_x2pi_3(sin_lookup_fract_v, cos_lookup_quadrant_v);
					cos_lookup_quadrant_iv := cos_lookup_quadrant_i;
					cos_val_lookup_iv := cos_val_lookup_i;
					cos_lookup_fract_x2pin_iv := cos_lookup_fract_x2pin_i;
				else
					cos_lookup_quadrant_iv := cos_lookup_quadrant_v;
					cos_val_lookup_iv := sin_lookup_mem(to_integer(cos_lookup_addr_v));
					cos_lookup_fract_x2pin_iv := alpus_sin_interpolate_fract_x2pi_3(sin_lookup_fract_v, cos_lookup_quadrant_v);
				end if;

				if MEMOUT_REG2 = '1' then
					cos_lookup_quadrant_ii <= cos_lookup_quadrant_iv;
					cos_val_lookup_ii <= cos_val_lookup_iv;
					cos_lookup_fract_x2pin_ii <= cos_lookup_fract_x2pin_iv;
					cos_lookup_quadrant_iiv := cos_lookup_quadrant_ii;
					cos_val_lookup_iiv := cos_val_lookup_ii;
					cos_lookup_fract_x2pin_iiv := cos_lookup_fract_x2pin_ii;
				else
					cos_lookup_quadrant_iiv := cos_lookup_quadrant_iv;
					cos_val_lookup_iiv := cos_val_lookup_iv;
					cos_lookup_fract_x2pin_iiv := cos_lookup_fract_x2pin_iv;
				end if;

				if INTERPOLATE = '0' then
					cos_iiiiiv := alpus_cos_lookup_out(cos_val_lookup_iiv, cos_lookup_quadrant_iiv);		
					cos <= to_signed(cos_iiiiiv, sin'length);
				end if;
			else
				cos <= (others => 'X'); --override below
			end if;
				
			if INTERPOLATE = '1' then
				if INTERPOLATE_REGM1 = '1' then
					sin_lookup_quadrant_iii <= sin_lookup_quadrant_iiv;
					sin_val_lookup_iii <= sin_val_lookup_iiv;
					sin_val_lookup_iii2 <= sin_val_lookup_iiv;
					sin_val_lookup_iii2s <= to_signed(sin_val_lookup_iiv, D_WID);
					sin_lookup_fract_x2pin_iii <= sin_lookup_fract_x2pin_iiv;
					sin_lookup_fract_x2pin_iiis <= to_signed(sin_lookup_fract_x2pin_iiv, PHASE_FRACT_WID+4);
					sin_lookup_quadrant_iiiv := sin_lookup_quadrant_iii;
					sin_val_lookup_iiiv := sin_val_lookup_iii;
					sin_val_lookup_iiiv2 := sin_val_lookup_iii2;
					sin_val_lookup_iiiv2s := sin_val_lookup_iii2s;
					sin_lookup_fract_x2pin_iiiv := sin_lookup_fract_x2pin_iii;
					sin_lookup_fract_x2pin_iiivs := sin_lookup_fract_x2pin_iiis;
			
					cos_lookup_quadrant_iii <= cos_lookup_quadrant_iiv;
					cos_val_lookup_iii <= cos_val_lookup_iiv;
					cos_val_lookup_iii2 <= cos_val_lookup_iiv;
					cos_val_lookup_iii2s <= to_signed(cos_val_lookup_iiv, D_WID);
					cos_lookup_fract_x2pin_iii <= cos_lookup_fract_x2pin_iiv;
					cos_lookup_fract_x2pin_iiis <= to_signed(cos_lookup_fract_x2pin_iiv, PHASE_FRACT_WID+4);
					cos_lookup_quadrant_iiiv := cos_lookup_quadrant_iii;
					cos_val_lookup_iiiv := cos_val_lookup_iii;
					cos_val_lookup_iiiv2 := cos_val_lookup_iii2;
					cos_val_lookup_iiiv2s := cos_val_lookup_iii2s;
					cos_lookup_fract_x2pin_iiiv := cos_lookup_fract_x2pin_iii;
					cos_lookup_fract_x2pin_iiivs := cos_lookup_fract_x2pin_iiis;
				else
					sin_lookup_quadrant_iiiv := sin_lookup_quadrant_iiv;
					sin_val_lookup_iiiv := sin_val_lookup_iiv;
					sin_val_lookup_iiiv2 := sin_val_lookup_iiv;
					sin_val_lookup_iiiv2s := to_signed(sin_val_lookup_iiv, D_WID);
					sin_lookup_fract_x2pin_iiiv := sin_lookup_fract_x2pin_iiv;
					sin_lookup_fract_x2pin_iiivs := to_signed(sin_lookup_fract_x2pin_iiv, PHASE_FRACT_WID+4);

					cos_lookup_quadrant_iiiv := cos_lookup_quadrant_iiv;
					cos_val_lookup_iiiv := cos_val_lookup_iiv;
					cos_val_lookup_iiiv2 := cos_val_lookup_iiv;
					cos_val_lookup_iiiv2s := to_signed(cos_val_lookup_iiv, D_WID);
					cos_lookup_fract_x2pin_iiiv := cos_lookup_fract_x2pin_iiv;
					cos_lookup_fract_x2pin_iiivs := to_signed(cos_lookup_fract_x2pin_iiv, PHASE_FRACT_WID+4);
				end if;
				
				if INTERPOLATE_REGM2 = '1' then
					sin_lookup_quadrant_iiii <= sin_lookup_quadrant_iiiv;
					sin_val_lookup_iiii <= sin_val_lookup_iiiv;
					--sin_iterm_iiii <= (cos_val_lookup_iiiv2 * sin_lookup_fract_x2pin_iiiv);
					sin_iterm_iiii <= to_integer(cos_val_lookup_iiiv2s * sin_lookup_fract_x2pin_iiivs);
					sin_lookup_quadrant_iiiiv := sin_lookup_quadrant_iiii;
					sin_val_lookup_iiiiv := sin_val_lookup_iiii;
					sin_iterm_iiiiv := sin_iterm_iiii;

					cos_lookup_quadrant_iiii <= cos_lookup_quadrant_iiiv;
					cos_val_lookup_iiii <= cos_val_lookup_iiiv;
					--cos_iterm_iiii <= (sin_val_lookup_iiiv2 * cos_lookup_fract_x2pin_iiiv);
					cos_iterm_iiii <= to_integer(sin_val_lookup_iiiv2s * cos_lookup_fract_x2pin_iiivs);
					cos_lookup_quadrant_iiiiv := cos_lookup_quadrant_iiii;
					cos_val_lookup_iiiiv := cos_val_lookup_iiii;
					cos_iterm_iiiiv := cos_iterm_iiii;
				else
					sin_lookup_quadrant_iiiiv := sin_lookup_quadrant_iiiv;
					sin_val_lookup_iiiiv := sin_val_lookup_iiiv;
					--sin_iterm_iiiiv := (cos_val_lookup_iiiv2 * sin_lookup_fract_x2pin_iiiv);
					sin_iterm_iiiiv := to_integer(cos_val_lookup_iiiv2s * sin_lookup_fract_x2pin_iiivs);
			
					cos_lookup_quadrant_iiiiv := cos_lookup_quadrant_iiiv;
					cos_val_lookup_iiiiv := cos_val_lookup_iiiv;
					--cos_iterm_iiiiv := (sin_val_lookup_iiiv2 * cos_lookup_fract_x2pin_iiiv);
					cos_iterm_iiiiv := to_integer(sin_val_lookup_iiiv2s * cos_lookup_fract_x2pin_iiivs);
				end if;

				if INTERPOLATE_REGM3 = '1' then
					sin_lookup_quadrant_iiiii <= sin_lookup_quadrant_iiiiv;
					sin_val_lookup_iiiii <= sin_val_lookup_iiiiv;
					sin_iterm_iiiii <= alpus_sin_interpolate_term(sin_iterm_iiiiv, PHASE_WID, PHASE_FRACT_WID, D_WID);
					sin_lookup_quadrant_iiiiiv := sin_lookup_quadrant_iiiii;
					sin_val_lookup_iiiiiv := sin_val_lookup_iiiii;
					sin_iterm_iiiiiv := sin_iterm_iiiii;

					cos_lookup_quadrant_iiiii <= cos_lookup_quadrant_iiiiv;
					cos_val_lookup_iiiii <= cos_val_lookup_iiiiv;
					cos_iterm_iiiii <= alpus_sin_interpolate_term(cos_iterm_iiiiv, PHASE_WID, PHASE_FRACT_WID, D_WID);
					cos_lookup_quadrant_iiiiiv := cos_lookup_quadrant_iiiii;
					cos_val_lookup_iiiiiv := cos_val_lookup_iiiii;
					cos_iterm_iiiiiv := cos_iterm_iiiii;
				else
					sin_lookup_quadrant_iiiiiv := sin_lookup_quadrant_iiiiv;
					sin_val_lookup_iiiiiv := sin_val_lookup_iiiiv;
					sin_iterm_iiiiiv := alpus_sin_interpolate_term(sin_iterm_iiiiv, PHASE_WID, PHASE_FRACT_WID, D_WID);

					cos_lookup_quadrant_iiiiiv := cos_lookup_quadrant_iiiiv;
					cos_val_lookup_iiiiiv := cos_val_lookup_iiiiv;
					cos_iterm_iiiiiv := alpus_sin_interpolate_term(cos_iterm_iiiiv, PHASE_WID, PHASE_FRACT_WID, D_WID);
				end if;

				sin_iiiiiv := alpus_sin_lookup_out(sin_val_lookup_iiiiiv, sin_iterm_iiiiiv, sin_lookup_quadrant_iiiiiv);		
				cos_iiiiiv := alpus_cos_lookup_out(cos_val_lookup_iiiiiv, cos_iterm_iiiiiv, cos_lookup_quadrant_iiiiiv);		
				if INTERPOLATE_REG2XOUT = '1' then
					sin_iiiiii <= sin_iiiiiv;		
					cos_iiiiii <= cos_iiiiiv;		
					sin <= to_signed(sin_iiiiii, sin'length);
					cos <= to_signed(cos_iiiiii, cos'length);
				else
					sin <= to_signed(sin_iiiiiv, sin'length);
					cos <= to_signed(cos_iiiiiv, cos'length);
				end if;
			end if;

			--TODO interpolate: sin= sin_int + phase_fract * cos_int * span
			-- sin([0.5 1.5]*2*pi/256)*2048 -8*pi*2047/2048
			-- sinmax=65536/2;phasemax=256;phase_fract_max=16;phase=1;phase_fract=0;sinval=round(sin((phase+0.5)*2*pi/phasemax)*sinmax);cosval=round(cos((phase+0.5)*2*pi/phasemax)*sinmax);sinint=sinval + (phase_fract-phase_fract_max/2)/phase_fract_max*3.14*cosval/sinmax*phasemax
			-- -> cosval can be taken from same memory approximating pi, or separate mem with accurate pi
			-- approx pi=3 -> -4.5% error, pi=(16+8+1)/8 -> -0.53% error,
			-- pi=(8-1)/2 -> +11.4% error, pi=(16+8+2)/8 -> +3.5% error
			-- -> lower cosval lookup max by
			
		end if;
	end process;
end;








-- synthesis translate_off
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.alpus_sin_lookup_pkg.all;

entity alpus_sin_lookup_tb is
end entity alpus_sin_lookup_tb;


architecture tb of alpus_sin_lookup_tb is
	constant SIN_PHASE_BITS : integer := 12;
	constant SIN_FRACT_BITS : integer := 4;
	constant SIN_VAL_BITS : integer := 16;
	constant SIN_AMPLITUDE_SCALE : real := 0.94;
	constant SIN_VAL_VALUES : integer := 2**SIN_VAL_BITS;
	constant SIN_PHASE_VALUES : integer := 2**SIN_PHASE_BITS;

	signal sin_lookup : alpus_sin_lookup_init_t(0 to SIN_PHASE_VALUES/4-1) := alpus_sin_lookup_init(SIN_PHASE_VALUES, real(SIN_VAL_VALUES)/2.0-1.0);

	signal sin_lookup_val : integer range 0 to SIN_VAL_VALUES-1;
	signal sin_val : signed(SIN_VAL_BITS-1 downto 0);
	signal cos_val : signed(SIN_VAL_BITS-1 downto 0);
	signal sin_lookup_quadrant : unsigned(1 downto 0);
	signal sin_lookup_addr : unsigned(SIN_PHASE_BITS-2-1 downto 0);
	signal sin_lookup_err : integer;
	signal cos_lookup_err : integer;
	
	signal clk : std_logic := '1';
	signal phase_acc : unsigned(31 downto 0) := x"00000000";
	signal phase_inst : unsigned(SIN_PHASE_BITS-1 downto 0);
	signal phase_real : real := 0.0;
	signal phase_real_i : real := 0.0;
	signal phase_real_ii : real := 0.0;
	signal phase_real_iii : real := 0.0;
	signal phase_real_iiii : real := 0.0;
	signal phase_real_iiiii : real := 0.0;
	signal sin_real : real := 0.0;
	signal cos_real : real := 0.0;
	signal sin_val_out : signed(SIN_VAL_BITS-1 downto 0);
	signal cos_val_out : signed(SIN_VAL_BITS-1 downto 0);

begin

	process is
		variable error : real;
		variable error2 : real;
		variable phase : unsigned(SIN_PHASE_BITS-1 downto 0);
		variable sin_lookup_quadrant_v : unsigned(1 downto 0);
		variable sin_lookup_addr_v : unsigned(SIN_PHASE_BITS-2-1 downto 0);
		variable cos_lookup_quadrant_v : unsigned(1 downto 0);
		variable cos_lookup_addr_v : unsigned(SIN_PHASE_BITS-2-1 downto 0);
		variable sin_val_v : integer;
		variable cos_val_v : integer;
		variable error_acc : real;
		variable power_acc : real;
		variable dc_acc : real;
		variable error_acc2 : real;
		variable power_acc2 : real;
		variable dc_acc2 : real;
		variable len_testrun : integer := 100107;
	begin
		for i in 0 to 2*SIN_PHASE_VALUES-1 loop
			phase := to_unsigned(i, phase'length);
			--phase_inst <= phase;
			
			sin_lookup_quadrant_v := alpus_sin_lookup_quadrant(phase);
			sin_lookup_addr_v := alpus_sin_lookup_addr(phase);
			sin_lookup_quadrant <= sin_lookup_quadrant_v;
			sin_lookup_addr <= sin_lookup_addr_v;

			sin_val_v := alpus_sin_lookup_out(sin_lookup(to_integer(sin_lookup_addr_v)), sin_lookup_quadrant_v );
			sin_val <= to_signed(sin_val_v, sin_val'length);

			error := real(sin_val_v) - real(SIN_VAL_VALUES/2-1)*sin(2.0*MATH_PI * (real(i)+0.5)/real(SIN_PHASE_VALUES));
			assert error <= 0.5 severity failure;
			--report "sin_lookup[" & integer'image(i) & "]=" & integer'image(sin_lookup(i)) & " err=" & real'image(error);
			sin_lookup_err <= integer(error*100.0)+1000000;



			cos_lookup_quadrant_v := alpus_cos_lookup_quadrant(phase);
			cos_lookup_addr_v := alpus_cos_lookup_addr(phase);

			cos_val_v := alpus_cos_lookup_out(sin_lookup(to_integer(cos_lookup_addr_v)), cos_lookup_quadrant_v );
			cos_val <= to_signed(cos_val_v, cos_val'length);

			error := real(cos_val_v) - real(SIN_VAL_VALUES/2-1)*cos(2.0*MATH_PI * (real(i)+0.5)/real(SIN_PHASE_VALUES));
			assert error <= 0.5 severity failure;
			--report "sin_lookup[" & integer'image(i) & "]=" & integer'image(sin_lookup(i)) & " err=" & real'image(error);
			cos_lookup_err <= integer(error*100.0)+1000000;

			wait for 10 ns;
		end loop;
		
		error_acc := 0.0;
		power_acc := 0.0;
		dc_acc := 0.0;
		error_acc2 := 0.0;
		power_acc2 := 0.0;
		dc_acc2 := 0.0;
		for i in 1 to len_testrun loop
			phase_acc <= phase_acc + x"02345678";
			--phase_acc <= phase_acc + x"02000000";

			-- p1
			phase_real <= 2.0*MATH_PI * real(to_integer(signed(phase_acc)))/(2.0**(phase_acc'length-SIN_PHASE_BITS))/real(SIN_PHASE_VALUES);
			-- p2
			phase_real_i <= phase_real;
			phase_real_ii <= phase_real_i;
			phase_real_iii <= phase_real_ii;
			phase_real_iiii <= phase_real_iii;
			phase_real_iiiii <= phase_real_iiii;
			
			sin_real <= SIN_AMPLITUDE_SCALE*real(SIN_VAL_VALUES/2-1)*sin(phase_real_iiiii);
			cos_real <= SIN_AMPLITUDE_SCALE*real(SIN_VAL_VALUES/2-1)*cos(phase_real_iiiii);
			
			--error := real(to_integer(sin_val_out)) - SIN_AMPLITUDE_SCALE*real(SIN_VAL_VALUES/2-1)*sin(phase_real_i);
			error := real(to_integer(sin_val_out)) - sin_real;
			error2 := real(to_integer(cos_val_out)) - cos_real;
			if i > 123 then
				sin_lookup_err <= integer(error*100.0)+1000000;
				error_acc := error_acc + error*error;
				dc_acc := dc_acc + real(to_integer(sin_val_out));
				power_acc := power_acc + real(to_integer(sin_val_out))*real(to_integer(sin_val_out));
				cos_lookup_err <= integer(error2*100.0)+1000000;
				error_acc2 := error_acc2 + error2*error2;
				dc_acc2 := dc_acc2 + real(to_integer(cos_val_out));
				power_acc2 := power_acc2 + real(to_integer(cos_val_out))*real(to_integer(cos_val_out));
			end if;
			
			wait until rising_edge(clk);	
		end loop;

		--report "error_acc: " & real'image(error_acc);
		--report "power_acc: " & real'image(power_acc);
		--report "DC level: " & to_string(10.0*log10(dc_acc*dc_acc/real(len_testrun) / power_acc), "%.1f") & " dB";
		--report "DC level avg: " & to_string(dc_acc/real(len_testrun), "%.3f") & " LSB";
		report "Sin(x) SNR: " & to_string(10.0*log10(power_acc/error_acc), "%.1f") & " dB, " &
		"DC level: " & to_string(10.0*log10(dc_acc*dc_acc/real(len_testrun) / power_acc), "%.1f") & " dB, " &
		"DC level avg: " & to_string(dc_acc/real(len_testrun), "%.3f") & " LSB";
		report "Cos(x) SNR: " & to_string(10.0*log10(power_acc2/error_acc2), "%.1f") & " dB, " &
		"DC level: " & to_string(10.0*log10(dc_acc2*dc_acc2/real(len_testrun) / power_acc2), "%.1f") & " dB, " &
		"DC level avg: " & to_string(dc_acc2/real(len_testrun), "%.3f") & " LSB";

		wait;
	end process;

	clk <= not clk after 5 ns;

	dut: alpus_sin_lookup generic map (
		PHASE_WID => SIN_PHASE_BITS,
		D_WID => SIN_VAL_BITS,
		PHASE_FRACT_WID => SIN_FRACT_BITS,
		INTERPOLATE => '1',
		ADDR_REG => '1',
		MEMOUT_REG => '1',
		MEMOUT_REG2 => '1',
		INTERPOLATE_REGM1 => '1',
		INTERPOLATE_REGM2 => '1',
		INTERPOLATE_REGM3 => '0',
		INTERPOLATE_REG2XOUT => '1',
		AMPLITUDE_SCALE => SIN_AMPLITUDE_SCALE
	) port map (
		clk => clk,
		phase => phase_acc(phase_acc'high downto phase_acc'high - (SIN_PHASE_BITS+SIN_FRACT_BITS-1)),
		sin => sin_val_out,
		cos => cos_val_out );

end;
-- synthesis translate_on
