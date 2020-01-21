-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Matej Otcenas
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  
  type fsm_state is (
    state_idle, state_fetch,
    state_decode,
    state_value_inc_0, state_value_inc_1, 
    state_value_dec_0, state_value_dec_1,
    state_ptr_inc,
    state_ptr_dec,
    state_while_start_0, state_while_start_1, state_while_start_2, state_while_start_3,
    state_while_end_0, state_while_end_1, state_while_end_2, state_while_end_3, state_while_end_4,
    state_value_print_0, state_value_print_1,
    state_value_load_0, state_value_load_1,
    state_value_tmp_store_0, state_value_tmp_store_1,
    state_value_tmp_load_0, state_value_tmp_load_1, state_value_tmp_load_2,
    state_stop,
    state_ignore
  );

  signal pstate : fsm_state; -- present state
  signal nstate : fsm_state; -- next state

  -- PC
  signal pc_reg: std_logic_vector (12 downto 0);
  signal pc_inc: std_logic;
  signal pc_dec: std_logic;

  -- PTR
  signal ptr_reg: std_logic_vector (12 downto 0);
  signal ptr_inc: std_logic;
  signal ptr_dec: std_logic;

  -- CNT
  signal cnt_reg: std_logic_vector (7 downto 0);
  signal cnt_inc: std_logic;
  signal cnt_dec: std_logic;

  -- MUX1
  signal mx1_data_addr_sel: std_logic_vector(0 downto 0); -- in

  -- MUX2
  signal mx2_data_addr: std_logic_vector (12 downto 0); -- out
  signal mx2_data_addr_sel: std_logic_vector (0 downto 0); -- in

  -- MUX3
  signal mx3_data_wdata_sel: std_logic_vector (1 downto 0); -- in
 

