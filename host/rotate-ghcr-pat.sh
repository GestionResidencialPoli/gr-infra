#!/usr/bin/env bash
# Rota el PAT con el que k3s baja las imagenes privadas de GHCR (read:packages).
# 1) Crear el token nuevo en https://github.com/settings/tokens (classic, solo read:packages)
# 2) sudo GHCR_USER=MateoBermudez ./host/rotate-ghcr-pat.sh      (pide el token sin mostrarlo)
# 3) Revocar el token anterior en la misma pagina de GitHub.
# Los pods en ejecucion no se reinician; solo se reinicia el servicio k3s (API sin respuesta unos segundos).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecutar con sudo." >&2; exit 1; }
: "${GHCR_USER:?Falta GHCR_USER}"
read -rsp "Token nuevo (read:packages): " PAT; echo
[ -n "$PAT" ] || { echo "Token vacio." >&2; exit 1; }

# Se valida contra GHCR antes de tocar nada.
if ! curl -sf -u "$GHCR_USER:$PAT" "https://ghcr.io/token?service=ghcr.io&scope=repository:gestionresidencialpoli/gr-wall-ui:pull" | grep -q '"token"'; then
  echo "GHCR rechazo el token; no se modifico nada." >&2; exit 1
fi

umask 077
cat > /etc/rancher/k3s/registries.yaml <<REG
configs:
  "ghcr.io":
    auth:
      username: ${GHCR_USER}
      password: ${PAT}
REG
systemctl restart k3s
echo "Token rotado. Recuerda revocar el anterior en GitHub."
