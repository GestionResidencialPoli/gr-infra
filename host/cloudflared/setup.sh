#!/usr/bin/env bash
# Crea el tunel "gr", sus registros DNS y la config de cloudflared. Requiere un
# navegador para `cloudflared tunnel login` (elegir residencialpoli.online).
# Despues instala el servicio systemd (pide sudo).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN=residencialpoli.online
TUNNEL=gr
HOSTS=("$DOMAIN" api auth app admin muro reservas porteria finanzas)
CI_HOST="ci.$DOMAIN"

[ -f "$HOME/.cloudflared/cert.pem" ] || cloudflared tunnel login
cloudflared tunnel list 2>/dev/null | grep -qw "$TUNNEL" || cloudflared tunnel create "$TUNNEL"
UUID="$(cloudflared tunnel list -o json | python3 -c "import sys,json;print(next(t['id'] for t in json.load(sys.stdin) if t['name']=='$TUNNEL'))")"

CFG="$HOME/.cloudflared/config.yml"
{
  echo "tunnel: $UUID"
  echo "credentials-file: $HOME/.cloudflared/$UUID.json"
  echo "ingress:"
  echo "  - hostname: $CI_HOST"
  echo "    path: ^/generic-webhook-trigger/"
  echo "    service: http://127.0.0.1:8081"
  for h in "${HOSTS[@]}"; do
    fq="$h"; [ "$h" = "$DOMAIN" ] || fq="$h.$DOMAIN"
    echo "  - hostname: $fq"
    echo "    service: http://10.43.0.80:80"
  done
  echo "  - service: http_status:404"
} > "$CFG"
echo "Config escrita en $CFG"

for h in "${HOSTS[@]}" ci; do
  fq="$h"; [ "$h" = "$DOMAIN" ] || fq="$h.$DOMAIN"
  cloudflared tunnel route dns "$TUNNEL" "$fq" || echo "!! No se pudo crear DNS para $fq (si ya existe un registro, borrarlo en el panel o usar 'route dns -f')."
done

echo "Instalando servicio systemd (sudo)..."
sudo install -d /etc/cloudflared
sudo cp "$CFG" /etc/cloudflared/config.yml
sudo cp "$HOME/.cloudflared/$UUID.json" /etc/cloudflared/
sudo sed -i "s#$HOME/.cloudflared#/etc/cloudflared#" /etc/cloudflared/config.yml
sudo cloudflared service install
