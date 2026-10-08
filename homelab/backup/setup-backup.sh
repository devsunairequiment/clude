#!/usr/bin/env bash
# Prepara las copias de seguridad: instala restic, crea el repositorio cifrado y programa la copia nocturna.
# Uso: sudo ./backup/setup-backup.sh
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Ejecuta con sudo: sudo ./backup/setup-backup.sh"; exit 1; fi
cd "$(dirname "$0")/.."
DIR="$PWD"

apt-get install -y restic rsync rclone jq >/dev/null
restic self-update >/dev/null 2>&1 || true

if ! grep -q '^BACKUP_REPO=.\+' .env; then
  cat <<M
Falta el destino de las copias. Añade a .env una de estas líneas y vuelve a ejecutar:
  BACKUP_REPO=/mnt/backup/homelab            # otro disco montado en /mnt/backup
  BACKUP_REPO=rclone:gdrive:homelab-backup   # Google Drive/OneDrive/... (antes: rclone config)
  BACKUP_REPO=s3:https://s3.eu-central-003.backblazeb2.com/mi-bucket   # Backblaze B2 / S3
    (para B2/S3 añade también AWS_ACCESS_KEY_ID=... y AWS_SECRET_ACCESS_KEY=...)
M
  exit 1
fi

if ! grep -q '^BACKUP_PASSWORD=.\+' .env; then
  echo "BACKUP_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 40)" >> .env
  NEW_PASS=1
fi
chmod 600 .env

set -a; source .env; set +a
export RESTIC_REPOSITORY="$BACKUP_REPO" RESTIC_PASSWORD="$BACKUP_PASSWORD"
if [[ "$BACKUP_REPO" == /* ]]; then
  mountpoint -q "$(dirname "$BACKUP_REPO")" || echo "AVISO: $(dirname "$BACKUP_REPO") no es un disco montado; la copia quedaría en el mismo disco."
  mkdir -p "$BACKUP_REPO"
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
Nice=10
IOSchedulingClass=idle
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
