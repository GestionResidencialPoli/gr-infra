#!/usr/bin/env bash
# Construye el kubeconfig de Jenkins a partir del ServiceAccount jenkins-deployer
# (acotado al namespace gr-app). Salida: ~/.config/gr-infra/jenkins-config
set -euo pipefail
OUT="${1:-$HOME/.config/gr-infra/jenkins-config}"
install -d -m 700 "$(dirname "$OUT")"
TOKEN="$(kubectl get secret jenkins-deployer-token -n gr-app -o jsonpath='{.data.token}' | base64 -d)"
CA="$(kubectl get secret jenkins-deployer-token -n gr-app -o jsonpath='{.data.ca\.crt}')"
umask 077
cat > "$OUT" <<KC
apiVersion: v1
kind: Config
clusters:
  - name: k3s
    cluster:
      server: https://127.0.0.1:6443
      certificate-authority-data: ${CA}
users:
  - name: jenkins-deployer
    user:
      token: ${TOKEN}
contexts:
  - name: gr-app
    context: { cluster: k3s, user: jenkins-deployer, namespace: gr-app }
current-context: gr-app
KC
echo "Escrito $OUT"
