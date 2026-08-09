--------------------------------------------------------------------------
-- fp_adder_demo_tb.vhd
--
-- Protocolo exercitado:
--     SW(9 downto 8) = campo, SW(6 downto 0) = dado, KEY0 = carrega
--     SW(7) = vista ('0' operando, '1' resultado)
--     KEY1  = reinicia os dois operandos em +1,0
--
-- O resultado e lido dos displays:
--     HEX2       -> expoente
--     HEX1:HEX0  -> fracao
--     HEX3       -> "-" quando negativo, apagado quando positivo
--     HEX5       -> "C" quando o expoente estourou
--------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity fp_adder_demo_tb is
end fp_adder_demo_tb;


architecture sim of fp_adder_demo_tb is

    constant CLK_PERIOD : time := 20 ns;

    constant SSEG_APAGADO : std_logic_vector(7 downto 0) := "11111111";
    constant SSEG_MENOS   : std_logic_vector(7 downto 0) := "10111111";
    constant SSEG_C       : std_logic_vector(7 downto 0) := "10100111";

    signal MAX10_CLK1_50 : std_logic := '0';
    signal KEY  : std_logic_vector(1 downto 0) := (others => '1');
    signal SW   : std_logic_vector(9 downto 0) := (others => '0');
    signal LEDR : std_logic_vector(9 downto 0);
    signal HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : std_logic_vector(7 downto 0);

    signal sim_done : boolean := false;

    signal HEX0_d, HEX1_d, HEX2_d, HEX3_d, HEX4_d, HEX5_d
                                        : std_logic_vector(6 downto 0);
    signal DP0, DP1, DP2, DP3, DP4, DP5 : std_logic;

    -- valores em decimal, aparecem direto no Wave do Questa
    signal val_op1      : real := 0.0;
    signal val_op2      : real := 0.0;
    signal val_esperado : real := 0.0;
    signal val_placa    : real := 0.0;
    signal val_erro     : real := 0.0;

    ----------------------------------------------------------------------
    -- decodificador reverso dos sete segmentos
    ----------------------------------------------------------------------
    function sseg_to_nib (s : std_logic_vector(6 downto 0)) return integer is
    begin
        case s is
            when "1000000" => return  0;
            when "1111001" => return  1;
            when "0100100" => return  2;
            when "0110000" => return  3;
            when "0011001" => return  4;
            when "0010010" => return  5;
            when "0000010" => return  6;
            when "1111000" => return  7;
            when "0000000" => return  8;
            when "0010000" => return  9;
            when "0001000" => return 10;
            when "0000011" => return 11;
            when "0100111" => return 12;
            when "0100001" => return 13;
            when "0000110" => return 14;
            when "0001110" => return 15;
            when others    => return -1;
        end case;
    end function;

    function nib_char (n : integer) return character is
        constant HEXCHR : string(1 to 16) := "0123456789ABCDEF";
    begin
        if n < 0 or n > 15 then
            return '?';
        end if;
        return HEXCHR(n + 1);
    end function;

    ----------------------------------------------------------------------
    -- a fracao guardada e sempre '1' & SW(6 downto 0)
    ----------------------------------------------------------------------
    function frac_efetiva (f : integer) return integer is
    begin
        return 128 + (f mod 128);
    end function;

    function fp_val (sgn : std_logic; e : integer; f : integer) return real is
        variable v : real;
    begin
        v := real(f) / 256.0 * (2.0 ** e);
        if sgn = '1' then
            v := -v;
        end if;
        return v;
    end function;

    ----------------------------------------------------------------------
    -- leitura dos displays
    ----------------------------------------------------------------------
    impure function ver_exp return integer is
    begin
        return sseg_to_nib(HEX2(6 downto 0));
    end function;

    impure function ver_frac return integer is
        variable hi, lo : integer;
    begin
        hi := sseg_to_nib(HEX1(6 downto 0));
        lo := sseg_to_nib(HEX0(6 downto 0));
        if hi < 0 or lo < 0 then
            return -1;
        end if;
        return hi * 16 + lo;
    end function;

    impure function ver_negativo return boolean is
    begin
        return HEX3 = SSEG_MENOS;
    end function;

    impure function ver_carry return boolean is
    begin
        return HEX5 = SSEG_C;
    end function;

    ----------------------------------------------------------------------
    -- valor mostrado, ja levando o "C" em conta:
    -- carry aceso significa somar 16 ao expoente exibido
    ----------------------------------------------------------------------
    impure function ver_value return real is
        variable e : integer;
        variable s : std_logic;
    begin
        if ver_exp < 0 or ver_frac < 0 then
            return 0.0;
        end if;
        e := ver_exp;
        if ver_carry then
            e := e + 16;
        end if;
        if ver_negativo then
            s := '1';
        else
            s := '0';
        end if;
        return fp_val(s, e, ver_frac);
    end function;

    ----------------------------------------------------------------------
    -- foto dos seis displays
    ----------------------------------------------------------------------
    procedure show_board is
        variable L : line;

        procedure put (seg : std_logic_vector(7 downto 0)) is
        begin
            if seg = SSEG_APAGADO then
                write(L, '_');
            elsif seg = SSEG_MENOS then
                write(L, character'('-'));
            else
                write(L, nib_char(sseg_to_nib(seg(6 downto 0))));
            end if;
            if seg(7) = '0' then
                write(L, '.');
            else
                write(L, ' ');
            end if;
            write(L, ' ');
        end procedure;
    begin
        write(L, string'("   HEX5..HEX0 :  "));
        put(HEX5); put(HEX4); put(HEX3); put(HEX2); put(HEX1); put(HEX0);
        writeline(output, L);
    end procedure;

begin

    dut : entity work.fp_adder_demo
        port map (
            MAX10_CLK1_50 => MAX10_CLK1_50,
            KEY  => KEY,
            SW   => SW,
            LEDR => LEDR,
            HEX0 => HEX0, HEX1 => HEX1, HEX2 => HEX2,
            HEX3 => HEX3, HEX4 => HEX4, HEX5 => HEX5
        );

    HEX0_d <= HEX0(6 downto 0);   DP0 <= not HEX0(7);
    HEX1_d <= HEX1(6 downto 0);   DP1 <= not HEX1(7);
    HEX2_d <= HEX2(6 downto 0);   DP2 <= not HEX2(7);
    HEX3_d <= HEX3(6 downto 0);   DP3 <= not HEX3(7);
    HEX4_d <= HEX4(6 downto 0);   DP4 <= not HEX4(7);
    HEX5_d <= HEX5(6 downto 0);   DP5 <= not HEX5(7);

    calc_real : process(HEX0, HEX1, HEX2, HEX3, HEX5, val_esperado)
    begin
        val_placa <= ver_value;
        val_erro  <= abs(ver_value - val_esperado);
    end process;

    clk_gen : process
    begin
        while not sim_done loop
            MAX10_CLK1_50 <= '0';
            wait for CLK_PERIOD / 2;
            MAX10_CLK1_50 <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;


    stim : process

        variable errors : natural := 0;
        variable L      : line;

        ------------------------------------------------------------------
        -- carrega um campo. SW(7) fica preservado: e a vista, nao dado.
        ------------------------------------------------------------------
        procedure load_field (campo : integer; dado : integer) is
        begin
            SW(9 downto 8) <= std_logic_vector(to_unsigned(campo, 2));
            SW(6 downto 0) <= std_logic_vector(to_unsigned(dado mod 128, 7));
            wait until rising_edge(MAX10_CLK1_50);

            KEY(0) <= '0';
            wait for 3 * CLK_PERIOD;

            KEY(0) <= '1';
            wait for 2 * CLK_PERIOD;
        end procedure;

        procedure load_op (op : integer; sgn : std_logic;
                           e : integer; f : integer) is
            variable cabecalho : integer;
        begin
            cabecalho := (e mod 16);
            if sgn = '1' then
                cabecalho := cabecalho + 16;
            end if;

            load_field(2 * (op - 1),     cabecalho);
            load_field(2 * (op - 1) + 1, f);
        end procedure;

        procedure press_reset is
        begin
            wait until rising_edge(MAX10_CLK1_50);
            KEY(1) <= '0';
            wait for 3 * CLK_PERIOD;
            KEY(1) <= '1';
            wait for 2 * CLK_PERIOD;
        end procedure;

        ------------------------------------------------------------------
        -- vista: '0' operando (SW(9) escolhe qual), '1' resultado
        ------------------------------------------------------------------
        procedure ver_resultado is
        begin
            SW(7) <= '1';
            wait for 2 * CLK_PERIOD;
        end procedure;

        procedure ver_operando (op : integer) is
        begin
            SW(7) <= '0';
            if op = 1 then
                SW(9) <= '0';
            else
                SW(9) <= '1';
            end if;
            wait for 2 * CLK_PERIOD;
        end procedure;

        ------------------------------------------------------------------
        -- verificacao
        ------------------------------------------------------------------
        procedure verifica (expect : real; espera_carry : boolean) is
            variable got, tol, err : real;
            variable ok : boolean;
            variable e_real : integer;
        begin
            got := ver_value;

            e_real := ver_exp;
            if ver_carry then
                e_real := e_real + 16;
            end if;

            write(L, string'("   esperado (real)             "));
            write(L, expect, right, 16, 6);
            writeline(output, L);

            show_board;

            write(L, string'("   lido do display : "));
            if ver_negativo then
                write(L, character'('-'));
            else
                write(L, character'('+'));
            end if;
            write(L, string'(" exp="));    write(L, e_real);
            if ver_carry then
                write(L, string'(" (C aceso: "));
                write(L, ver_exp);
                write(L, string'("+16)"));
            end if;
            write(L, string'(" frac=0x")); write(L, nib_char(ver_frac / 16));
            write(L, nib_char(ver_frac mod 16));
            write(L, string'("  ->"));     write(L, got, right, 16, 6);
            writeline(output, L);

            if ver_carry /= espera_carry then
                write(L, string'("   [ FALHOU ] carry no display nao bate com o esperado"));
                writeline(output, L);
                errors := errors + 1;
                write(L, string'("")); writeline(output, L);
                return;
            end if;

            if abs(expect) < 0.5 then
                ok := (ver_frac = 0);
                write(L, string'("   (abaixo do minimo normalizavel: espera-se zero)"));
                writeline(output, L);
            else
                tol := (2.0 ** e_real) / 256.0 * 2.0;
                err := abs(got - expect);
                ok  := (err <= tol);
                write(L, string'("   erro ="));
                write(L, err, right, 14, 6);
                write(L, string'("   tolerancia (2 ULP) ="));
                write(L, tol, right, 14, 6);
                writeline(output, L);
            end if;

            if ok then
                write(L, string'("   [ OK ]"));
            else
                write(L, string'("   [ FALHOU ]"));
                errors := errors + 1;
            end if;
            writeline(output, L);
            write(L, string'(""));
            writeline(output, L);
        end procedure;

        ------------------------------------------------------------------
        procedure do_test (tname : string;
                           s1 : std_logic; e1 : integer; f1 : integer;
                           s2 : std_logic; e2 : integer; f2 : integer;
                           espera_carry : boolean := false) is
            variable ef1, ef2 : integer;
            variable va, vb   : real;
        begin
            ef1 := frac_efetiva(f1);
            ef2 := frac_efetiva(f2);

            load_op(1, s1, e1, f1);
            load_op(2, s2, e2, f2);

            va := fp_val(s1, e1, ef1);
            vb := fp_val(s2, e2, ef2);

            val_op1      <= va;
            val_op2      <= vb;
            val_esperado <= va + vb;
            wait for 0 ns;

            write(L, string'("====================================================================="));
            writeline(output, L);
            write(L, string'(" ") & tname);
            writeline(output, L);
            write(L, string'("---------------------------------------------------------------------"));
            writeline(output, L);

            -- confere as duas vistas de operando antes de olhar o resultado
            ver_operando(1);
            if ver_exp /= (e1 mod 16) or ver_frac /= ef1
               or (ver_negativo /= (s1 = '1')) then
                write(L, string'("   [ FALHOU ] vista do operando 1 nao bate"));
                writeline(output, L);
                errors := errors + 1;
            end if;

            ver_operando(2);
            if ver_exp /= (e2 mod 16) or ver_frac /= ef2
               or (ver_negativo /= (s2 = '1')) then
                write(L, string'("   [ FALHOU ] vista do operando 2 nao bate"));
                writeline(output, L);
                errors := errors + 1;
            end if;

            write(L, string'("   op1 = "));
            if s1 = '1' then write(L, character'('-')); else write(L, character'('+')); end if;
            write(L, string'("  exp="));    write(L, e1);
            write(L, string'("  frac=0x")); write(L, nib_char(ef1 / 16));
            write(L, nib_char(ef1 mod 16));
            write(L, string'("   ->"));     write(L, va, right, 16, 6);
            writeline(output, L);

            write(L, string'("   op2 = "));
            if s2 = '1' then write(L, character'('-')); else write(L, character'('+')); end if;
            write(L, string'("  exp="));    write(L, e2);
            write(L, string'("  frac=0x")); write(L, nib_char(ef2 / 16));
            write(L, nib_char(ef2 mod 16));
            write(L, string'("   ->"));     write(L, vb, right, 16, 6);
            writeline(output, L);

            ver_resultado;
            verifica(va + vb, espera_carry);
        end procedure;

    begin
        write(L, string'(""));
        writeline(output, L);
        write(L, string'("#####################################################################"));
        writeline(output, L);
        write(L, string'("  fp_adder_demo -- vista comutada por SW(7)"));
        writeline(output, L);
        write(L, string'("  HEX5=C(estouro)  HEX4=apagado  HEX3=sinal  HEX2=exp.  HEX1:HEX0=frac"));
        writeline(output, L);
        write(L, string'("  fracao sempre normalizada: frac = '1' & SW(6 downto 0)"));
        writeline(output, L);
        write(L, string'("#####################################################################"));
        writeline(output, L);
        write(L, string'(""));
        writeline(output, L);

        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- Table 1 do livro, traduzida mantendo o expoente e escolhendo a
        -- fracao normalizada mais proxima:
        --     0.54 -> 0x8A    0.87 -> 0xDF    0.55 -> 0x8D
        --     0.56 -> 0x8F    0.52 -> 0x85
        ------------------------------------------------------------------

        do_test("EG1 : +0.54E3 + (-0.87E4)   alinha 1 casa, subtrai, fica em E4",
                '0', 3, 16#8A#,
                '1', 4, 16#DF#);

        do_test("EG2 : +0.54E3 + (-0.55E3)   cancelamento: precisa de 6 bits, so ha 3 de expoente",
                '0', 3, 16#8A#,
                '1', 3, 16#8D#);

        do_test("EG3 : +0.54E0 + (-0.55E0)   expoente no minimo, vira zero negativo",
                '0', 0, 16#8A#,
                '1', 0, 16#8D#);

        do_test("EG4 : +0.56E3 + (+0.52E3)   vai-um, expoente sobe para E4",
                '0', 3, 16#8F#,
                '0', 3, 16#85#);

        ------------------------------------------------------------------
        -- Casos complementares: cobrem os ramos que a Table 1 nao alcanca
        ------------------------------------------------------------------

        -- caso II da normalizacao: mesmo par do EG2, agora com expoente
        -- sobrando. leado = 6 e expb = 6, entao o deslocamento a esquerda
        -- e pago e o resultado sai exato em -0,75
        do_test("T5  : +0.54E6 + (-0.55E6)   expoente suficiente: renormaliza para -0,75",
                '0', 6, 16#8A#,
                '1', 6, 16#8D#);

        -- potencias de dois, so possiveis porque apenas o bit 7 e forcado
        do_test("T6  : 1,0 + 0,5             potencias de dois, resultado exato 1,5",
                '0', 1, 16#80#,
                '0', 0, 16#80#);

        -- ordenacao inversa: aqui o operando 1 e o maior, e o sinal dele
        -- e que prevalece na saida
        do_test("T7  : -24 + 4               operando 1 e o maior, subtrai e mantem o sinal",
                '1', 5, 16#C0#,
                '0', 3, 16#80#);

        -- exp_diff = 15: o alinhamento desloca alem dos 8 bits e a fracao
        -- do operando pequeno e inteiramente descartada
        do_test("T8  : 16384 + 0,996         exp_diff=15, o operando pequeno e absorvido",
                '0', 15, 16#80#,
                '0',  0, 16#FF#);

        -- cancelamento total com expb >= 7: leado = 7 nao supera expb, o
        -- ramo geral assume e devolve zero com expoente 5 (zero nao
        -- canonico, limitacao conhecida do somador)
        do_test("T9  : a + (-a) com exp=12   cancelamento total: zero com expoente 5",
                '0', 12, 16#C0#,
                '1', 12, 16#C0#);

        -- unico caso em que o expoente verdadeiro nao cabe em 4 bits:
        -- expn = 15 + 1 da a volta para 0 e o HEX5 acende o C
        do_test("T10 : 32640 + 32640         ESTOURO do expoente, HEX5 mostra C",
                '0', 15, 16#FF#,
                '0', 15, 16#FF#,
                true);

        ------------------------------------------------------------------
        press_reset;
        ver_resultado;

        write(L, string'("====================================================================="));
        writeline(output, L);
        write(L, string'(" T11 : KEY1 reinicia os dois operandos em +1,0"));
        writeline(output, L);
        write(L, string'("---------------------------------------------------------------------"));
        writeline(output, L);
        val_esperado <= 2.0;
        wait for 0 ns;
        verifica(2.0, false);

        ------------------------------------------------------------------
        write(L, string'("#####################################################################"));
        writeline(output, L);
        if errors = 0 then
            write(L, string'("  RESULTADO: todos os testes passaram."));
        else
            write(L, string'("  RESULTADO: "));
            write(L, errors);
            write(L, string'(" teste(s) falharam."));
        end if;
        writeline(output, L);
        write(L, string'("#####################################################################"));
        writeline(output, L);

        sim_done <= true;
        wait;
    end process;

end sim;
