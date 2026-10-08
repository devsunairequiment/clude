#!/usr/bin/env bash
# Revisa que todos los servicios del homelab estén en marcha y respondiendo.
# Uso: sudo ./check.sh
cd "$(dirname "$0")"
G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N=$'\e[0m'
FAILS=0

echo "== Contenedores =="
for c in homepage portainer npm uptime-kuma vaultwarden immich_server immich_machine_learning \
         immich_redis immich_postgres homeassistant open-webui netdata watchtower jellyfin pihole ollama; do
  st="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null)"
  restarts="$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null)"
  if [[ -z "$st" ]]; then printf "  %-24s ${Y}no existe${N}\n" "$c"; continue; fi
  if [[ "$st" == running* && "$st" != *unhealthy* ]]; then
    printf "  %-24s ${G}OK${N}  (%s, reinicios: %s)\n" "$c" "${st% }" "$restarts"
  else
    printf "  %-24s ${R}FALLO${N} (%s)\n" "$c" "$st"; FAILS=$((FAILS+1))
  fi
done

echo; echo "== Respuesta web =="
web() {
  code="$(curl -ksm 8 -o /dev/null -w '%{http_code}' "$2")"
  if [[ "$code" =~ ^(2|3|401) ]]; then printf "  %-24s ${G}OK${N}  (HTTP %s) %s\n" "$1" "$code" "$2"
  else printf "  %-24s ${R}FALLO${N} (HTTP %s) %s\n" "$1" "$code" "$2"; FAILS=$((FAILS+1)); fi
}
web Homepage            http://127.0.0.1:3000
web Portainer           https://127.0.0.1:9443
web "Nginx Proxy Mgr"   http://127.0.0.1:81
web "Uptime Kuma"       http://127.0.0.1:3001
web Netdata             http://127.0.0.1:19999
web Immich              http://127.0.0.1:2283/api/server/ping
web "Home Assistant"    http://127.0.0.1:8123
web "Open WebUI"        http://127.0.0.1:3080/health
web Vaultwarden         http://127.0.0.1:8222/alive
web Jellyfin            http://127.0.0.1:8096/health
web Pi-hole             http://127.0.0.1/admin/
# Ollama tal como lo ve Open WebUI: por la red Docker "ai"
if docker exec open-webui curl -fsm 5 http://ollama:11434/api/version >/dev/null 2>&1 || \
   docker exec open-webui python3 -c "import urllib.request;urllib.request.urlopen('http://ollama:11434/api/version',timeout=5)" >/dev/null 2>&1; then
  printf "  %-24s ${G}OK${N}  (accesible desde Open WebUI, %s modelos)\n" Ollama "$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | wc -l)"
else
  printf "  %-24s ${R}FALLO${N} (Open WebUI no llega a http://ollama:11434)\n" Ollama; FAILS=$((FAILS+1))
fi

echo; echo "== Otros =="
if dig +short +time=3 @127.0.0.1 google.com | grep -q .; then echo "  DNS Pi-hole              ${G}OK${N}"; else echo "  DNS Pi-hole              ${R}FALLO${N}"; FAILS=$((FAILS+1)); fi
if tailscale status >/dev/null 2>&1; then echo "  Tailscale                ${G}OK${N}  ($(tailscale ip -4 2>/dev/null))"; else echo "  Tailscale                ${Y}desconectado${N}"; fi
tailscale serve status 2>/dev/null | grep -q 8222 && echo "  Vaultwarden HTTPS        ${G}OK${N}  ($(tailscale serve status | grep -oE 'https://[^ ]+' | head -1))" || echo "  Vaultwarden HTTPS        ${Y}sin configurar${N} (sudo ./vaultwarden-https.sh)"
last="$(systemctl show homelab-backup -p ExecMainStatus --value 2>/dev/null)"
next="$(systemctl list-timers homelab-backup.timer --no-pager 2>/dev/null | sed -n 2p | awk '{print $1, $2, $3}')"
if [[ "$last" == 0 ]]; then echo "  Copia de seguridad       ${G}OK${N}  (próxima: $next)"; else echo "  Copia de seguridad       ${R}FALLO${N} (journalctl -u homelab-backup)"; FAILS=$((FAILS+1)); fi
systemctl is-active -q ufw && echo "  Firewall                 ${G}OK${N}" || { echo "  Firewall                 ${R}inactivo${N}"; FAILS=$((FAILS+1)); }
systemctl is-active -q fail2ban && echo "  Fail2ban                 ${G}OK${N}" || { echo "  Fail2ban                 ${R}inactivo${N}"; FAILS=$((FAILS+1)); }
echo "  Disco /                  $(df -h / | awk 'NR==2{print $5" usado, "$4" libres"}')"
echo "  RAM                      $(free -h | awk '/^Mem/{print $3" usados de "$2}')"
temp="$(sensors 2>/dev/null | grep -m1 -oP '(Package id 0|Tctl|temp1):\s+\+\K[0-9.]+')"
[[ -n "$temp" ]] && echo "  Temperatura CPU          ${temp} °C"

echo
if (( FAILS == 0 )); then echo "${G}Todo funcionando.${N}"; else echo "${R}$FAILS problema(s) encontrados.${N}"; fi
