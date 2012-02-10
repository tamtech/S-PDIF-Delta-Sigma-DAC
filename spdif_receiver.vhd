----------------------------------------------------------------------------------
-- Engineer: 	Thomas Parry
-- 
-- Create Date:    21:03:14 02/02/2012  
-- Module Name:    decode_v2 - Behavioral 
-- Project Name: 		S/PDIF Delta Sigma Audio DAC
-- Target Devices: 		Spartan 3E 500k on Papilio One dev board
-- Description: 	Decodes the S/PDIF protocol and provides left and right channel as well as reset output
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity decode_v2  is
    Port ( clk : in  STD_LOGIC;
           data : in  STD_LOGIC;
           left : out  STD_LOGIC_VECTOR(15 downto 0) := "0000000000000000";
           right : out  STD_LOGIC_VECTOR(15 downto 0) := "0000000000000000";
			  reset : out STD_LOGIC);
end decode_v2 ;

architecture Behavioral of decode_v2 is

-- constants
constant one : std_logic_vector(1 downto 0) := "01";					-- one lengths of Tclk spdif/2
constant two : std_logic_vector(1 downto 0) := "10";					-- two lengths of Tclk spdif/2
constant three : std_logic_vector(1 downto 0) := "11";				-- three lengths of Tclk spdif/2

-- store pulses
signal prev_state : std_logic := '0';										-- last state for comparing against
signal count : UNSIGNED(4 downto 0) := "00000";							-- count since last change
signal data_reg : std_logic_vector(7 downto 0);							-- register to store last 3 pulses received
signal new_data : std_logic := '0';											-- new data ready
signal temp_data : std_logic := '0';										-- store data state on clock edge
signal decoded : std_logic := '0';											-- current decoded data

-- preamble find
signal audio_block : STD_LOGIC := '0';										-- start of new audio block
signal left_chan : STD_LOGIC := '0';										-- left channel
signal right_chan : STD_LOGIC := '0';										-- right channel
signal current_loc : UNSIGNED(4 downto 0) := "00000";					-- store current location within subframe
signal disable : STD_LOGIC := '0';											-- used to flag when a sample has been fully recorded
signal clear : STD_LOGIC := '0';												-- flag to clear disable
signal ready_out : STD_LOGIC := '0';										-- flag that intermediate sample register can be loaded into output

-- decode
signal phase : std_logic := '0';

-- store
signal enable : STD_LOGIC := '0';											-- enable the storing
signal enable_data : STD_LOGIC := '0';										-- enable the storing
signal index_count : integer range 0 to 15 := 0;						-- for indexing the logic vector
signal pre_count : integer range 0 to 13 := 0;							-- counting before storing bits
signal count_amount : integer range 0 to 13 := 9;						-- how much should the pre count count to

-- intermediate sample registers to fill up as decoding, transfer to outputs on ready_out
signal left_out : STD_LOGIC_VECTOR(15 downto 0) := "0000000000000000";
signal right_out : STD_LOGIC_VECTOR(15 downto 0) := "0000000000000000";

begin

-- find the length of time between the last transition
store_pulse : process(clk)
begin

	if rising_edge(clk) then
	
		-- store current data state, errors otherwise
		temp_data <= data;
	
		-- has the data changed state?
		if temp_data = not(prev_state) then
		
			-- store new previous state of input data
			prev_state <= temp_data;
			
			-- shift down data to make room for new pulse length
			data_reg(3 downto 2) <= data_reg(1 downto 0);
			data_reg(5 downto 4) <= data_reg(3 downto 2);
			data_reg(7 downto 6) <= data_reg(5 downto 4);			
			
			
			---- test to ascertain pulse length
			
			-- pulse length one, 2-7 Tclk
			if (count="00010")or(count="00011")or(count="00100") then
				data_reg(1 downto 0) <= one;
				new_data <= '1';
			
			elsif (count="00101")or(count="00110")or(count="00111") then
				data_reg(1 downto 0) <= one;
				new_data <= '1';
			
			-- pulse length two, 8-13 Tclk
			elsif (count="01000")or(count="01001")or(count="01010") then	
				data_reg(1 downto 0) <= two;
				new_data <= '1';
				
			elsif (count="01011")or(count="01100")or(count="01101") then	
				data_reg(1 downto 0) <= two;
				new_data <= '1';
			
			-- pulse length three, 15-19 Tclk
			elsif (count="01110")or(count="01111")or(count="10000") then
				data_reg(1 downto 0) <= three;
				new_data <= '1';
				
			elsif (count="10001")or(count="10010")or(count="10011") then
				data_reg(1 downto 0) <= three;
				new_data <= '1';

			end if;
			
			-- reset counter
			count <= "00000";
		
		-- no change, increment count
		else
		
			count <= count + "00001";
			new_data <= '0';
			
		end if;
		
	end if;
		
end process store_pulse;


-- monitor the transition length registers to find pre-ambles
preamble_find : process(clk)
begin

if rising_edge(clk) then

	-- check for location
	-- audio block
	if data_reg = three & one & one & three then
		audio_block <= '1';
		ready_out <= '1';
		phase <= '0';
	else
		ready_out <= '0';
	end if;
	
	-- left channel
	if data_reg = three & three & one & one then
		left_chan <= '1';
		ready_out <= '1';
		phase <= '0';
	else
		ready_out <= '0';
	end if;	
	
	-- right channel
	if data_reg = three & two & one & two then
		right_chan <= '1';
		phase <= '0';
	end if;
	
	-- do we have to disable any channels?
	if disable = '1' then
		if audio_block = '1' then
			audio_block <= '0';
			clear <= '1';
		elsif left_chan = '1' then
			left_chan <= '0';
			clear <= '1';
		elsif right_chan = '1' then
			right_chan <= '0';
			clear <= '1';
		end if;
	else
		clear <= '0';
	end if;
	
	if new_data = '1' then
		if data_reg(1 downto 0) = two then
			decoded <= '0';
			enable_data <= '1';
		elsif data_reg(1 downto 0) = one then
			if phase = '1' then
				decoded <= '1';
				enable_data <= '1';
			end if;
			
			phase <= not(phase);
			
		end if;
	else
		enable_data <= '0';
	end if;

end if;

end process preamble_find;



-- store decoded data into correct location
store : process(clk) 

begin

if rising_edge(clk) then
if enable_data = '1' and ((audio_block = '1') or (left_chan = '1') or (right_chan = '1')) then

	-- NOTE:  start indexing at -9 to allow a one data clock cycle for the decoder to catch up
	--			 and then to skip the first 8 auxillary bits	
	if audio_block = '1' then
		count_amount <= 8;
	else
		count_amount <= 9;
	end if;
	
	if not(pre_count = count_amount) then	
		pre_count <= pre_count + 1;
	else

		-- start storing the left channel
		if (left_chan = '1') or (audio_block = '1') then
			left_out(index_count) <= decoded;					-- store the decoded data		
			index_count <= index_count + 1;								-- increment the count
		end if;

		-- start storing the right channel
		if right_chan = '1' then
			right_out(index_count) <= decoded;					-- store the decoded data
			index_count <= index_count + 1;								-- increment the count
		end if;

		-- reset count and set flag to disable channel flags
		if index_count = 15 then
			index_count <= 0;
			disable <= '1';
			pre_count <= 0;
		end if;	

	end if;

end if;


-- if one of the channels is now deactive, reset the disable flag
if clear = '1' then
	disable <= '0';
end if;

-- pass out the data when ready
if ready_out = '1' then
	left <= left_out;
	right <= right_out;
end if;

end if;

end process store;	

end Behavioral;