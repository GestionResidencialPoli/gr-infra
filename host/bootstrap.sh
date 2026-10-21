#!/usr/bin/env bash
# Crea el namespace, el RBAC de Jenkins, el Secret gr-app-secrets y hace el
# primer helm install. Idempotente: se puede volver a correr.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
ENV_FILE="${GR_ENV_FILE:-$HOME/.config/gr-infra/.env}"

for bin in kubectl helm openssl; do command -v "$bin" >/dev/null || { echo "Falta $bin" >&2; exit 1; }; done

echo "==> Esperando a k3s"
kubectl wait --for=condition=Ready node --all --timeout=180s

if [ ! -f "$ENV_FILE" ]; then
  echo "==> Generando $ENV_FILE (chmod 600)"
  install -d -m 700 "$(dirname "$ENV_FILE")"
  rnd() { openssl rand -hex "$1"; }
  umask 077
  cat > "$ENV_FILE" <<ENV
DB_USERNAME=gr_admin
DB_PASSWORD=$(rnd 24)
RABBITMQ_DEFAULT_USER=gr_rabbit
RABBITMQ_DEFAULT_PASS=$(rnd 24)
JWT_SECRET=$(rnd 32)
INTERNAL_SERVICE_TOKEN=$(rnd 32)
CORS_ALLOWED_ORIGINS=https://residencialpoli.online,https://auth.residencialpoli.online,https://app.residencialpoli.online,https://admin.residencialpoli.online,https://muro.residencialpoli.online,https://reservas.residencialpoli.online,https://porteria.residencialpoli.online,https://finanzas.residencialpoli.online
ENV
fi

echo "==> Namespace, RBAC y Secret"
kubectl create namespace gr-app --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$INFRA/k8s/jenkins-rbac.yaml"
kubectl create secret generic gr-app-secrets -n gr-app --from-env-file="$ENV_FILE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> helm upgrade --install (sin --wait: las imagenes de UI aparecen cuando su CI las publique)"
helm upgrade --install gr-app "$INFRA/helm/gr-app" -n gr-app -f "$INFRA/helm/gr-app/values-prod.yaml"

kubectl get pods -n gr-app
