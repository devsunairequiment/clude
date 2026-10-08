#!/usr/bin/env bash
# Publica Vaultwarden con HTTPS válido usando Tailscale Serve.
# Queda accesible solo desde tus dispositivos con Tailscale: https://<servidor>.<tailnet>.ts.net
# Uso: sudo ./vaultwarden-https.sh
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo: sudo ./vaultwarden-https.sh"; exit 1; fi
cd "$(dirname "$0")"

if ! tailscale status >/dev/null 2>&1; then
  echo "Tailscale no está conectado. Ejecuta 'sudo tailscale up', inicia sesión y vuelve a lanzar este script."
  exit 1
fi

HOST="$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
if [[ -z "$HOST" || "$HOST" == "null" ]]; then
  echo "No encuentro el nombre de Tailscale. Activa MagicDNS en https://login.tailscale.com/admin/dns"
  exit 1
fi
URL="https://$HOST"
echo "==> Vaultwarden se publicará en $URL"

# Guardar el dominio en .env (Vaultwarden lo necesita para la app y los enlaces)
if grep -q '^VAULTWARDEN_DOMAIN=' .env; then
  sed -i "s|^VAULTWARDEN_DOMAIN=.*|VAULTWARDEN_DOMAIN=$URL|" .env
else
  echo "VAULTWARDEN_DOMAIN=$URL" >> .env
fi

echo "==> Reiniciando Vaultwarden"
docker compose up -d vaultwarden

echo "==> Activando HTTPS con Tailscale Serve"
echo "    (si te muestra un enlace, ábrelo para activar los certificados HTTPS en tu cuenta)"
tailscale serve --bg --https=443 http://127.0.0.1:8222

cat <<M

==============================================
 Vaultwarden listo en: $URL
 1. Ábrelo desde un dispositivo con Tailscale y crea tu cuenta.
 2. En la app/extensión de Bitwarden: "Autoalojado" -> URL del servidor: $URL
 3. Cierra los registros: pon VAULTWARDEN_SIGNUPS=false en .env y ejecuta
    sudo docker compose up -d vaultwarden
==============================================
M
