# ============================================================
#  RHCE LAB — IMAGEN BASE DE LOS 4 NODOS
# ------------------------------------------------------------
#  Sistema : AlmaLinux 10 (binario compatible RHEL 10)
#  Motor   : systemd como PID 1 (contenedor "real-like")
#  Stack   : Ansible Core 2.16 + LVM2 + SELinux tools + Cronie
#
#  NOTAS DE DISEÑO:
#   - UNA sola imagen para control + node1..3: el rol de cada
#     nodo no lo decide la imagen, sino docker-compose (nombre,
#     IP fija, volúmenes). Un solo build, cuatro nodos.
#   - systemd como PID 1 (CMD /usr/sbin/init): los playbooks
#     ejercitan systemctl contra servicios de verdad, como en
#     el EX294; sin init los contenedores serían cajas vacías y
#     media batería del lab no tendría sentido.
#   - Usuario 'ansible' (wheel + NOPASSWD): emula al alumno del
#     examen real, con become sin contraseña.
#   - firewalld instalado y HABILITADO a propósito aunque no
#     filtra tráfico: 'systemctl is-enabled firewalld' debe dar
#     'enabled' (lo exige la Fase 1 de ./lab.sh test) y los
#     playbooks lo usan como servicio gestionable.
#   - Ansible 2.16 por pip (el dnf de Alma 10 no fija versión) y
#     colecciones del examen preinstaladas: el alumno no depende
#     de galaxy durante el lab.
#   - Los discos LVM fake nacen en esta imagen (secciones 5-7):
#     fake-disks.service + setup-disks.sh dejan a cada nodo SU
#     pareja de /dev/loopN en cada arranque.
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
    selinux-policy-targeted \
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
RUN ansible-galaxy collection install -p /usr/share/ansible/collections ansible.posix:1.5.4
RUN ansible-galaxy collection install -p /usr/share/ansible/collections community.general:7.0.0

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
#    firewalld entra en el 'enable' A PROPÓSITO: su daemon no
#    filtra tráfico real, pero así 'systemctl is-enabled
#    firewalld' = 'enabled', justo lo que exige la Fase 1 de
#    ./lab.sh test (y los enunciados tipo examen).
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
CMD ["/usr/sbin/init"]
