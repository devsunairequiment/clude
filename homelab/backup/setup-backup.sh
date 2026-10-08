#!/usr/bin/env bash
# Prepara las copias de seguridad: instala restic, crea el repositorio cifrado y programa la copia nocturna.
# Uso: sudo ./backup/setup-backup.sh
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo: sudo ./backup/setup-backup.sh"; exit 1; fi
cd "$(dirname "$0")/.."
DIR="$PWD"

apt-get install -y restic rsync rclone jq >/dev/null
restic self-update >/dev/null 2>&1 || true

# Destino por defecto: carpeta local, separada de los datos (gratis, en este servidor)
if ! grep -q '^BACKUP_REPO=.\+' .env; then
  sed -i '/^BACKUP_REPO=$/d' .env
  echo "BACKUP_REPO=/srv/backups/homelab" >> .env
  echo "==> Destino de las copias: /srv/backups/homelab (en este servidor)"
fi

if ! grep -q '^BACKUP_PASSWORD=.\+' .env; then
  echo "BACKUP_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 40)" >> .env
  NEW_PASS=1
fi
chmod 600 .env

set -a; source .env; set +a
export RESTIC_REPOSITORY="$BACKUP_REPO" RESTIC_PASSWORD="$BACKUP_PASSWORD"
if [[ "$BACKUP_REPO" == /* ]]; then
  mkdir -p "$BACKUP_REPO"
  chmod 700 "$BACKUP_REPO"
  # En el mismo disco que los datos, duplicar las fotos solo gasta espacio: no protege si el disco falla
  if [[ "$(df --output=source "$BACKUP_REPO" | tail -1)" == "$(df --output=source "${DATA_PATH:-/srv/homelab}" | tail -1)" ]]; then
    echo "==> La copia está en el mismo disco que los datos: protege de borrados y fallos de"
    echo "    actualización, no de que el disco se rompa. Las fotos de Immich no se duplican"
    echo "    (Immich ya tiene papelera de 30 días). Cámbialo con BACKUP_PHOTOS=true en .env."
    grep -q '^BACKUP_PHOTOS=' .env || echo "BACKUP_PHOTOS=false" >> .env
  fi
fi
if restic cat config >/dev/null 2>&1; then
  echo "==> El repositorio ya existe"
else
  echo "==> Creando repositorio cifrado"
  restic init
fi

cat >/etc/systemd/system/homelab-backup.service <<U
[Unit]
Description=Copia de seguridad del homelab
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$DIR/backup/backup.sh
# Bajo consumo: prioridad mínima, como mucho media CPU (2 hilos) y 1 GB de RAM
Nice=19
IOSchedulingClass=idle
CPUQuota=50%
MemoryHigh=1G
Environment=GOMAXPROCS=2
Environment=RESTIC_CACHE_DIR=/var/cache/restic
U
cat >/etc/systemd/system/homelab-backup.timer <<U
[Unit]
Description=Copia de seguridad nocturna del homelab

[Timer]
OnCalendar=*-*-* 03:00
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
U
systemctl daemon-reload
systemctl enable --now homelab-backup.timer

echo
echo "==> Copias programadas cada noche a las 03:00. Próxima ejecución:"
systemctl list-timers homelab-backup.timer --no-pager | sed -n 2p
if [[ -n "${NEW_PASS:-}" ]]; then
  cat <<M

!!! IMPORTANTE: guarda esta contraseña fuera del servidor (papel, otro gestor) !!!
!!! Sin ella las copias NO se pueden recuperar.                                   !!!
    BACKUP_PASSWORD=$BACKUP_PASSWORD
M
fi
echo
echo "Primera copia ahora (puede tardar si tienes muchas fotos):  sudo systemctl start homelab-backup"
echo "Ver el progreso:                                           journalctl -u homelab-backup -f"
