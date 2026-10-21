# Entorno local con kind

Levanta el stack completo sobre Kubernetes real (en un cluster `kind`, no en el k3s del
homelab), usando el mismo chart de Helm que producción (`../helm/gr-app`) con las imágenes
construidas y cargadas localmente, y las 8 UIs encendidas (en producción viven en Vercel, por
eso están apagadas por defecto en `values.yaml`).

Esto **no reemplaza** `../docker-compose.local.yml` para el día a día — es más lento de
levantar. Sirve para probar la topología de Kubernetes (Deployments, Services, Ingress,
migraciones como initContainer) antes de que un cambio llegue al k3s real.

## Requisitos

`docker`, `kind`, `kubectl`, `helm`.

```bash
brew install kind kubectl helm
```

## Topologia: 2 nodos y 2 replicas

El cluster kind tiene el control-plane (ingress-nginx y los puertos 80/443) y dos nodos de trabajo
etiquetados:

| Nodo (label) | Carga |
|---|---|
| `gr-app/role=backend` | gateway, user, wall, booking, gate, contact y billing, mas postgres, redis y rabbitmq |
| `gr-app/role=frontend` | las 8 UIs |

`helm/gr-app/values-2nodos.yaml` fija cada carga a su nodo con `nodeSelector` y sube a 2 las replicas
de los servicios de aplicacion y de las UIs. Postgres, redis y rabbitmq siguen en 1 replica.
`setup.sh` lo aplica junto con `values-local.yaml`.

Verificar la distribucion:

```bash
kubectl get pods -n gr-app -o wide
kubectl get nodes -L gr-app/role
```

Si el cluster `gr-local` ya existia con un solo nodo, ejecutar `./teardown.sh` antes de `./setup.sh`.

Sin `values-2nodos.yaml` el chart se comporta como antes (1 replica, sin `nodeSelector`), que es lo que
usa el k3s de un solo nodo. Para usar la misma topologia en un cluster real, etiquetar los nodos
(`kubectl label node <nodo> gr-app/role=backend` y `gr-app/role=frontend`) y pasar
`-f helm/gr-app/values-2nodos.yaml` a `helm upgrade`.

## Uso

```bash
cd gr-infra/local
cp .env.example .env   # completar los secretos
./setup.sh
```

El script: crea el cluster kind (`kind-cluster.yaml`, con los puertos 80/443 mapeados al host),
instala `ingress-nginx`, construye las imágenes de los 16 repos con `docker build` (usando sus
Dockerfiles ya optimizados), las carga al cluster con `kind load docker-image` (no se publican a
ningún registry), crea el namespace `gr-app` y el Secret `gr-app-secrets` desde `.env`, y hace
`helm upgrade --install` con `values-local.yaml`.

Al terminar, agregar a `/etc/hosts` (el script imprime la línea exacta):

```
127.0.0.1 gateway.gr.local common-ui.gr.local admin-ui.gr.local auth-ui.gr.local wall-ui.gr.local booking-ui.gr.local gate-ui.gr.local public-ui.gr.local billing-ui.gr.local
```

Y abrir `http://common-ui.gr.local` (o cualquiera de las otras UIs).

## Verificar

```bash
kubectl get pods -n gr-app
kubectl logs -n gr-app deploy/gateway -f
```

## Repetir tras un cambio de código

Volver a correr `./setup.sh` reconstruye y recarga todas las imágenes y hace `helm upgrade`
sobre el mismo cluster (no hace falta `teardown.sh` entre pruebas).

## Apagar todo

```bash
./teardown.sh
```

Borra el cluster kind completo (namespace, pods, volúmenes locales del cluster). No toca nada del
homelab/k3s real ni del `docker-compose.local.yml`.
