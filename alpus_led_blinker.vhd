-- alpus_led_blinker
--
-- Blinks a led. Every design starts with blinking a led to see that configuration succeeds and clocks and reset are working.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;

package alpus_led_blinker_pkg is
component alpus_led_blinker is
generic(
	PERIOD_LEN : integer := 28;
	PERIOD_LEN_SIM : integer := 8;
	DUTY_LEN : integer := 4;
	LED_ON : std_logic := '1';
	LED_OFF : std_logic := '0'
);
port(
	clk : in std_logic;
	rst : in std_logic := '0';
	led : out std_logic
);
end component;
end package;



library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alpus_led_blinker is
generic(
	PERIOD_LEN : integer := 28;
	PERIOD_LEN_SIM : integer := 8;
	DUTY_LEN : integer := 4;
	LED_ON : std_logic := '1';
	LED_OFF : std_logic := '0'
);
port(
	clk : in std_logic;
	rst : in std_logic := '0';
	led : out std_logic
);
end entity alpus_led_blinker;

architecture rtl of alpus_led_blinker is

	signal led_ctr : unsigned(PERIOD_LEN-1
-- synthesis translate_off
                              -PERIOD_LEN+PERIOD_LEN_SIM
-- synthesis translate_on
                                           downto 0) := (others => '0');

begin

	process(clk)
	begin
		if rising_edge(clk) then
			led_ctr <= led_ctr + 1;
			
			if led_ctr(led_ctr'high downto led_ctr'high-DUTY_LEN+1) = 0 then
				led <= LED_ON;
			else
				led <= LED_OFF;
			end if;
			
			if rst = '1' then
				led_ctr <= (others => '0');
			end if;
		end if;
	end process;

end;



