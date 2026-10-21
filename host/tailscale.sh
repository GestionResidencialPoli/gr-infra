#!/usr/bin/env bash
# Instala Tailscale (solo como red privada) y OpenSSH. El SSH es el sshd normal del
# sistema, accesible por la IP de la LAN (desde la casa) y por la IP de Tailscale
# (desde fuera). NO se usa Tailscale SSH.
# Uso: sudo ./host/tailscale.sh        (abre una URL para autorizar este equipo)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo." >&2; exit 1; }

HOSTNAME_TS="${TS_HOSTNAME:-mateo-desktop-ubuntu}"
TARGET_USER="${SUDO_USER:?Ejecutar con sudo desde tu usuario}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "==> OpenSSH"
apt-get install -y -qq openssh-server
# Endurecimiento: sin root. Solo se desactiva la clave por contrasena si ya hay una llave
# autorizada, para no dejarte fuera: agregar tu llave publica a ~/.ssh/authorized_keys.
{
  echo "PermitRootLogin no"
  echo "MaxAuthTries 4"
  if [ -s "$TARGET_HOME/.ssh/authorized_keys" ]; then
    echo "PasswordAuthentication no"
    echo "KbdInteractiveAuthentication no"
  else
    echo "# PasswordAuthentication sigue activo: no hay llaves en $TARGET_HOME/.ssh/authorized_keys"
  fi
} > /etc/ssh/sshd_config.d/10-gr.conf
# /run/sshd lo crea el servicio al arrancar; sshd -t lo necesita antes de que arranque.
install -d -m 0755 /run/sshd
sshd -t
systemctl enable --now ssh
systemctl reload ssh

echo "==> Tailscale"
if ! command -v tailscale >/dev/null; then
  . /etc/os-release
  install -d -m 755 /usr/share/keyrings
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq
  apt-get install -y -qq tailscale
fi
systemctl enable --now tailscaled
# --accept-dns=false: no tocar el DNS del equipo (afectaria a k3s y Docker).
tailscale up --hostname="$HOSTNAME_TS" --accept-dns=false

TS_IP="$(tailscale ip -4 | head -1)"
echo
echo "Por Tailscale:   ssh $TARGET_USER@$TS_IP   o   ssh $TARGET_USER@$HOSTNAME_TS"
[ -s "$TARGET_HOME/.ssh/authorized_keys" ] || echo "AVISO: sin llaves autorizadas; desde el otro equipo ejecuta  ssh-copy-id $TARGET_USER@$HOSTNAME_TS  y luego vuelve a correr este script para desactivar la contrasena."
