#!/usr/bin/env bash
# Copia de seguridad cifrada del homelab con restic.
# La ejecuta el temporizador homelab-backup.timer (cada noche a las 03:00) o a mano: sudo ./backup/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

: "${BACKUP_REPO:?Falta BACKUP_REPO en .env (ver README, sección Copias de seguridad)}"
export RESTIC_REPOSITORY="$BACKUP_REPO"
export RESTIC_PASSWORD="$BACKUP_PASSWORD"
DATA_PATH="${DATA_PATH:-/srv/homelab}"
STAGE="$DATA_PATH/backups"
mkdir -p "$STAGE"

fail() {
  echo "ERROR: $1" >&2
  [[ -n "${BACKUP_PUSH_URL:-}" ]] && curl -fsS -m 10 "$BACKUP_PUSH_URL?status=down&msg=$(echo "$1" | jq -sRr @uri)" >/dev/null || true
  exit 1
}
trap 'fail "la copia falló en la línea $LINENO"' ERR

echo "==> Volcado de la base de datos de Immich"
# Immich recomienda volcar la base de datos en vez de copiar sus archivos en marcha
if docker ps --format '{{.Names}}' | grep -qx immich_postgres; then
  docker exec immich_postgres pg_dumpall --clean --if-exists -U postgres | gzip > "$STAGE/immich-db.sql.gz.tmp"
  mv "$STAGE/immich-db.sql.gz.tmp" "$STAGE/immich-db.sql.gz"
fi

echo "==> Copia consistente de Vaultwarden"
# Se para unos segundos para que su base de datos SQLite quede coherente
if docker ps --format '{{.Names}}' | grep -qx vaultwarden; then
  docker stop vaultwarden >/dev/null
  rsync -a --delete "$DATA_PATH/vaultwarden/" "$STAGE/vaultwarden/" || { docker start vaultwarden >/dev/null; fail "no se pudo copiar Vaultwarden"; }
  docker start vaultwarden >/dev/null
fi

PATHS=("$DATA_PATH" "$PWD/.env")
# Fotos fuera de DATA_PATH, y rutas extra (p. ej. datos de tu Pi-hole o Jellyfin propios)
EXCLUDES=()
if [[ "${BACKUP_PHOTOS:-true}" == false ]]; then
  [[ -n "${PHOTOS_PATH:-}" ]] && EXCLUDES+=(--exclude "$PHOTOS_PATH")
elif [[ -n "${PHOTOS_PATH:-}" ]]; then
  [[ "$PHOTOS_PATH" != "$DATA_PATH"/* ]] && PATHS+=("$PHOTOS_PATH")
  # Miniaturas y vídeos recodificados: Immich los regenera, no hace falta copiarlos
  EXCLUDES+=(--exclude "$PHOTOS_PATH/thumbs" --exclude "$PHOTOS_PATH/encoded-video")
fi
for p in ${EXTRA_BACKUP_PATHS:-}; do PATHS+=("$p"); done

echo "==> Subiendo copia cifrada a $BACKUP_REPO"
restic backup --tag homelab "${PATHS[@]}" \
  --exclude "$DATA_PATH/immich/postgres" \
  --exclude "$DATA_PATH/immich/model-cache" \
  --exclude "$DATA_PATH/jellyfin/cache" \
  --exclude "$DATA_PATH/netdata/cache" \
  --exclude "$DATA_PATH/vaultwarden" \
  "${EXCLUDES[@]}"

echo "==> Limpiando copias antiguas (7 diarias, 4 semanales, 6 mensuales)"
restic forget --tag homelab --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# Los domingos, verificar una parte de los datos para detectar corrupción
if [[ "$(date +%u)" == 7 ]]; then
  echo "==> Verificación semanal"
  restic check --read-data-subset=5%
fi

[[ -n "${BACKUP_PUSH_URL:-}" ]] && curl -fsS -m 10 "$BACKUP_PUSH_URL?status=up&msg=OK" >/dev/null || true
echo "==> Copia completada"
