#!/usr/bin/env bash
# Desactiva el login SSH con contraseña. Solo se ejecuta si ya hay una clave autorizada.
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo"; exit 1; fi
USER_HOME="$(getent passwd "${SUDO_USER:-reyes}" | cut -d: -f6)"
if [[ ! -s "$USER_HOME/.ssh/authorized_keys" ]]; then
  echo "No hay claves en $USER_HOME/.ssh/authorized_keys."
  echo "Desde tu PC ejecuta primero: ssh-copy-id ${SUDO_USER:-reyes}@$(hostname -I | awk '{print $1}')"
  exit 1
fi
cat >/etc/ssh/sshd_config.d/99-homelab.conf <<C
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
C
sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd
echo "Listo: SSH ahora solo acepta claves. No cierres esta sesión hasta probar otra."
