#!/usr/bin/env bash
# Instala k3s (un solo nodo), cloudflared y la config minima para GHCR.
# Requiere sudo:   sudo GHCR_USER=MateoBermudez GHCR_PAT=<read:packages> ./host/install.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo." >&2; exit 1; }
: "${GHCR_USER:?Falta GHCR_USER}"
: "${GHCR_PAT:?Falta GHCR_PAT (PAT classic con read:packages)}"
TARGET_USER="${SUDO_USER:?Ejecutar con sudo desde tu usuario}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Config previa de k3s"
install -d -m 755 /etc/rancher/k3s /var/lib/rancher/k3s/server/manifests
install -m 644 "$HERE/traefik-config.yaml" /var/lib/rancher/k3s/server/manifests/traefik-config.yaml
# Las imagenes de GHCR son privadas: containerd necesita credenciales.
umask 077
cat > /etc/rancher/k3s/registries.yaml <<REG
configs:
  "ghcr.io":
    auth:
      username: ${GHCR_USER}
      password: ${GHCR_PAT}
REG
umask 022

echo "==> k3s (server, sin servicelb: Traefik queda solo como ClusterIP)"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable servicelb --write-kubeconfig-mode 600" sh -s -

echo "==> kubeconfig para $TARGET_USER"
install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.kube"
install -m 600 -o "$TARGET_USER" -g "$TARGET_USER" /etc/rancher/k3s/k3s.yaml "$TARGET_HOME/.kube/config"

echo "==> helm"
command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==> cloudflared"
if ! command -v cloudflared >/dev/null; then
  install -d -m 755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -qq && apt-get install -y -qq cloudflared
fi

echo
echo "Listo. Siguiente: ./host/bootstrap.sh (como usuario normal)."
