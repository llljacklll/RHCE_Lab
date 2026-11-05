#!/bin/bash
# 36-D: gate de transporte locale-proof (leccion LC_ALL=C: la clase [^ -~]
# solo colaciona por byte bajo locale C). Puertas: bash -n | ASCII estricto
# (imprimible + NL; tab/CR = fallo) | <=80 col; >51 lineas solo avisa.
# Uso: ./lab.sh gate <archivo>...  (standalone: bash core/gate.sh <archivo>...)
lab_gate() {
  local f rc=0 out n bad
  if [ "$#" -lt 1 ]; then
    echo "[X] gate: uso: lab.sh gate <archivo> [archivo2 ...]"; return 1
  fi
  for f in "$@"; do
    bad=0
    if [ ! -f "$f" ]; then echo "[X] gate: $f no existe"; rc=1; continue; fi
    if ! out=$(bash -n "$f" 2>&1); then
      echo "[X] gate: sintaxis bash rota en $f:"; echo "$out"; bad=1
    fi
    out=$(LC_ALL=C grep -n '[^ -~]' "$f" 2>/dev/null)
    if [ -n "$out" ]; then
      echo "[X] gate: no-ASCII en $f:"; echo "$out"; bad=1
    fi
    out=$(LC_ALL=C awk 'length($0)>80 {print "  L"NR": "length($0)}' "$f")
    if [ -n "$out" ]; then
      echo "[X] gate: >80 col en $f:"; echo "$out"; bad=1
    fi
    n=$(LC_ALL=C wc -l < "$f" | tr -d ' ')
    if [ "$n" -gt 51 ]; then
      echo "[!] gate: $f = $n lineas (>51: aviso de transporte, no error)"
    fi
    if [ "$bad" -eq 0 ]; then echo "[+] gate OK: $f"; else rc=1; fi
  done
  return "$rc"
}
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  lab_gate "$@"; exit $?
fi
