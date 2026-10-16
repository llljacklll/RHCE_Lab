#!/bin/bash
# ==========================================
#  RHCE LAB - Bootstrap del host (MV)
#  Instala Docker Engine + compose v2 en
#  Rocky/Alma/RHEL/CentOS 9-10 (familia EL).
#  Idempotente: re-lanzable sin dano.
#  Repo oficial docker-ce (el repo "centos"
#  de Docker sirve para todo EL: Rocky y
#  Alma resuelven $releasever a 9/10).
# ==========================================
set -u

fail() { echo "[FAIL] $*"; exit 1; }
step() { echo ""; echo "== $* =="; }

# ---------- 1) Sistema ----------
step "1/6 Sistema"
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
step "2/6 Paquetes conflictivos"
dnf remove -y docker docker-client docker-common docker-containerd podman runc 2>/dev/null || true
echo "[OK] limpio (o no habia nada)"

# ---------- 3) Repo oficial ----------
step "3/6 Repositorio docker-ce"
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
step "4/6 Instalando engine + plugins"
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    || fail "dnf install fallo (revisa red/repo)"

# ---------- 5) Servicio ----------
step "5/6 Habilitando docker.service"
systemctl enable --now docker || fail "no arranco docker.service"

# ---------- 6) Verificaciones para el lab ----------
step "6/6 Verificaciones del host"
ok=0
for i in 1 2 3 4 5; do docker info >/dev/null 2>&1 && ok=1 && break; sleep 2; done
[ "$ok" = "1" ] && echo "[OK] dockerd responde: $(docker -v)" \
    || fail "docker info no responde (mirar journalctl -u docker)"
docker compose version >/dev/null 2>&1 \
    && echo "[OK] compose v2: $(docker compose version)" \
    || fail "falta docker-compose-plugin"
[ -e /dev/loop-control ] && echo "[OK] /dev/loop-control (discos fake LVM)" \
    || { modprobe loop 2>/dev/null || true; \
         [ -e /dev/loop-control ] && echo "[OK] /dev/loop-control (tras modprobe loop)" \
             || echo "[AVISO] falta /dev/loop-control: el LVM del lab fallara"; }
CGROUP=$(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo "?")
[ "$CGROUP" = "cgroup2fs" ] && echo "[OK] cgroup v2 (systemd como PID 1)" \
    || echo "[AVISO] cgroup montado como '$CGROUP' (se espera cgroup2fs)"
echo "    SELinux: $(getenforce 2>/dev/null || echo Disabled) (contenedores privileged: no requiere Permissive)"
echo ""
echo "[DONE] host listo. Siguiente: docker compose -f docker/docker-compose.yml build && ./lab.sh"
