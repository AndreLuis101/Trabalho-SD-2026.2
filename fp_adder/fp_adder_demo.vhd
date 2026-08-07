library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


------------------------------------------------------------------------
-- fp_adder_demo  --  DE10-Lite
--
-- ENTRADA
--
--     SW(9 downto 8) = campo        SW(6 downto 0) = dado
--
--        "00"  ->  sinal e expoente do operando 1
--        "01"  ->  fracao do operando 1
--        "10"  ->  sinal e expoente do operando 2
--        "11"  ->  fracao do operando 2
--
--     Nos campos de sinal/expoente:  SW(4) = sinal,  SW(3 downto 0) = exp
--     Nos campos de fracao:          frac = '1' & SW(6 downto 0)
--
--     A fracao e SEMPRE normalizada: o bit 7 nao e ajustavel, e nao
--     existe mais como digitar um operando fora do formato.
--
--     KEY0 = carrega o campo selecionado
--     KEY1 = reinicia os dois operandos em +1,0  (autoteste: mostra 2,0)
--
--
-- VISTA
--
--     SW(7) = '0'  ->  mostra o OPERANDO apontado por SW(9)
--     SW(7) = '1'  ->  mostra o RESULTADO
--
--
-- DISPLAYS
--
--     HEX5   "C" quando o expoente do resultado estourou
--     HEX4   apagado (separador visual)
--     HEX3   "-" quando o numero mostrado e negativo
--     HEX2   expoente, com o ponto decimal SEMPRE aceso
--     HEX1   fracao, nibble alto
--     HEX0   fracao, nibble baixo
--
--     O ponto aceso em HEX2 marca a fronteira entre expoente e fracao:
--
--          C _ -  2.  F  F      ->  -(0xFF/256) * 2^(2+16)
--          _ _ _  5.  8  0      ->   (0x80/256) * 2^5
--
--
-- SOBRE O "C" DO HEX5
--
--     Ele NAO mostra sum(8), o vai-um da soma de 9 bits. Aquele bit
--     acende em quase toda soma de sinais iguais -- e situacao normal,
--     nao merece aviso.
--
--     O "C" aqui marca o estouro do EXPOENTE: o expoente verdadeiro
--     seria 16, que nao cabe nos 4 bits do campo e da a volta para 0.
--     Ou seja, com o "C" aceso, o expoente correto e o que aparece
--     em HEX2 MAIS 16. O display continua legivel em vez de virar
--     apenas um alarme.
------------------------------------------------------------------------

entity fp_adder_demo is
    port(
        MAX10_CLK1_50 : in std_logic;

        KEY : in std_logic_vector(1 downto 0);
        SW  : in std_logic_vector(9 downto 0);

        LEDR : out std_logic_vector(9 downto 0);

        HEX0 : out std_logic_vector(7 downto 0);
        HEX1 : out std_logic_vector(7 downto 0);
        HEX2 : out std_logic_vector(7 downto 0);
        HEX3 : out std_logic_vector(7 downto 0);
        HEX4 : out std_logic_vector(7 downto 0);
        HEX5 : out std_logic_vector(7 downto 0)
    );
end fp_adder_demo;


architecture arch of fp_adder_demo is


    --------------------------------------------------------------------
    -- padroes de segmento montados a mao
    --
    -- O hex_to_sseg so sabe gerar 0 a F. Traco e apagado nao estao na
    -- tabela dele, e isso e uma vantagem: nenhum resultado legitimo
    -- consegue imitar esses dois padroes.
    --
    --                                       dp gfedcba
    --------------------------------------------------------------------

    constant SSEG_APAGADO : std_logic_vector(7 downto 0) := "1" & "1111111";
    constant SSEG_MENOS   : std_logic_vector(7 downto 0) := "1" & "0111111";
    constant SSEG_C       : std_logic_vector(7 downto 0) := "1" & "0100111";


    -- valor de reinicio: +1,0  =  (0x80 / 256) * 2^1

    constant EXP_UM  : std_logic_vector(3 downto 0) := "0001";
    constant FRAC_UM : std_logic_vector(7 downto 0) := "10000000";


    -- operandos armazenados

    signal sign1_reg : std_logic                    := '0';
    signal exp1_reg  : std_logic_vector(3 downto 0) := EXP_UM;
    signal frac1_reg : std_logic_vector(7 downto 0) := FRAC_UM;

    signal sign2_reg : std_logic                    := '0';
    signal exp2_reg  : std_logic_vector(3 downto 0) := EXP_UM;
    signal frac2_reg : std_logic_vector(7 downto 0) := FRAC_UM;


    -- fracao vinda das chaves, sempre normalizada

    signal frac_in : std_logic_vector(7 downto 0);


    -- saida do adder

    signal sign_out : std_logic;
    signal exp_out  : std_logic_vector(3 downto 0);
    signal frac_out : std_logic_vector(7 downto 0);

    signal ovf : std_logic;


    -- operando apontado por SW(9)

    signal op_sign : std_logic;
    signal op_exp  : std_logic_vector(3 downto 0);
    signal op_frac : std_logic_vector(7 downto 0);


    -- o que vai para os displays

    signal ver_sign : std_logic;
    signal ver_exp  : std_logic_vector(3 downto 0);
    signal ver_frac : std_logic_vector(7 downto 0);


