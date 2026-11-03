#!/bin/bash
# ============================================================
#  SCRIPTS/VM_BOOTSTRAP.SH — Bootstrap del host (máquina virtual)
# ------------------------------------------------------------
#  Prepara una MV Rocky/Alma/RHEL/CentOS 9-10 (EL) recién
#  instalada para el laboratorio: Docker Engine + compose v2,
#  PyYAML (para los exámenes --random) y los loop devices de
#  los discos LVM fake. Idempotente: re-lanzable sin daño.
#
#  LAS 7 FASES:
#   1) Sistema — verifica distro EL 9/10 y root.
#   2) Limpieza — fuera docker/podman de distro (chocan con
#                 docker-ce).
#   3) Repo — docker-ce oficial para EL.
#   4) Instalación — engine + plugins + PyYAML.
#   5) Servicio — docker.service habilitado y arrancado.
#   6) Verificación — dockerd responde, compose v2, loop-control
#                 PyYAML importable y cgroup v2 (requisitos del lab).
#   7) Loops — registra /dev/loop0-15 en el kernel y los
#                 MANTIENE con la unidad rhce-lab-loop: EL10 no
#                 los crea al arrancar (el kernel de WSL2 sí;
#                 por eso el lab funcionaba en WSL y reventaba
#                 en la MV hasta esta unidad).
# ============================================================
set -u

fail() { echo "[FAIL] $*"; exit 1; }
step() { echo ""; echo "== $* =="; }

# ---------- 1) Sistema ----------
step "1/7 Sistema"
[ -f /etc/os-release ] || fail "no hay /etc/os-release"
. /etc/os-release
MAJOR=${VERSION_ID%%.*}
echo "    distro:  ${PRETTY_NAME:-?}"
echo "    familia: ${ID:-?} (EL ${MAJOR:-?})"
case "${ID:-}" in
    rocky|almalinux|rhel|centos) ;;
    *) fail "distro '${ID}' no soportada (se espera Rocky/Alma/RHEL/CentOS)" ;;
esac
case "${MAJOR:-}" in
    9|10) ;;
    *) fail "EL ${MAJOR} no testeado (solo 9 y 10)" ;;
esac
[ "$(id -u)" = "0" ] || fail "ejecuta como root: bash scripts/vm_bootstrap.sh"

# ---------- 2) Conflictivos fuera ----------
step "2/7 Paquetes conflictivos"
dnf remove -y docker docker-client docker-common docker-containerd podman runc 2>/dev/null || true
echo "[OK] limpio (o no habia nada)"

# ---------- 3) Repo oficial ----------
step "3/7 Repositorio docker-ce"
cat > /etc/yum.repos.d/docker-ce.repo << 'REPOEOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/centos/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
REPOEOF
dnf -q makecache --disablerepo='*' --enablerepo='docker-ce-stable' || dnf -q makecache || true
echo "[OK] repo escrito (EL${MAJOR})"

# ---------- 4) Instalacion ----------
step "4/7 Instalando engine + plugins"
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin python3-pyyaml \
    || fail "dnf install fallo (revisa red/repo)"

# ---------- 5) Servicio ----------
step "5/7 Habilitando docker.service"
systemctl enable --now docker || fail "no arranco docker.service"

# ---------- 6) Verificaciones para el lab ----------
step "6/7 Verificaciones del host"
ok=0
for i in 1 2 3 4 5; do docker info >/dev/null 2>&1 && ok=1 && break; sleep 2; done
[ "$ok" = "1" ] && echo "[OK] dockerd responde: $(docker -v)" \
    || fail "docker info no responde (mirar journalctl -u docker)"
docker compose version >/dev/null 2>&1 \
    && echo "[OK] compose v2: $(docker compose version)" \
    || fail "falta docker-compose-plugin"
python3 -c "import yaml" >/dev/null 2>&1 \
    && echo "[OK] PyYAML importable: $(python3 -c 'import yaml; print(yaml.__version__)')" \
    || fail "python3-pyyaml no importable (mirar: which -a python3)"
[ -e /dev/loop-control ] && echo "[OK] /dev/loop-control (discos fake LVM)" \
    || { modprobe loop 2>/dev/null || true; \
         [ -e /dev/loop-control ] && echo "[OK] /dev/loop-control (tras modprobe loop)" \
             || echo "[AVISO] falta /dev/loop-control: el LVM del lab fallara"; }
CGROUP=$(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo "?")
[ "$CGROUP" = "cgroup2fs" ] && echo "[OK] cgroup v2 (systemd como PID 1)" \
    || echo "[AVISO] cgroup montado como '$CGROUP' (se espera cgroup2fs)"
echo "    SELinux: $(getenforce 2>/dev/null || echo Disabled) (contenedores privileged: no requiere Permissive)"

# ---------- 7) Loop devices del lab (PERSISTENTE) ----------
# EL10 NO crea /dev/loopN al arrancar (solo loop-control); el kernel
# de WSL2 si los creaba: por eso el lab funcionaba en WSL y fallaba en
# MV. Se registran via LOOP_CTL_ADD y una unidad systemd del host los
# mantiene vivos tras cualquier reinicio.
step "7/7 Loop devices (discos LVM del lab)"
cat > /usr/local/sbin/rhce-lab-loop.sh << 'LOOPSH'
#!/bin/bash
python3 - <<'PYEOF'
import fcntl, os, errno
fd = os.open('/dev/loop-control', os.O_RDWR)
for i in range(16):
    try:
        fcntl.ioctl(fd, 0x4C80, i)
    except OSError as e:
        if e.errno != errno.EEXIST:
            print(f'[WARN] loop{i}: {e.strerror}')
print('[OK] /dev/loop0-15 registrados en el kernel')
PYEOF
LOOPSH
chmod 755 /usr/local/sbin/rhce-lab-loop.sh
cat > /etc/systemd/system/rhce-lab-loop.service << 'UNITEOF'
[Unit]
Description=RHCE Lab: registra /dev/loopN (discos fake LVM)
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/rhce-lab-loop.sh
[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl enable --now rhce-lab-loop.service >/dev/null 2>&1
N=$(ls /dev/loop[0-9]* 2>/dev/null | wc -l)
[ "$N" -ge 8 ] && echo "[OK] /dev/loop* disponibles en el host: $N" \
    || echo "[AVISO] solo $N loop devices (ver: systemctl status rhce-lab-loop)"

echo ""
echo "[DONE] host listo. Siguiente: docker compose -f docker/docker-compose.yml build && ./lab.sh"
