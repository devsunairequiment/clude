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
ufw allow from "$LAN" to any port 81,2283,3000,3001,3003,8096,8123,9443,8080,19999,51821 proto tcp
ufw allow from "$LAN" to any port 5353 proto udp      # mDNS: Home Assistant descubre dispositivos
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
# Variables nuevas que un .env antiguo no tenga
grep -q '^PHOTOS_PATH=' .env || echo "PHOTOS_PATH=$(grep -oP '^DATA_PATH=\K.*' .env || echo /srv/homelab)/immich/library" >> .env
grep -q '^IMMICH_VERSION=' .env || echo "IMMICH_VERSION=v3" >> .env
# Contraseña aleatoria para la base de datos de Immich (solo letras y números)
grep -q '^IMMICH_DB_PASSWORD=' .env || echo "IMMICH_DB_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)" >> .env
ours() { [[ "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$1" 2>/dev/null)" == "homelab" ]]; }
exists() { docker ps -a --format '{{.Names}}' | grep -qx "$1"; }
port_busy() { ss -Hlntu "( sport = :$1 )" | grep -q .; }
PROFILES=()

# Jellyfin solo se crea si no existe ya uno propio en el servidor
if exists jellyfin && ! ours jellyfin; then
  echo "    Ya tienes un Jellyfin propio: lo respeto y no creo otro"
else
  PROFILES+=(--profile jellyfin)
fi

# AdGuard solo si el puerto 53 está libre (si ya tienes Pi-hole, se usa ese)
exists adguard && ours adguard && docker rm -f adguard >/dev/null
if port_busy 53; then
  echo "    El puerto 53 ya lo usa otro DNS (p. ej. Pi-hole): no instalo AdGuard"
else
  PROFILES+=(--profile adguard)
fi

# Nginx Proxy Manager en puertos alternativos si el 80/443 están ocupados
exists npm && ours npm && docker rm -f npm >/dev/null
if port_busy 80 || port_busy 443; then
  grep -q '^NPM_HTTP_PORT=' .env || printf 'NPM_HTTP_PORT=8880\nNPM_HTTPS_PORT=8443\n' >> .env
  ufw allow 8880,8443/tcp >/dev/null
  echo "    El puerto 80/443 está ocupado: Nginx Proxy Manager usará 8880/8443"
fi

# VPN WireGuard propia solo si se pide; por defecto se usa Tailscale
if grep -q '^ENABLE_WG=1' .env; then
  PROFILES+=(--profile vpn)
else
  exists wg-easy && ours wg-easy && docker rm -f wg-easy >/dev/null
fi

docker compose "${PROFILES[@]}" up -d

NPM_PORT="$(grep -oP '^NPM_HTTP_PORT=\K.*' .env || echo 80)"

IP="$(hostname -I | awk '{print $1}')"
cat <<M

==============================================
 Homelab listo. Abre en tu navegador:
  Dashboard ........ http://$IP:3000
  Portainer ........ https://$IP:9443
  Proxy (NPM) ...... http://$IP:81  (proxy en el puerto $NPM_PORT)
  DNS .............. Pi-hole o AdGuard (http://$IP:8080)
  Uptime Kuma ...... http://$IP:3001
  Jellyfin ......... http://$IP:8096
  Immich (fotos) ... http://$IP:2283
  Home Assistant ... http://$IP:8123
  Netdata .......... http://$IP:19999
  Vaultwarden ...... vía NPM con HTTPS
  Acceso remoto .... Tailscale
 Siguiente paso: ./harden-ssh.sh (después de copiar tu clave SSH)
==============================================
M