------------------------------------- BEGIN -------------------------------------------
  begin
    
    -- PC register
    pc_cntr: process(RESET, CLK)
    begin
      if(RESET = '1') then
        pc_reg <= (others => '0');
      elsif (CLK'event) and CLK = '1' then
        if(pc_inc = '1') then 
          pc_reg <= pc_reg + 1;
        elsif(pc_dec = '1') then
          pc_reg <= pc_reg - 1;
        end if;
      end if ;
    end process;

    -- PTR register
    ptr_cntr: process(RESET, CLK)
    begin
      if(RESET = '1') then
        ptr_reg <= "1000000000000";
      elsif (CLK'event) and CLK = '1' then
        if(ptr_inc = '1') then 
          if ptr_reg = "1111111111111" then
            ptr_reg <= "1000000000000";
          else
            ptr_reg <= ptr_reg + 1;
          end if;
        elsif(ptr_dec = '1') then
          if ptr_reg = "1000000000000" then
            ptr_reg <= "1111111111111";
          else
            ptr_reg <= ptr_reg - 1;
          end if;  
        end if;
      end if ;
    end process;

    -- CNT register
    cnt_cntr: process(RESET, CLK)
    begin
      if(RESET = '1') then
        cnt_reg <= (others => '0');
      elsif (CLK'event) and CLK = '1' then
        if(cnt_inc = '1') then 
          cnt_reg <= cnt_reg + 1;
        elsif(cnt_dec = '1') then
          cnt_reg <= cnt_reg - 1;
        end if;
      end if ;
    end process;

    -- MUX1
    mx1: process (mx1_data_addr_sel, pc_reg, mx2_data_addr)
    begin
      if (mx1_data_addr_sel = "0") then
        DATA_ADDR <= pc_reg;
      else
        DATA_ADDR <= mx2_data_addr;
      end if;
    end process;

    -- MUX2
    mx2: process (mx2_data_addr_sel,ptr_reg)
    begin
      if (mx2_data_addr_sel = "0") then
        mx2_data_addr <= ptr_reg;
      else
        mx2_data_addr <= "1000000000000";
      end if ;
    end process;

    -- MUX3
    mx3_data_wdata_cntr: process(mx3_data_wdata_sel, DATA_RDATA, IN_DATA)
    begin
        case mx3_data_wdata_sel is

          when "00" => DATA_WDATA <= IN_DATA;

          when "01" => DATA_WDATA <= DATA_RDATA - 1;

          when "10" => DATA_WDATA <= DATA_RDATA + 1;
          
          when others => DATA_WDATA <= DATA_RDATA;
        
        end case ;
    end process;

    -- Present state
    pstate_reg: process(CLK, RESET, EN)
    begin
      if RESET = '1' then
        pstate <= state_idle;
      elsif CLK'event and CLK = '1' then
        if EN = '1' then
          pstate <= nstate;
        end if ;
      end if ;
    end process;


    -- Next state
    nstate_reg: process(pstate, OUT_BUSY, IN_VLD, DATA_RDATA, cnt_reg)
    begin
      -- INITIALIZATION
      nstate <= state_idle; -- first state
      IN_REQ <= '0';  
      OUT_WE <= '0';
      cnt_inc <= '0';
      cnt_dec <= '0';
      pc_inc <= '0';
      pc_dec <= '0';
      ptr_inc <= '0';
      ptr_dec <= '0';
      mx1_data_addr_sel <= "1";
      mx2_data_addr_sel <= "0";
      mx3_data_wdata_sel <= "00";
      DATA_EN <= '0';
      DATA_RDWR <= '0';
      OUT_DATA <= DATA_RDATA;

      case pstate is
        -- IDLE
        when state_idle => 
              nstate <= state_fetch;
        
        -- FETCH
        when state_fetch => 
              DATA_EN <= '1';
              DATA_RDWR <= '0';
              mx1_data_addr_sel <= "0";
              nstate <= state_decode;
        
        -- DECODE
        when state_decode =>
          case DATA_RDATA is
          
            when X"3E" => nstate <= state_ptr_inc; -- '>'

            when X"3C" => nstate <= state_ptr_dec; -- '<'
            
            when X"2B" => nstate <= state_value_inc_0; -- '+'

            when X"2D" => nstate <= state_value_dec_0; -- '-'

            when X"5B" => nstate <= state_while_start_0; -- '['

            when X"5D" => nstate <= state_while_end_0; -- ']'

            when X"2E" => nstate <= state_value_print_0; -- '.'
            
            when X"2C" => nstate <= state_value_load_0; -- ','
            
            when X"24" => nstate <= state_value_tmp_store_0; -- '$'
            
            when X"21" => nstate <= state_value_tmp_load_0; -- '!'
            
            when X"00" => nstate <= state_stop; -- 'null'

            when others => nstate <= state_ignore; -- comment blocks 
          
          end case;
        
        -----------------------------------------------------------------
        -- PTR += 1 --> '>'
        when state_ptr_inc =>
                pc_inc <= '1';
                ptr_inc <= '1'; -- pointer to memory block increments '>'
                nstate <= state_fetch; -- read new instruction
        ------------------------------------------------------------------
        -- PTR -= 1 --> '<'
        when state_ptr_dec =>
                pc_inc <= '1';
                ptr_dec <= '1';
                nstate <= state_fetch;
        ------------------------------------------------------------------
        -- *PTR += 1 --> '+'
        when state_value_inc_0 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                nstate <= state_value_inc_1;
        
        when state_value_inc_1 => -- '+'
                mx1_data_addr_sel <= "1";
                mx3_data_wdata_sel <= "10"; -- DATA_RDATA + 1
                DATA_EN <= '1';   
                DATA_RDWR <= '1';
                pc_inc <= '1'; 
                nstate <= state_fetch;
        ------------------------------------------------------------------        
        -- *PTR -= 1 --> '-'
        when state_value_dec_0 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                nstate <= state_value_dec_1;

        when state_value_dec_1 => -- '-'
                mx1_data_addr_sel <= "1";
                mx3_data_wdata_sel <= "01"; -- DATA_RDATA - 1
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                nstate <= state_fetch;
        ------------------------------------------------------------------
        -- *PTR = GETCHAR() --> ','
        when state_value_load_0 => 
                IN_REQ <= '1';
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_data_addr_sel <= "1";
                nstate <= state_value_load_1;

        when state_value_load_1 =>
                if IN_VLD = '1' then
                  mx3_data_wdata_sel <= "00";
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
                  pc_inc <= '1';
                  nstate <= state_fetch;
                else
                  nstate <= state_value_load_1;
                end if;
        ------------------------------------------------------------------
         -- PUTCHAR(*ptr) --> '.'
        when state_value_print_0 => 
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                nstate <= state_value_print_1;
                
        when state_value_print_1 =>
                mx1_data_addr_sel <= "1";
                if OUT_BUSY = '0' then
                  OUT_WE <= '1';
                  OUT_DATA <= DATA_RDATA;
                  pc_inc <= '1';
                  nstate <= state_fetch;
                else
                  nstate <= state_value_print_1;
                end if;
        -------------------------------------------------------------------
        -- TMP = *PTR --> '$'
        when state_value_tmp_store_0 =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                nstate <= state_value_tmp_store_1;
        
        when state_value_tmp_store_1 =>
                mx3_data_wdata_sel <= "11";
                mx2_data_addr_sel <= "1";
                mx1_data_addr_sel <= "1";
                DATA_EN <= '1';   
                DATA_RDWR <= '1';
                pc_inc <= '1'; 
                nstate <= state_fetch;
        -------------------------------------------------------------------
        -- *PTR = TMP --> '!'
        when state_value_tmp_load_0 =>
                mx2_data_addr_sel <= "1";
                mx1_data_addr_sel <= "1";
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                nstate <= state_value_tmp_load_1;

        when state_value_tmp_load_1 =>
                mx2_data_addr_sel <= "0";
                mx1_data_addr_sel <= "1";
                nstate <= state_value_tmp_load_2;
        
        when state_value_tmp_load_2 =>
                mx3_data_wdata_sel <= "11";
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                pc_inc <= '1';
                nstate <= state_fetch;

        -------------------------------------------------------------------
        -- WHILE (*PTR) { --> '['
        when state_while_start_0 =>
                 DATA_EN <= '1';
                 DATA_RDWR <= '0';
                 mx1_data_addr_sel <= "1";
                 mx2_data_addr_sel <= "0";
                 pc_inc <= '1';
                 nstate <= state_while_start_1;

        when state_while_start_1 =>
                 if DATA_RDATA = "00000000" then
                   cnt_inc <= '1';
                   nstate <= state_while_start_2;
                 else
                   nstate <= state_fetch;
                 end if;

        when state_while_start_2 =>
                if cnt_reg = "00000000" then
                  nstate <= state_fetch;
                else
                  DATA_EN <= '1';
                  DATA_RDWR <= '0';
                  mx1_data_addr_sel <= "0";
                  nstate <= state_while_start_3;
                end if ;
        
        when state_while_start_3 =>
                if DATA_RDATA = X"5B" then
                  cnt_inc <= '1';
                elsif DATA_RDATA = X"5D" then
                  cnt_dec <= '1';
                end if;
                pc_inc <= '1';
                nstate <= state_while_start_2;
                
         -------------------------------------------------------------------
         -- END OF WHILE } --> ']'
         when state_while_end_0 =>
                 DATA_EN <= '1';
                 DATA_RDWR <= '0';
                 mx1_data_addr_sel <= "1"; 
                 mx2_data_addr_sel <= "0";
                 nstate <= state_while_end_1;
                
         when state_while_end_1 =>
                 if DATA_RDATA = "00000000" then
                   pc_inc <= '1';
                   nstate <= state_fetch;
                 else
                   cnt_inc <= '1';
                   pc_dec <= '1';
                   nstate <= state_while_end_2;
                 end if;
      
         when state_while_end_2 =>
                if cnt_reg = "00000000" then
                  nstate <= state_fetch;
                else
                 DATA_EN <= '1';
                 DATA_RDWR <= '0';
                 mx1_data_addr_sel <= "0";
                 nstate <= state_while_end_3;
                end if;

       when state_while_end_3 =>
                if DATA_RDATA = X"5B" then
                  cnt_dec <= '1';
                elsif DATA_RDATA = X"5D" then
                  cnt_inc <= '1';
                end if;
                nstate <= state_while_end_4;
              
      when state_while_end_4 =>
                if cnt_reg = "00000000" then
                  pc_inc <= '1';
                else
                  pc_dec <= '1';
                end if;
                nstate <= state_while_end_2;

        -------------------------------------------------------------------
        -- RETURN --> null
        when state_stop => nstate <= state_stop;
        -------------------------------------------------------------------
        -- OTHERS
        when state_ignore => 
                pc_inc <= '1';
                nstate <= state_fetch; 
        -------------------------------------------------------------------
        -- UNDEFINED
        when others => null;
      
      end case;
      
  end process;
 
end behavioral;