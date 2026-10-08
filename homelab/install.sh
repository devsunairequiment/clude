#!/usr/bin/env bash
# Instalador del homelab: prepara el servidor (Debian/Ubuntu) y levanta los servicios.
# Uso: sudo ./install.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo: sudo ./install.sh"; exit 1; fi
REAL_USER="${SUDO_USER:-reyes}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Actualizando sistema"
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg ufw fail2ban unattended-upgrades \
  htop btop git vim tmux ncdu smartmontools lm-sensors jq

echo "==> Actualizaciones de seguridad automáticas"
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Instalando Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$REAL_USER"
systemctl enable --now docker

echo "==> Firewall (solo red local + puertos web)"
LAN="$(ip -o -4 route show to default | awk '{print $3}' | cut -d. -f1-3).0/24"
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$LAN" to any port 22 proto tcp
ufw allow 80,443/tcp
ufw allow from "$LAN" to any port 53
ufw allow from "$LAN" to any port 81,3000,3001,3003,8096,9443,8080,19999,51821 proto tcp
ufw allow from "$LAN" to any port 3389 proto tcp      # xrdp (escritorio remoto)
ufw allow from "$LAN" to any port 139,445 proto tcp   # Samba
ufw allow in on tailscale0                            # Tailscale
ufw allow 51820/udp   # WireGuard
ufw --force enable

echo "==> Fail2ban para SSH"
cat >/etc/fail2ban/jail.local <<J
[sshd]
enabled = true
maxretry = 5
bantime = 1h
J
systemctl enable --now fail2ban

echo "==> Liberando el puerto 53 para AdGuard"
if systemctl is-active --quiet systemd-resolved; then
  mkdir -p /etc/systemd/resolved.conf.d
  printf "[Resolve]\nDNSStubListener=no\nDNS=1.1.1.1\n" >/etc/systemd/resolved.conf.d/adguard.conf
  # Sin el stub, 127.0.0.53 deja de responder: resolv.conf debe apuntar a DNS reales.
  # Solo se conserva un resolv.conf propio si tiene "nameserver" válidos distintos del stub.
  if grep -E '^nameserver ' /etc/resolv.conf 2>/dev/null | grep -vq '127.0.0.53'; then
    echo "    /etc/resolv.conf tiene DNS propios: lo dejo como está"
  else
    if lsattr -d /etc/resolv.conf 2>/dev/null | cut -d' ' -f1 | grep -q i; then
      echo "    /etc/resolv.conf está bloqueado (chattr +i) sin DNS válidos: lo desbloqueo"
      chattr -i /etc/resolv.conf
    fi
    # rm + ln: el ln de rust-coreutils (Ubuntu 26.04) no sobrescribe con -sf
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
  fi
  systemctl restart systemd-resolved
fi

echo "==> Levantando servicios"
cd "$DIR"
[[ -f .env ]] || cp .env.example .env
# Jellyfin solo se crea si no existe ya uno en el servidor
if docker ps -a --format '{{.Names}}' | grep -qx jellyfin && \
   [[ "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' jellyfin)" != "homelab" ]]; then
  echo "    Ya tienes un Jellyfin propio: lo respeto y no creo otro"
  docker compose up -d
else
  docker compose --profile jellyfin up -d
fi

IP="$(hostname -I | awk '{print $1}')"
cat <<M

==============================================
 Homelab listo. Abre en tu navegador:
  Dashboard ........ http://$IP:3000
  Portainer ........ https://$IP:9443
  Proxy (NPM) ...... http://$IP:81
  AdGuard (DNS) .... http://$IP:8080
  Uptime Kuma ...... http://$IP:3001
  Jellyfin ......... http://$IP:8096
  Netdata .......... http://$IP:19999
  Vaultwarden ...... vía NPM con HTTPS
 Siguiente paso: ./harden-ssh.sh (después de copiar tu clave SSH)
==============================================
M
