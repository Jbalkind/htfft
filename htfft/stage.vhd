library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.htfft_pkg.all;
use work.htfft{{suffix}}_pipeline.all;

entity stage_{{n}}{{suffix}} is
  port (
    clk: in std_logic;
    -- The reset is just to get the addresses in sync with the
    -- data flow.  If it arrives on the clock cycle immediately
    -- before a new vector starts it will have no effect since
    -- the addresses would be getting initialized anyway.
    i_reset: in std_logic;
    i_data_a: in std_logic_vector({{width}}*{{size}}/2-1 downto 0);
    i_data_b: in std_logic_vector({{width}}*{{size}}/2-1 downto 0);
    o_reset: out std_logic;
    o_data_a: out std_logic_vector(({{width}}+2)*{{size}}/2-1 downto 0);
    o_data_b: out std_logic_vector(({{width}}+2)*{{size}}/2-1 downto 0)
  );
end entity;

architecture arch of stage_{{n}}{{suffix}} is
  constant N: positive := {{n}};
  constant WIDTH: positive := {{width}};
  constant SIZE: positive := {{size}};
  constant OUTPUT_WIDTH: positive := WIDTH + 2;
  constant L: positive := N/SIZE;

  function ADDRESS_CLASH return string is
  begin
    if L=2 then
      return "NEW";
    else
      return "UNDEFINED";
    end if;
  end function;

  signal write_valid_a: std_logic;
  signal write_valid_b: std_logic;
  signal write_index: unsigned(logceil(L)-1 downto 0);
  signal write_address: unsigned(logceil(L/2)-1 downto 0);
  signal write_data_a: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal write_data_b: std_logic_vector(SIZE*WIDTH/2-1 downto 0);

  signal read_index: unsigned(logceil(L)-1 downto 0);

  signal toread_valid_a: std_logic;
  signal toread_valid_b: std_logic;
  signal toread_address: unsigned(logceil(L/2)-1 downto 0);

  subtype t_twiddle is std_logic_vector(WIDTH-1 downto 0);
  type array_of_twiddles is array(natural range <>) of t_twiddle;
  signal fromread_data_a: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal fromread_data_b: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal fromread_twiddles: array_of_twiddles(SIZE/2-1 downto 0);
  signal fromread_swap: std_logic;

  signal buffered_data_a: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal buffered_data_b: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal buffered_twiddles: array_of_twiddles(SIZE/2-1 downto 0);
  signal buffered_swap: std_logic;
  signal buffered_newdata_a: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal buffered_switchdata_a: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal buffered_switchdata_b: std_logic_vector(SIZE*WIDTH/2-1 downto 0);

  signal tobutterfly_twiddles: array_of_twiddles(SIZE/2-1 downto 0);
  signal tobutterfly_swap: std_logic;
  signal tobutterfly_data_a: std_logic_vector(SIZE*WIDTH/2-1 downto 0);
  signal tobutterfly_data_b: std_logic_vector(SIZE*WIDTH/2-1 downto 0);

  subtype t_batch_of_twiddles is array_of_twiddles(SIZE/2-1 downto 0);
  type array_of_batches_of_twiddles is array(natural range <>) of t_batch_of_twiddles;

  subtype t_data is std_logic_vector(WIDTH-1 downto 0);
  type array_of_data is array(natural range <>) of t_data;
  signal tobutterfly_dataarray_a: array_of_data(SIZE/2-1 downto 0);
  signal tobutterfly_dataarray_b: array_of_data(SIZE/2-1 downto 0);

  subtype t_odata is std_logic_vector(WIDTH+2-1 downto 0);
  type array_of_odata is array(natural range <>) of t_odata;
  signal o_dataarray_a: array_of_odata(SIZE/2-1 downto 0);
  signal o_dataarray_b: array_of_odata(SIZE/2-1 downto 0);

  constant LOCAL_TWIDDLES: array_of_batches_of_twiddles(N/SIZE-1 downto 0) := ({% for twiddle_batch in twiddle_batches %}
    {{loop.index0}} => ({% for twiddle in twiddle_batch %}
       {{loop.index0}} => "{{twiddle}}"{% if not loop.last %},{% endif %}{% endfor %}
       ){% if not loop.last %},{% endif %}{% endfor %}
  );


  signal i_reset_slv: std_logic_vector(0 downto 0);
  signal o_reset_slv: std_logic_vector(0 downto 0);

