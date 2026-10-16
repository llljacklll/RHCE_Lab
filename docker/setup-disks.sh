#!/bin/bash
# ==========================================
# LVM Setup: Adaptado para Docker/WSL
# ==========================================
set -e
DISK_DIR="/opt/lvm_disks"; mkdir -p "$DISK_DIR"
losetup -D 2>/dev/null || true
truncate -s 1G "$DISK_DIR/disk1.img"; truncate -s 1G "$DISK_DIR/disk2.img"
losetup -d /dev/loop0 2>/dev/null || true; losetup -d /dev/loop1 2>/dev/null || true
losetup /dev/loop0 "$DISK_DIR/disk1.img"; losetup /dev/loop1 "$DISK_DIR/disk2.img"
wipefs -a /dev/loop0 2>/dev/null || true; wipefs -a /dev/loop1 2>/dev/null || true
if ! grep -q "use_devicesfile = 0" /etc/lvm/lvm.conf; then sed -i '/^devices {/a\    use_devicesfile = 0' /etc/lvm/lvm.conf; fi
echo "LVM Ready: /dev/loop0 and /dev/loop1"