begin


    ------------------------------------------------------------------
    -- Fracao das chaves: bit escondido garantido em '1'
    ------------------------------------------------------------------

    frac_in <= '1' & SW(6 downto 0);


    ------------------------------------------------------------------
    -- Captura dos campos
    ------------------------------------------------------------------

    process(MAX10_CLK1_50)
    begin

        if rising_edge(MAX10_CLK1_50) then


            -- KEY0: carrega o campo apontado por SW(9 downto 8)

            if KEY(0) = '0' then

                case SW(9 downto 8) is

                    when "00" =>
                        sign1_reg <= SW(4);
                        exp1_reg  <= SW(3 downto 0);

                    when "01" =>
                        frac1_reg <= frac_in;

                    when "10" =>
                        sign2_reg <= SW(4);
                        exp2_reg  <= SW(3 downto 0);

                    when others =>
                        frac2_reg <= frac_in;

                end case;

            end if;


            -- KEY1: reinicia os dois operandos em +1,0

            if KEY(1) = '0' then

                sign1_reg <= '0';
                exp1_reg  <= EXP_UM;
                frac1_reg <= FRAC_UM;

                sign2_reg <= '0';
                exp2_reg  <= EXP_UM;
                frac2_reg <= FRAC_UM;

            end if;


        end if;

    end process;


    ------------------------------------------------------------------
    -- Somador FP
    ------------------------------------------------------------------

    fp_add : entity work.fp_adder

        port map(

            sign1 => sign1_reg,
            sign2 => sign2_reg,

            exp1 => exp1_reg,
            exp2 => exp2_reg,

            frac1 => frac1_reg,
            frac2 => frac2_reg,

            sign_out => sign_out,
            exp_out  => exp_out,
            frac_out => frac_out

        );


    ------------------------------------------------------------------
    -- Estouro do expoente, deduzido de fora do somador
    --
    -- Com sinais iguais nao ha subtracao, entao exp_out so pode valer
    -- expb ou expb+1. Se expb = 15, o incremento da a volta e exp_out
    -- sai 0 -- resultado impossivel por qualquer outro caminho quando
    -- expb = 15, porque o ramo de normalizacao faz expb - leado, que
    -- com leado no maximo 7 nunca desce abaixo de 8.
    --
    -- expb = 15 equivale a algum dos dois expoentes ser 15, ja que a
    -- chave de ordenacao coloca o maior expoente em expb.
    ------------------------------------------------------------------

    ovf <= '1' when sign1_reg = sign2_reg
                    and (exp1_reg = "1111" or exp2_reg = "1111")
                    and exp_out = "0000"
           else '0';


    ------------------------------------------------------------------
    -- Vista: SW(9) escolhe o operando, SW(7) escolhe operando/resultado
    ------------------------------------------------------------------

    op_sign <= sign1_reg when SW(9) = '0' else sign2_reg;
    op_exp  <= exp1_reg  when SW(9) = '0' else exp2_reg;
    op_frac <= frac1_reg when SW(9) = '0' else frac2_reg;

    ver_sign <= sign_out when SW(7) = '1' else op_sign;
    ver_exp  <= exp_out  when SW(7) = '1' else op_exp;
    ver_frac <= frac_out when SW(7) = '1' else op_frac;


    ------------------------------------------------------------------
    -- LEDs
    ------------------------------------------------------------------

    LEDR(6 downto 0) <= SW(6 downto 0);   -- eco do dado nas chaves

    LEDR(7) <= SW(7);                     -- vista: aceso = resultado

    LEDR(8) <= ovf;                       -- estouro (mesmo na vista do operando)

    LEDR(9) <= sign_out;                  -- sinal do resultado


    ------------------------------------------------------------------
    -- Displays montados a mao
    ------------------------------------------------------------------

    -- so acende na vista do resultado: operando nenhum tem carry
    HEX5 <= SSEG_C when (SW(7) = '1' and ovf = '1') else SSEG_APAGADO;

    HEX4 <= SSEG_APAGADO;

    HEX3 <= SSEG_MENOS when ver_sign = '1' else SSEG_APAGADO;


    ------------------------------------------------------------------
    -- Displays decodificados
    ------------------------------------------------------------------

    HEX2_UNIT : entity work.hex_to_sseg
        port map(
            hex  => ver_exp,
            dp   => '1',            -- sempre aceso: separa expoente de fracao
            sseg => HEX2
        );

    HEX1_UNIT : entity work.hex_to_sseg
        port map(
            hex  => ver_frac(7 downto 4),
            dp   => '0',
            sseg => HEX1
        );

    HEX0_UNIT : entity work.hex_to_sseg
        port map(
            hex  => ver_frac(3 downto 0),
            dp   => '0',
            sseg => HEX0
        );


end arch;
