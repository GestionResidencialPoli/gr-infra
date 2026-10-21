#!/usr/bin/env bash
# Cierra la entrada desde la LAN: solo se acepta trafico del propio equipo, de los pods de
# k3s (cni0/flannel.1), de Docker y de la tailnet. Esto deja fuera de la LAN la API de k3s
# (6443) y el kubelet (10250), que escuchan en todas las interfaces.
# NOTA: los puertos que Docker publica con -p (p. ej. 5432, 6379) NO pasan por ufw, hay que
# publicarlos en 127.0.0.1 desde su propio docker-compose si no deben verse en la LAN.
# Uso: sudo ./host/firewall.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo." >&2; exit 1; }
command -v ufw >/dev/null || apt-get install -y -qq ufw

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed
for iface in lo cni0 flannel.1 docker0 tailscale0; do
  ufw allow in on "$iface" >/dev/null
done
# Pods -> API de k3s y servicios, cuando el trafico llega por la IP de la LAN.
ufw allow from 10.42.0.0/16 >/dev/null
ufw allow from 10.43.0.0/16 >/dev/null
ufw --force enable
ufw status verbose
