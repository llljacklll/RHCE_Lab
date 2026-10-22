#!/bin/bash
# ============================================================
#  SCRIPTS/AUDIT_PY.SH — Auditor de heredocs python embebidos
# ------------------------------------------------------------
#  Recorre todos los .sh del repo (raíz, core/, core/checkers/,
#  scripts/, docker/), extrae CADA heredoc python3 y lo compila
#  con py_compile. Detecta dos clases de daño silencioso:
#    [SIN-CERRAR] la marca de cierre no aparece (heredoc
#                 truncado por una edición desafortunada)
#    [CORRUPTO]   el cuerpo no compila como python puro
#  TRUCO: antes de compilar, $VAR y ${VAR} se sustituyen por
#  '3' — en ejecución el shell los interpolaría, pero el cuerpo
#  debe compilar igual como python estático.
#  CONTRATO: exit 0 = todos sanos; exit 1 = defectos (listados
#  con fichero + marca + línea). Apta para CI o pre-commit.
#  NOTA (excepción funcional del lote 8): el cd era ~/RHCE_Lab
#  absoluto y rompía en cualquier otra ruta (p.ej. Dropbox);
#  ahora es relativo al repo, como smoke_test.sh.
# ============================================================
set -u
cd "$(dirname "$0")/.." || exit 1
python3 - << 'PYEOF'
import glob, re, sys, py_compile, tempfile, os
total = bad = 0
files = (glob.glob('*.sh') + glob.glob('core/*.sh') +
         glob.glob('core/checkers/*.sh') + glob.glob('scripts/*.sh') +
         glob.glob('docker/*.sh'))
for f in sorted(set(files)):
    lines = open(f, encoding='utf-8', errors='replace').read().split('\n')
    i = 0
    while i < len(lines):
        if 'python3' in lines[i] and '<<' in lines[i]:
            m = re.search(r"<<-?\s*['\"]?(\w+)", lines[i])
            if m:
                mark = m.group(1)
                body, j = [], i + 1
                while j < len(lines) and lines[j].strip() != mark:
                    body.append(lines[j]); j += 1
                total += 1
                if j >= len(lines):
                    print('[SIN-CERRAR] %s: heredoc %s (linea %d)' % (f, mark, i+1))
                    bad += 1
                else:
                    tf = tempfile.NamedTemporaryFile('w', suffix='.py', delete=False)
                    tf.write(re.sub(r'\$\{?[A-Za-z_]\w*\}?', '3', '\n'.join(body))); tf.close()
                    try:
                        py_compile.compile(tf.name, doraise=True)
                    except py_compile.PyCompileError as e:
                        print('[CORRUPTO] %s: heredoc %s (linea %d)' % (f, mark, i+1))
                        for ln in str(e).split('\n'):
                            if ln.strip(): print('    ' + ln)
                        bad += 1
                    os.unlink(tf.name)
                i = j + 1
                continue
        i += 1
print('=== %d heredocs python: %d OK, %d defectuosos ===' % (total, total-bad, bad))
sys.exit(1 if bad else 0)
PYEOF
