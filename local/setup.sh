#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$HERE")"
UNIVERSITY_DIR="$(dirname "$INFRA_DIR")"
CLUSTER_NAME=gr-local
DOMAIN=gr.local

for bin in kind kubectl helm docker; do
  command -v "$bin" >/dev/null || { echo "Falta '$bin' en el PATH." >&2; exit 1; }
done

if [ ! -f "$HERE/.env" ]; then
  echo "Falta $HERE/.env (copiar .env.example y completar los secretos)." >&2
  exit 1
fi

echo "==> Cluster kind"
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind create cluster --config "$HERE/kind-cluster.yaml"
else
  echo "Ya existe el cluster '$CLUSTER_NAME'."
  if ! kubectl --context "kind-$CLUSTER_NAME" get nodes -l gr-app/role=backend --no-headers | grep -q .; then
    echo "El cluster existente no tiene los nodos backend/frontend. Ejecutar local/teardown.sh y volver a correr este script." >&2
    exit 1
  fi
fi
kubectl config use-context "kind-$CLUSTER_NAME"

echo "==> ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

declare -A MIGRATE_REPOS=( [gr-wall-microservice]=1 [gr-booking-microservice]=1 [gr-gate-microservice]=1 )
BACKEND_REPOS=(gr-user-microservice gr-wall-microservice gr-booking-microservice gr-gate-microservice gr-contact-microservice gr-billing-microservice gr-api-gateway)

echo "==> Construyendo imagenes de backend"
for repo in "${BACKEND_REPOS[@]}"; do
  name="${repo#gr-}"
  echo "  - $repo -> local/gr-$name:local"
  docker build -t "local/gr-$name:local" "$UNIVERSITY_DIR/$repo"
  if [ -n "${MIGRATE_REPOS[$repo]:-}" ]; then
    echo "  - $repo (migrate) -> local/gr-$name:migrate-local"
    docker build --target migrate -t "local/gr-$name:migrate-local" "$UNIVERSITY_DIR/$repo"
  fi
done

echo "==> Construyendo imagenes de UI (apuntando a *.${DOMAIN})"
declare -A UI_EXTRA_ARGS=(
  [gr-admin-ui]="--build-arg NEXT_PUBLIC_AUTH_UI_URL=http://auth-ui.${DOMAIN}"
  [gr-auth-ui]="--build-arg NEXT_PUBLIC_ADMIN_UI_URL=http://admin-ui.${DOMAIN} --build-arg NEXT_PUBLIC_COMMON_UI_URL=http://common-ui.${DOMAIN}"
  [gr-common-ui]="--build-arg NEXT_PUBLIC_AUTH_UI_URL=http://auth-ui.${DOMAIN}"
  [gr-wall-ui]="--build-arg NEXT_PUBLIC_AUTH_UI_URL=http://auth-ui.${DOMAIN}"
  [gr-booking-ui]="--build-arg NEXT_PUBLIC_AUTH_UI_URL=http://auth-ui.${DOMAIN}"
  [gr-gate-ui]="--build-arg NEXT_PUBLIC_AUTH_UI_URL=http://auth-ui.${DOMAIN}"
)
UI_REPOS=(gr-common-ui gr-admin-ui gr-auth-ui gr-wall-ui gr-booking-ui gr-gate-ui gr-public-ui gr-billing-ui)
for repo in "${UI_REPOS[@]}"; do
  name="${repo#gr-}"
  echo "  - $repo -> local/gr-$name:local"
  docker build -t "local/gr-$name:local" \
    --build-arg BACKEND_API_URL=http://gateway:4000 \
    ${UI_EXTRA_ARGS[$repo]:-} \
    "$UNIVERSITY_DIR/$repo"
done

echo "==> Cargando imagenes en el cluster"
for img in $(docker images "local/*" --format "{{.Repository}}:{{.Tag}}"); do
  kind load docker-image "$img" --name "$CLUSTER_NAME"
done

echo "==> Namespace y secret"
kubectl create namespace gr-app --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic gr-app-secrets -n gr-app \
  --from-env-file="$HERE/.env" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> helm upgrade --install"
helm upgrade --install gr-app "$INFRA_DIR/helm/gr-app" -n gr-app \
  -f "$INFRA_DIR/helm/gr-app/values-local.yaml" \
  -f "$INFRA_DIR/helm/gr-app/values-2nodos.yaml" \
  --wait --timeout 300s

echo "==> Distribucion de pods por nodo"
kubectl get pods -n gr-app -o wide

cat <<EOF

Listo. Agregar a /etc/hosts si no esta ya:

127.0.0.1 gateway.${DOMAIN} common-ui.${DOMAIN} admin-ui.${DOMAIN} auth-ui.${DOMAIN} wall-ui.${DOMAIN} booking-ui.${DOMAIN} gate-ui.${DOMAIN} public-ui.${DOMAIN} billing-ui.${DOMAIN}

Luego abrir http://common-ui.${DOMAIN} (y las demas UIs).
EOF