begin

  process(clk)
  begin
    if rising_edge(clk) then
      -- We could probably get away with one counter
      -- rather than two here, but I think it's easier
      -- to understand with two.
      if read_index = L-1 then
        read_index <= (others => '0');
      else
        read_index <= read_index + 1;
      end if;
      if write_index = L-1 then
        write_index <= (others => '0');
      else
        write_index <= write_index + 1;
      end if;
      if i_reset = '1' then
        write_index <= (others => '0');
        read_index <= to_unsigned(L/2+1, logceil(L));
      end if;
    end if;
  end process;

  write_valid_a <= '1';
  write_valid_b <= not write_index(logceil(L)-1);
  write_address <= write_index(logceil(L)-1-1 downto 0);

  toread_valid_a <= '1';
  toread_valid_b <= read_index(logceil(L)-1);
  toread_address <= read_index(logceil(L)-1-1 downto 0);

  write_data_a <= i_data_a when write_index(logceil(L)-1) = '0' else
                  i_data_b;
  write_data_b <= i_data_b;

  memory_a: entity work.htfft_memory
    generic map (
      WIDTH => SIZE*WIDTH/2,
      DEPTH => L/2,
      ADDRESS_CLASH => ADDRESS_CLASH
      )
    port map (
      clk => clk,
      write_valid => write_valid_a,
      write_address => write_address,
      write_data => write_data_a,
      toread_valid => toread_valid_a,
      toread_address => toread_address,
      fromread_data => fromread_data_a
      );

  memory_b: entity work.htfft_memory
    generic map (
      WIDTH => SIZE*WIDTH/2,
      DEPTH => L/2,
      ADDRESS_CLASH => ADDRESS_CLASH
      )
    port map (
      clk => clk,
      -- read_valid_b is just used to bring the power down when
      -- we're not reading from this memory.
      -- It's not necessary for correctness. 
      write_valid => write_valid_b,
      write_address => write_address,
      write_data => write_data_b,
      toread_valid => toread_valid_b,
      toread_address => toread_address,
      fromread_data => fromread_data_b
      );

  process(clk)
  begin
    if rising_edge(clk) then
      fromread_twiddles <= LOCAL_TWIDDLES(to_integer(read_index));
      fromread_swap <= read_index(logceil(L)-1);
    end if;
  end process;

  yes_fromread_buffered: if STAGE_REG_FROMREAD_BUFFERED generate
    process(clk)
    begin
      if rising_edge(clk) then
        buffered_data_a <= fromread_data_a;
        buffered_data_b <= fromread_data_b;
        buffered_twiddles <= fromread_twiddles;
        buffered_swap <= fromread_swap;
        buffered_newdata_a <= i_data_a;
      end if;
    end process;
  end generate;
  no_fromread_buffered: if not STAGE_REG_FROMREAD_BUFFERED generate
    buffered_data_a <= fromread_data_a;
    buffered_data_b <= fromread_data_b;
    buffered_twiddles <= fromread_twiddles;
    buffered_swap <= fromread_swap;
    buffered_newdata_a <= i_data_a;
  end generate;

  buffered_switchdata_a <= buffered_data_a when buffered_swap = '0' else
                           buffered_data_b;
  buffered_switchdata_b <= buffered_newdata_a when buffered_swap = '0' else
                           buffered_data_a;

  yes_buffered_tobutterfly: if STAGE_REG_BUFFERED_TOBUTTERFLY generate
    process(clk)
    begin
      if rising_edge(clk) then
        tobutterfly_data_a <= buffered_switchdata_a;
        tobutterfly_data_b <= buffered_switchdata_b;
        tobutterfly_twiddles <= buffered_twiddles;
      end if;
    end process;
  end generate;
  no_buffered_tobutterfly: if not STAGE_REG_BUFFERED_TOBUTTERFLY generate
    tobutterfly_data_a <= buffered_switchdata_a;
    tobutterfly_data_b <= buffered_switchdata_b;
    tobutterfly_twiddles <= buffered_twiddles;
  end generate;

  loop_butterflys: for bf_index in 0 to SIZE/2-1 generate
    tobutterfly_dataarray_a(bf_index) <= tobutterfly_data_a((bf_index+1)*WIDTH-1 downto bf_index*WIDTH);
    tobutterfly_dataarray_b(bf_index) <= tobutterfly_data_b((bf_index+1)*WIDTH-1 downto bf_index*WIDTH);
    bf: entity work.butterfly
      generic map (
        WIDTH => WIDTH,
        TWIDDLE_WIDTH => WIDTH,
        MULT_LATENCY => MULT_LATENCY,
        REG_I_P => BUTTERFLY_I_P,
        REG_Q_R => BUTTERFLY_Q_R,
        REG_R_S => BUTTERFLY_R_S,
        REG_S_O => BUTTERFLY_S_O
      )
      port map (
        clk => clk,
        i_a => tobutterfly_dataarray_a(bf_index),
        i_b => tobutterfly_dataarray_b(bf_index),
        i_t => tobutterfly_twiddles(bf_index),
        o_c => o_dataarray_a(bf_index),
        o_d => o_dataarray_b(bf_index)
        );
    o_data_a((bf_index+1)*OUTPUT_WIDTH-1 downto bf_index*OUTPUT_WIDTH) <=
      std_logic_vector(o_dataarray_a(bf_index));
    o_data_b((bf_index+1)*OUTPUT_WIDTH-1 downto bf_index*OUTPUT_WIDTH) <=
      std_logic_vector(o_dataarray_b(bf_index));
  end generate;

  i_reset_slv(0) <= i_reset;
  sr: entity work.shift_register
    generic map (
      WIDTH => 1,
      LENGTH => BUTTERFLY_LATENCY + L/2 + boolean_to_int(STAGE_REG_FROMREAD_BUFFERED) + boolean_to_int(STAGE_REG_BUFFERED_TOBUTTERFLY)
      )
    port map (
      clk => clk,
      i_data => i_reset_slv,
      o_data => o_reset_slv
      );
  o_reset <= o_reset_slv(0);
  
end architecture;
