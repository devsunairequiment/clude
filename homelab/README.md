# Homelab

Prepara un servidor Debian/Ubuntu y levanta los servicios con Docker.

## Instalación

```bash
# Desde tu PC
ssh reyes@192.168.1.26
git clone https://github.com/devsunairequiment/clude.git && cd clude/homelab
git checkout claude/relaxed-cray-ba9bg0
cp .env.example .env && nano .env    # ajusta TZ, MEDIA_PATH, WG_HOST
sudo ./install.sh
```

Después, cambia la contraseña y pasa a autenticación por clave:

```bash
passwd                               # en el servidor
ssh-copy-id reyes@192.168.1.26       # desde tu PC
sudo ./harden-ssh.sh                 # en el servidor
```

## Servicios

| Servicio | Puerto | Para qué |
|---|---|---|
| Homepage | 3000 | Dashboard central |
| Portainer | 9443 | Gestionar Docker |
| Nginx Proxy Manager | 81 (admin), 80/443 | HTTPS y subdominios |
| AdGuard Home | 8080 / 3003 (primer setup) | DNS con bloqueo de anuncios; se omite si ya hay Pi-hole |
| Uptime Kuma | 3001 | Alertas si algo se cae |
| Jellyfin | 8096 | Películas y series |
| Immich | 2283 | Fotos y vídeos, con app móvil y copia automática |
| Home Assistant | 8123 | Domótica y automatizaciones |
| Vaultwarden | vía NPM | Gestor de contraseñas |
| Netdata | 19999 | Métricas en tiempo real |
| wg-easy (opcional, `ENABLE_WG=1`) | 51821 (admin), 51820/udp | VPN propia; por defecto se usa Tailscale |
| Watchtower | — | Actualizaciones automáticas a las 04:00 |

## Después de instalar
1. **AdGuard**: abre `:3003` para el primer setup y luego pon la IP del servidor como DNS en tu router.
2. **NPM**: entra en `:81` (admin@example.com / changeme) y cambia las credenciales.
3. **Vaultwarden**: ejecuta `sudo ./vaultwarden-https.sh` (HTTPS con Tailscale), crea tu cuenta y pon `VAULTWARDEN_SIGNUPS=false` en `.env`.
4. **VPN**: abre el puerto 51820/udp en el router hacia el servidor.
5. Pon una IP fija al servidor (reserva DHCP en el router).
