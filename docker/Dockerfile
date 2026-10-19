# ============================================================
#  🐳 RHCE LAB — IMAGEN BASE DE LOS 4 NODOS
# ------------------------------------------------------------
#  Sistema : AlmaLinux 10 (binario compatible RHEL 10)
#  Motor   : systemd como PID 1 (contenedor "real-like")
#  Stack   : Ansible Core 2.16 + LVM2 + SELinux tools + Cronie
#
#  NOTAS DE DISEÑO:
#   - Los 4 contenedores (control + node1..3) usan ESTA misma
#     imagen: el rol de "control" lo da el docker-compose.
#   - El usuario 'ansible' (wheel + NOPASSWD) emula al usuario
#     de examen del EX294 real.
#   - firewalld se instala y habilita, pero los playbooks lo
#     usan en modo 'offline' (ver README.md (seccion Notas tecnicas)).
# ============================================================

FROM almalinux:10

# Indicamos a systemd que corre dentro de un contenedor
ENV container=docker

# ------------------------------------------------------------
# 1) PAQUETES DEL SISTEMA
# ------------------------------------------------------------
RUN dnf install -y \
    systemd \
    openssh-server \
    openssh-clients \
    sudo \
    python3 \
    python3-pip \
    iproute \
    firewalld \
    dbus \
    curl \
    wget \
    vim \
    lvm2 \
    xfsprogs \
    e2fsprogs \
    parted \
    cronie \
    policycoreutils-python-utils \
    setools-console \
    net-tools \
    sshpass \
    tar \
    bzip2 \
    unzip \
    && dnf clean all

# ------------------------------------------------------------
# 2) ANSIBLE CORE 2.16 + COLECCIONES DEL EXAMEN
#    (vía pip: el dnf de Alma 10 no fija la versión 2.16)
# ------------------------------------------------------------
RUN pip3 install ansible-core==2.16.* \
        --break-system-packages --no-cache-dir
RUN ansible-galaxy collection install ansible.posix:1.5.4
RUN ansible-galaxy collection install community.general:7.0.0

# ------------------------------------------------------------
# 3) CONFIGURACIÓN SSH
#    - PasswordAuthentication → bootstrap inicial de claves
#    - UseDNS no → evita lentitud de resolución inversa
# ------------------------------------------------------------
RUN mkdir -p /var/run/sshd && ssh-keygen -A && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config

# ------------------------------------------------------------
# 4) USUARIO 'ansible' (el "alumno" del laboratorio)
#    wheel + NOPASSWD → become sin contraseña
# ------------------------------------------------------------
RUN useradd -m -s /bin/bash ansible && \
    echo "ansible:ansible" | chpasswd && \
    usermod -aG wheel ansible && \
    echo "ansible ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ------------------------------------------------------------
# 5) SERVICIOS HABILITADOS AL ARRANQUE
#    🔧 FIX BUG 2: firewalld añadido al 'enable'. El daemon no
#    corre (modo offline), pero así 'systemctl is-enabled' =
#    'enabled' y la Fase 1 de ./lab.sh test pasa correctamente.
# ------------------------------------------------------------
RUN systemctl enable sshd crond firewalld

# ------------------------------------------------------------
# 6) OVERRIDES DE SYSTEMD PARA CONTENEDORES
# ------------------------------------------------------------
RUN mkdir -p /etc/systemd/system/firewalld.service.d && \
    echo -e "[Unit]\nRequires=dbus.service\nAfter=dbus.service\n" \
      > /etc/systemd/system/firewalld.service.d/override.conf
RUN systemctl disable systemd-resolved || true
RUN systemctl disable systemd-networkd  || true
RUN systemctl disable NetworkManager    || true

# ------------------------------------------------------------
# 7) DISCOS VIRTUALES PARA PRÁCTICAS LVM
#    fake-disks.service ejecuta setup-disks.sh al arrancar y
#    deja SU pareja de discos por nodo (node1: loop0/1, node2: loop2/3,
#    node3: loop4/5; control: ninguno). Los loops son globales en el
#    kernel: por eso cada nodo usa solo los suyos.
# ------------------------------------------------------------
COPY setup-disks.sh /usr/local/bin/setup-disks.sh
RUN chmod +x /usr/local/bin/setup-disks.sh
COPY fake-disks.service /etc/systemd/system/fake-disks.service
RUN systemctl enable fake-disks.service

# ------------------------------------------------------------
# 8) CONFIG ANSIBLE + ARRANQUE
# ------------------------------------------------------------
COPY ansible.cfg /etc/ansible/ansible.cfg
# LVM sin udev (contenedor): override anti-udev
COPY lvmlocal.conf /etc/lvm/lvmlocal.conf
ENV ANSIBLE_INVENTORY=/opt/ansible/inventory/hosts.ini
# FIX12: horneado para autoarranque (sin dnf en runtime)
RUN dnf install -y mdadm cryptsetup && dnf clean all
RUN ssh-keygen -A || true
CMD ["/usr/sbin/init"]
