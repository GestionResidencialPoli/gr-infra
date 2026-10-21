#!/usr/bin/env bash
# Instala Tailscale y habilita Tailscale SSH: acceso por la identidad de la tailnet,
# sin llaves que repartir y sin abrir el puerto 22 a la LAN ni a internet.
# Uso: sudo ./host/tailscale.sh        (abre una URL para autorizar este equipo)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo." >&2; exit 1; }

HOSTNAME_TS="${TS_HOSTNAME:-gr-prod}"

if ! command -v tailscale >/dev/null; then
  . /etc/os-release
  install -d -m 755 /usr/share/keyrings
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq
  apt-get install -y -qq tailscale
fi
systemctl enable --now tailscaled

# --ssh: tailscaled atiende el SSH solo en la interfaz de la tailnet.
# El DNS de la tailnet no se toca (--accept-dns=false) para no afectar a k3s ni a Docker.
tailscale up --ssh --hostname="$HOSTNAME_TS" --accept-dns=false

echo
tailscale status | head -5
echo
echo "Desde otro equipo de tu tailnet:  ssh $(logname 2>/dev/null || echo "$SUDO_USER")@${HOSTNAME_TS}"
echo "Las reglas de quien puede entrar se administran en https://login.tailscale.com/admin/acls"
