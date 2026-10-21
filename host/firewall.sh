#!/usr/bin/env bash
# Cierra la entrada desde la LAN: solo se acepta trafico del propio equipo, de los pods de
# k3s (cni0/flannel.1), de Docker y de la tailnet. Esto deja fuera de la LAN la API de k3s
# (6443) y el kubelet (10250), que escuchan en todas las interfaces. El SSH (22) se
# permite desde la subred de la LAN y desde la tailnet.
# NOTA: los puertos que Docker publica con -p (p. ej. 5432, 6379) NO pasan por ufw, hay que
# publicarlos en 127.0.0.1 desde su propio docker-compose si no deben verse en la LAN.
# Uso: sudo ./host/firewall.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo." >&2; exit 1; }
command -v ufw >/dev/null || apt-get install -y -qq ufw

# No se hace "ufw reset": el equipo puede tener reglas propias (ufw ya estaba activo).
# Solo se agregan las que faltan; ufw ignora las que ya existen.
echo "Reglas actuales:"; ufw status numbered || true
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed
for iface in lo cni0 flannel.1 docker0 tailscale0; do
  ufw allow in on "$iface" >/dev/null
done
# SSH (OpenSSH) solo desde la subred de la LAN del equipo; por la tailnet ya entra via tailscale0.
LAN_CIDR="$(ip -4 route show scope link | awk '!/^(10\.4[23]|172\.|192\.168\.122|169\.254)/ && !/flannel|cni|docker|virbr|br-|tailscale/ {print $1; exit}')"
[ -n "$LAN_CIDR" ] || { echo "No pude detectar la subred de la LAN; abortando para no dejarte sin SSH." >&2; exit 1; }
ufw allow from "$LAN_CIDR" to any port 22 proto tcp >/dev/null
echo "SSH permitido desde la LAN: $LAN_CIDR y por la tailnet"
# Pods -> API de k3s y servicios, cuando el trafico llega por la IP de la LAN.
ufw allow from 10.42.0.0/16 >/dev/null
ufw allow from 10.43.0.0/16 >/dev/null
ufw --force enable
ufw status verbose
