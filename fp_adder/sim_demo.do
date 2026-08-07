# =====================================================================
#  sim_demo.do  --  simulacao do fp_adder_demo no Questa / ModelSim
#
#  Uso:
#     1) coloque este arquivo na mesma pasta dos .vhd
#     2) no prompt do Questa:   do sim_demo.do
# =====================================================================

# ---------------------------------------------------------------------
# biblioteca de trabalho
# ---------------------------------------------------------------------
if {[file exists work]} { vdel -all }
vlib work
vmap work work

# ---------------------------------------------------------------------
# compilacao (a ordem importa: pacotes/entidades antes de quem instancia)
# ---------------------------------------------------------------------
vcom -2008 fp_adder.vhd
vcom -2008 hex_to_sseg.vhd
vcom -2008 fp_adder_demo.vhd
vcom -2008 fp_adder_demo_tb.vhd

# ---------------------------------------------------------------------
# elaboracao
#   +acc mantem os sinais internos visiveis (sem isso o otimizador
#   descarta expb, exps, fraca, sum, leado... e o "add wave" falha)
# ---------------------------------------------------------------------
vsim -voptargs=+acc work.fp_adder_demo_tb

# ---------------------------------------------------------------------
# radix customizado: mostra o DIGITO que aparece no display,
# em vez do padrao de bits dos segmentos
#
# tabela retirada diretamente de hex_to_sseg.vhd (segmentos gfedcba,
# ativos em nivel baixo)
# ---------------------------------------------------------------------
radix define sseg {
    7'b1000000 "0",
    7'b1111001 "1",
    7'b0100100 "2",
    7'b0110000 "3",
    7'b0011001 "4",
    7'b0010010 "5",
    7'b0000010 "6",
    7'b1111000 "7",
    7'b0000000 "8",
    7'b0010000 "9",
    7'b0001000 "A",
    7'b0000011 "b",
    7'b0100111 "C",
    7'b0100001 "d",
    7'b0000110 "E",
    7'b0001110 "F",
    -default hex
}

# ---------------------------------------------------------------------
# janela de waveform
# ---------------------------------------------------------------------
delete wave *

add wave -divider "Placa: entradas"
add wave -radix binary  /fp_adder_demo_tb/SW
add wave -radix binary  /fp_adder_demo_tb/KEY
add wave                /fp_adder_demo_tb/MAX10_CLK1_50

add wave -divider "Displays (o que aparece na placa)"
add wave -radix sseg    /fp_adder_demo_tb/HEX5_d
add wave -radix sseg    /fp_adder_demo_tb/HEX4_d
add wave -radix sseg    /fp_adder_demo_tb/HEX3_d
add wave -radix sseg    /fp_adder_demo_tb/HEX2_d
add wave -radix sseg    /fp_adder_demo_tb/HEX1_d
add wave -radix sseg    /fp_adder_demo_tb/HEX0_d

add wave -divider "Pontos decimais (1 = aceso)"
add wave                /fp_adder_demo_tb/DP5
add wave                /fp_adder_demo_tb/DP2

add wave -divider "Operandos registrados"
add wave                /fp_adder_demo_tb/dut/sign1_reg
add wave -radix unsigned /fp_adder_demo_tb/dut/exp1_reg
add wave -radix hex     /fp_adder_demo_tb/dut/frac1_reg
add wave                /fp_adder_demo_tb/dut/sign2_reg
add wave -radix unsigned /fp_adder_demo_tb/dut/exp2_reg
add wave -radix hex     /fp_adder_demo_tb/dut/frac2_reg

add wave -divider "Estagios internos do somador"
add wave -radix unsigned /fp_adder_demo_tb/dut/fp_add/expb
add wave -radix unsigned /fp_adder_demo_tb/dut/fp_add/exps
add wave -radix unsigned /fp_adder_demo_tb/dut/fp_add/exp_diff
add wave -radix hex     /fp_adder_demo_tb/dut/fp_add/fracb
add wave -radix hex     /fp_adder_demo_tb/dut/fp_add/fracs
add wave -radix hex     /fp_adder_demo_tb/dut/fp_add/fraca
add wave -radix hex     /fp_adder_demo_tb/dut/fp_add/sum
add wave -radix unsigned /fp_adder_demo_tb/dut/fp_add/leado
add wave -radix hex     /fp_adder_demo_tb/dut/fp_add/sum_norm

add wave -divider "Resultado"
add wave                /fp_adder_demo_tb/dut/sign_out
add wave -radix unsigned /fp_adder_demo_tb/dut/exp_out
add wave -radix hex     /fp_adder_demo_tb/dut/frac_out

add wave -divider "LEDs"
add wave -radix binary  /fp_adder_demo_tb/LEDR

configure wave -namecolwidth 260
configure wave -valuecolwidth 90
configure wave -timelineunits ns

# ---------------------------------------------------------------------
# roda ate o fim do testbench
# ---------------------------------------------------------------------
run -all
wave zoom full
