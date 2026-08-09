#!/usr/bin/env python3
"""
vcd_to_wavedrom.py -- converte o dump da simulacao (debug/sim_demo.vcd) em diagramas
WaveDrom, um por caso de teste do fp_adder_demo_tb.

Uso:
    python3 tools/vcd_to_wavedrom.py debug/sim_demo.vcd -o debug/wavedrom

Saida:
    <out>/EG1.json ... <out>/T11.json   (um objeto WaveDrom por caso)
    <out>/ondas.md                      (todos em blocos ```wavedrom)

O diagrama e por evento, nao por tempo: cada coluna e um instante em que
algum sinal exibido muda. O clock de 50 MHz fica de fora de proposito --
com colunas de duracao variavel ele so viraria ruido. A linha "t [ns]"
guarda o tempo real de cada coluna.
"""

import argparse
import json
import os
import re
import sys
from collections import OrderedDict

# ----------------------------------------------------------------------
# leitura do VCD
# ----------------------------------------------------------------------

VAR_RE = re.compile(r"\$var\s+\S+\s+(\d+)\s+(\S+)\s+(.+?)\s*\$end")
BIT_RE = re.compile(r"^(.*?)\s*\[(\d+)\]$")


def parse_vcd(path):
    """Devolve (scopes, changes).

    scopes  : { caminho_do_sinal : [(bit, id), ...] } ordenado do msb ao lsb
    changes : lista [(tempo, id, valor)] em ordem cronologica
    """
    signals = OrderedDict()   # nome completo -> {bit: id} ou {None: id}
    changes = []

    scope = []
    time = 0
    in_defs = True

    with open(path, "r", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue

            if in_defs:
                if line.startswith("$scope"):
                    scope.append(line.split()[2])
                    continue
                if line.startswith("$upscope"):
                    scope.pop()
                    continue
                if line.startswith("$var"):
                    m = VAR_RE.match(line)
                    if not m:
                        continue
                    _width, ident, name = m.groups()
                    mb = BIT_RE.match(name)
                    if mb:
                        base, bit = mb.group(1), int(mb.group(2))
                    else:
                        base, bit = name, None
                    full = "/".join(scope[1:] + [base]) if len(scope) > 1 else base
                    signals.setdefault(full, OrderedDict())[bit] = ident
                    continue
                if line.startswith("$enddefinitions"):
                    in_defs = False
                    continue
                continue

            if line.startswith("#"):
                time = int(line[1:])
                continue
            if line[0] in "$":
                continue
            if line[0] in "bB":
                val, ident = line[1:].split()
                changes.append((time, ident, val))
                continue
            changes.append((time, line[1:], line[0]))

    # ordena os bits do mais significativo para o menos
    for name, bits in signals.items():
        if list(bits.keys()) != [None]:
            signals[name] = OrderedDict(
                sorted(bits.items(), key=lambda kv: -kv[0])
            )
    return signals, changes


def build_timeline(signals, changes):
    """Reconstroi o valor de cada sinal (string de bits, msb primeiro)
    em cada instante. Devolve (tempos, {nome: {tempo: valor}})."""
    id_to = {}   # ident -> (nome, indice do bit dentro da string)
    state = {}
    for name, bits in signals.items():
        idents = list(bits.items())
        state[name] = ["x"] * len(idents)
        for idx, (_bit, ident) in enumerate(idents):
            id_to.setdefault(ident, []).append((name, idx))

    hist = {name: OrderedDict() for name in signals}
    times = []
    cur = None

    def snapshot(t):
        for name in signals:
            hist[name][t] = "".join(state[name])

    for t, ident, val in changes:
        if cur is None:
            cur = t
            times.append(t)
        elif t != cur:
            snapshot(cur)
            cur = t
            times.append(t)
        for name, idx in id_to.get(ident, []):
            state[name][idx] = val
    if cur is not None:
        snapshot(cur)
    return times, hist


# ----------------------------------------------------------------------
# formatacao dos valores
# ----------------------------------------------------------------------

SSEG = {
    "1000000": "0", "1111001": "1", "0100100": "2", "0110000": "3",
    "0011001": "4", "0010010": "5", "0000010": "6", "1111000": "7",
    "0000000": "8", "0010000": "9", "0001000": "A", "0000011": "b",
    "0100111": "C", "0100001": "d", "0000110": "E", "0001110": "F",
    "1111111": "_", "0111111": "-",
}


def as_int(bits):
    if any(c not in "01" for c in bits):
        return None
    return int(bits, 2)


def fmt_hex(bits):
    v = as_int(bits)
    if v is None:
        return "x"
    digits = (len(bits) + 3) // 4
    return "%0*X" % (digits, v)


def fmt_dec(bits):
    v = as_int(bits)
    return "x" if v is None else str(v)


def fmt_bin(bits):
    return bits


def fmt_sseg(bits):
    return SSEG.get(bits, "?")


# ----------------------------------------------------------------------
# recorte dos casos de teste
# ----------------------------------------------------------------------

NOMES = [
    ("EG1", "+0,54E3 + (-0,87E4)  -- alinha 1 casa, subtrai, fica em E4"),
    ("EG2", "+0,54E3 + (-0,55E3)  -- cancelamento sem expoente para renormalizar"),
    ("EG3", "+0,54E0 + (-0,55E0)  -- expoente no minimo, vira zero negativo"),
    ("EG4", "+0,56E3 + (+0,52E3)  -- vai-um, expoente sobe para E4"),
    ("T5",  "+0,54E6 + (-0,55E6)  -- expoente sobrando, renormaliza para -0,75"),
    ("T6",  "1,0 + 0,5            -- potencias de dois, resultado exato 1,5"),
    ("T7",  "-24 + 4              -- operando 1 e o maior, mantem o sinal"),
    ("T8",  "16384 + 0,996        -- exp_diff=15, o operando pequeno some"),
    ("T9",  "a + (-a) com exp=12  -- cancelamento total, zero nao canonico"),
    ("T10", "32640 + 32640        -- ESTOURO do expoente, HEX5 mostra C"),
    ("T11", "KEY1 reinicia os dois operandos em +1,0"),
]


def edges(hist, name, frm, to):
    """instantes em que o sinal de 1 bit vai de frm para to"""
    out = []
    prev = None
    for t, v in hist[name].items():
        if prev == frm and v == to:
            out.append(t)
        prev = v
    return out


def janelas(hist):
    """Uma janela por caso. Cada do_test dispara 4 pulsos de KEY0
    (2 campos por operando); T11 comeca no pulso de KEY1."""
    key0 = edges(hist, "KEY", "11", "10")  # KEY[1:0]: KEY0 desce
    key1 = edges(hist, "KEY", "11", "01")  # KEY1 desce
    if len(key0) < 40 or not key1:
        raise SystemExit("VCD nao tem os 10 casos com 4 cargas cada")

    reset = key1[0]
    # 30 ns antes da primeira borda: pega o SW ja posicionado para a carga.
    # O fim vai ate a vespera da proxima carga, porque a leitura do
    # resultado (SW(7)='1') so acontece depois das quatro cargas.
    ini = [max(0, key0[4 * i] - 30) for i in range(10)] + [max(0, reset - 10)]
    fim = [t - 1 for t in ini[1:]] + [max(hist["KEY"].keys())]
    return list(zip(ini, fim))


# ----------------------------------------------------------------------
# montagem do WaveDrom
# ----------------------------------------------------------------------

# (rotulo, sinal no VCD, formatador ou None para 1 bit)
LINHAS = [
    ("entrada", [
        ("SW[9:8] campo", "SW[9:8]", fmt_bin),
        ("SW[7] vista",   "SW[7]",   None),
        ("SW[6:0] dado",  "SW[6:0]", fmt_hex),
        ("KEY0 carrega",  "KEY[0]",  None),
        ("KEY1 reset",    "KEY[1]",  None),
    ]),
    ("operando 1", [
        ("sign1", "dut/sign1_reg", None),
        ("exp1",  "dut/exp1_reg",  fmt_dec),
        ("frac1", "dut/frac1_reg", fmt_hex),
    ]),
    ("operando 2", [
        ("sign2", "dut/sign2_reg", None),
        ("exp2",  "dut/exp2_reg",  fmt_dec),
        ("frac2", "dut/frac2_reg", fmt_hex),
    ]),
    ("fp_adder (interno)", [
        ("expb",     "dut/fp_add/expb",     fmt_dec),
        ("exps",     "dut/fp_add/exps",     fmt_dec),
        ("exp_diff", "dut/fp_add/exp_diff", fmt_dec),
        ("fracb",    "dut/fp_add/fracb",    fmt_hex),
        ("fracs",    "dut/fp_add/fracs",    fmt_hex),
        ("fraca",    "dut/fp_add/fraca",    fmt_hex),
        ("sum",      "dut/fp_add/sum",      fmt_hex),
        ("leado",    "dut/fp_add/leado",    fmt_dec),
        ("sum_norm", "dut/fp_add/sum_norm", fmt_hex),
    ]),
    ("resultado", [
        ("sign_out", "dut/sign_out", None),
        ("exp_out",  "dut/exp_out",  fmt_dec),
        ("frac_out", "dut/frac_out", fmt_hex),
    ]),
    ("displays", [
        ("HEX5 estouro", "HEX5_d", fmt_sseg),
        ("HEX4",         "HEX4_d", fmt_sseg),
        ("HEX3 sinal",   "HEX3_d", fmt_sseg),
        ("HEX2 exp",     "HEX2_d", fmt_sseg),
        ("HEX1 frac hi", "HEX1_d", fmt_sseg),
        ("HEX0 frac lo", "HEX0_d", fmt_sseg),
    ]),
]


def fatia(hist, name, ini, fim):
    """Nome pode ser 'SW[6:0]': recorta os bits do barramento."""
    m = re.match(r"^(.*)\[(\d+):(\d+)\]$", name)
    corte = None
    if m:
        name, hi, lo = m.group(1), int(m.group(2)), int(m.group(3))
        corte = (hi, lo)
    elif re.match(r"^(.*)\[(\d+)\]$", name):
        m2 = re.match(r"^(.*)\[(\d+)\]$", name)
        name, bit = m2.group(1), int(m2.group(2))
        corte = (bit, bit)

    serie = hist[name]
    largura = len(next(iter(serie.values())))

    def rec(v):
        if corte is None:
            return v
        hi, lo = corte
        # bit i esta na posicao (largura-1-i)
        return v[largura - 1 - hi: largura - lo]

    val = None
    out = OrderedDict()
    for t, v in serie.items():
        if t > fim:
            break
        val = rec(v)
        if t >= ini:
            out[t] = val
        else:
            out = OrderedDict([(ini, val)])
    if not out:
        out[ini] = val
    return out


def wavedrom(hist, blocos, head, foot, rotulo_caso=False):
    """blocos = [(nome, ini, fim), ...]. Com mais de um bloco, entra uma
    coluna de corte ('|') entre eles e uma linha 'caso' identificando cada
    trecho."""
    series = OrderedDict()
    for _grupo, linhas in LINHAS:
        for rotulo, sinal, fmt in linhas:
            series[rotulo] = (fatia(hist, sinal, 0, 10 ** 12), fmt)

    # colunas: (tempo, caso) para eventos, None para corte entre blocos
    colunas = []
    for i, (nome, ini, fim) in enumerate(blocos):
        if i:
            colunas.append(None)
        marcos = sorted({t for s, _f in series.values() for t in s
                         if ini <= t <= fim})
        if not marcos:
            marcos = [ini]
        colunas += [(t, nome) for t in marcos]

    def valor_em(serie, t):
        v = None
        for tt, vv in serie.items():
            if tt > t:
                break
            v = vv
        return v

    def linha(serie, fmt):
        wave, data, anterior = "", [], object()
        for col in colunas:
            if col is None:
                wave += "|"
                continue
            v = valor_em(serie, col[0])
            if fmt is None:
                c = "1" if v == "1" else ("0" if v == "0" else "x")
                wave += "." if v == anterior else c
            else:
                if v == anterior:
                    wave += "."
                else:
                    wave += "="
                    data.append(fmt(v))
            anterior = v
        return wave, data

    sig = []
    if rotulo_caso:
        wave, data, anterior = "", [], None
        for col in colunas:
            if col is None:
                wave += "|"
                continue
            if col[1] != anterior:
                wave += "="
                data.append(col[1])
            else:
                wave += "."
            anterior = col[1]
        sig.append({"name": "caso", "wave": wave, "data": data})

    sig += [
        {"name": "t [ns]",
         "wave": "".join("|" if c is None else "=" for c in colunas),
         "data": [str(c[0]) for c in colunas if c is not None]},
        {},
    ]
    for grupo, linhas in LINHAS:
        bloco = [grupo]
        for rotulo, _sinal, fmt in linhas:
            serie, f = series[rotulo]
            wave, data = linha(serie, f)
            item = {"name": rotulo, "wave": wave}
            if f is not None:
                item["data"] = data
            bloco.append(item)
        sig.append(bloco)
        sig.append({})
    if sig and sig[-1] == {}:
        sig.pop()

    return {
        "signal": sig,
        "head": {"text": head},
        "foot": {"text": foot},
        "config": {"hscale": 1},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd", nargs="?", default="debug/sim_demo.vcd")
    ap.add_argument("-o", "--out", default="debug/wavedrom")
    args = ap.parse_args()

    signals, changes = parse_vcd(args.vcd)
    _times, hist = build_timeline(signals, changes)

    os.makedirs(args.out, exist_ok=True)
    md = ["# Formas de onda da simulacao (WaveDrom)",
          "",
          "Gerado por `tools/vcd_to_wavedrom.py` a partir de `debug/sim_demo.vcd`.",
          "Cole cada bloco em <https://wavedrom.com/editor.html> para renderizar.",
          ""]

    js = janelas(hist)
    RODAPE = ("sim_demo.vcd  %d ns .. %d ns  (colunas por evento, "
              "clock de 50 MHz omitido)")

    for (nome, titulo), (ini, fim) in zip(NOMES, js):
        obj = wavedrom(hist, [(nome, ini, fim)],
                       "%s : %s" % (nome, titulo), RODAPE % (ini, fim))
        caminho = os.path.join(args.out, nome + ".json")
        with open(caminho, "w") as fh:
            json.dump(obj, fh, indent=2)
            fh.write("\n")
        colunas = len(obj["signal"][0]["wave"])
        print("%-4s %5d..%5d ns  %3d colunas  -> %s"
              % (nome, ini, fim, colunas, caminho))
        md += ["## %s -- %s" % (nome, titulo), "",
               "```wavedrom", json.dumps(obj, indent=2), "```", ""]

    # diagrama unico com os onze casos, separados por coluna de corte
    blocos = [(nome, ini, fim)
              for (nome, _t), (ini, fim) in zip(NOMES, js)]
    todos = wavedrom(hist, blocos,
                     "fp_adder_demo -- EG1 a T11 (simulacao completa)",
                     RODAPE % (js[0][0], js[-1][1]),
                     rotulo_caso=True)
    caminho = os.path.join(args.out, "TODOS.json")
    with open(caminho, "w") as fh:
        json.dump(todos, fh, indent=2)
        fh.write("\n")
    print("TODOS %5d..%5d ns  %3d colunas  -> %s"
          % (js[0][0], js[-1][1], len(todos["signal"][0]["wave"]), caminho))
    md += ["## TODOS -- os onze casos em um diagrama so", "",
           "```wavedrom", json.dumps(todos, indent=2), "```", ""]

    with open(os.path.join(args.out, "ondas.md"), "w") as fh:
        fh.write("\n".join(md))
    print("indice -> %s" % os.path.join(args.out, "ondas.md"))


if __name__ == "__main__":
    main()
