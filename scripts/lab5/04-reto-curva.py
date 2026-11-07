#!/usr/bin/env python3
"""scripts/lab5/04-reto-curva.py — reto de la Parte E: dibuja la curva del punto de equilibrio en SVG.

Lee la sección 3 de la evidencia de 04-agrupamiento-equilibrio.sql (k %, lecturas con CF bueno, CF malo,
tabla entera y lo que elige el optimizador) y escribe un SVG con ejes logarítmicos. Solo biblioteca estándar.
Uso: python3 scripts/lab5/04-reto-curva.py <evidencia 04 .script.log> <salida .svg>
"""
import math
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
fila = re.compile(r"^\s*([\d.]+) %\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)")
datos = []
for linea in open(src, encoding="utf-8", errors="replace"):
    m = fila.match(linea)
    if m:
        k, _, bueno, malo, tabla, elige = m.groups()
        datos.append((float(k), int(bueno), int(malo), int(tabla), elige.startswith("recorrido")))
assert len(datos) >= 5, "no encuentro la tabla de la sección 3 en la evidencia"

W, H, ML, MR, MT, MB = 760, 460, 70, 170, 30, 50
x0, x1 = math.log10(datos[0][0]), math.log10(datos[-1][0])
y0, y1 = 0, math.log10(max(d[2] for d in datos) * 1.5)
X = lambda k: ML + (math.log10(k) - x0) / (x1 - x0) * (W - ML - MR)
Y = lambda v: H - MB - (math.log10(max(v, 1)) - y0) / (y1 - y0) * (H - MT - MB)

def serie(i, color, nombre):
    pts = " ".join(f"{X(d[0]):.1f},{Y(d[i]):.1f}" for d in datos)
    yl = Y(datos[-1][i])
    return (f'<polyline fill="none" stroke="{color}" stroke-width="2.5" points="{pts}"/>'
            + "".join(f'<circle cx="{X(d[0]):.1f}" cy="{Y(d[i]):.1f}" r="3" fill="{color}"/>' for d in datos)
            + f'<text x="{W - MR + 8}" y="{yl + 4:.1f}" fill="{color}" font-size="13">{nombre}</text>')

def cruce(i):
    """primer k en que la serie i supera a la tabla entera"""
    return next((d[0] for d in datos if d[i] > d[3]), None)

partes = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="sans-serif">',
          f'<rect width="{W}" height="{H}" fill="white"/>']
for e in range(0, int(y1) + 1):                       # rejilla horizontal: 1, 10, 100...
    y = Y(10 ** e)
    partes.append(f'<line x1="{ML}" y1="{y:.1f}" x2="{W - MR}" y2="{y:.1f}" stroke="#e5e5e5"/>'
                  f'<text x="{ML - 8}" y="{y + 4:.1f}" text-anchor="end" font-size="11">{10 ** e:,}</text>')
for d in datos:                                       # marcas del eje x
    partes.append(f'<text x="{X(d[0]):.1f}" y="{H - MB + 18}" text-anchor="middle" font-size="11">{d[0]:g}</text>')
partes.append(f'<text x="{(ML + W - MR) / 2}" y="{H - 10}" text-anchor="middle" font-size="12">k (% de filas de PEDIDO, escala logarítmica)</text>')
partes.append(f'<text x="16" y="{(MT + H - MB) / 2}" transform="rotate(-90 16 {(MT + H - MB) / 2})" text-anchor="middle" font-size="12">lecturas lógicas (escala logarítmica)</text>')
cambio = next(d[0] for d in datos if d[4])            # primer k en que el optimizador elige recorrido completo
partes.append(f'<line x1="{X(cambio):.1f}" y1="{MT}" x2="{X(cambio):.1f}" y2="{H - MB}" stroke="#7a3db8" stroke-dasharray="5,4"/>'
              f'<text x="{X(cambio) + 4:.1f}" y="{MT + 12}" fill="#7a3db8" font-size="11">optimizador: FULL desde {cambio:g} %</text>')
for i, color in ((2, "#c0392b"), (1, "#1e7b34")):
    k = cruce(i)
    if k is not None:
        partes.append(f'<circle cx="{X(k):.1f}" cy="{Y(datos[[d[0] for d in datos].index(k)][3]):.1f}" r="7" fill="none" stroke="{color}" stroke-width="2"/>')
partes.append(serie(3, "#555555", "tabla entera"))
partes.append(serie(1, "#1e7b34", "índice CF bueno"))
partes.append(serie(2, "#c0392b", "índice CF malo"))
partes.append('</svg>')
open(dst, "w", encoding="utf-8").write("\n".join(partes))
print(f"SVG: {dst} · CF malo cruza la tabla en {cruce(2):g} % · CF bueno en {cruce(1):g} % · optimizador cambia en {cambio:g} %")
