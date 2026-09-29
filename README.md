# gr-infra

Fuente de verdad del despliegue de Gestion Residencial Poli. Este repo no
tiene codigo de aplicacion: define que corre, con que recursos, y como llega
ahi cada nueva version.

## Arquitectura

```
push a main (cualquier repo de servicio)
        |
        v
  GitHub Actions (runner de GitHub)
    - build de la imagen (Dockerfile multietapa de cada repo)
    - push a GHCR: ghcr.io/gestionresidencialpoli/<repo>:latest y :sha-<commit>
      (+ :migrate-latest y :migrate-sha-<commit> si el servicio tiene imagen de migraciones)
    - POST al webhook de Jenkins con { service, tag }
        |
        v
  cloudflared (ci.residencialpoli.online: solo expone /generic-webhook-trigger)
        |
        v
  Jenkins (en el homelab)
    - helm upgrade gr-app --reset-then-reuse-values --set <service>.image.tag=sha-<commit> --wait
        |
        v
  k3s, namespace gr-app (chart helm/gr-app)
```

El homelab **nunca compila nada**. Solo descarga la imagen ya construida y hace
el rollout. El hardware (i5-3450, 3.7 GiB de RAM) no tiene margen para builds de
Maven o pnpm ademas de los servicios.

Jenkins despliega con un ServiceAccount acotado al namespace `gr-app`
(`k8s/jenkins-rbac.yaml`), nunca con cluster-admin.

## Que es publico y que no

Solo el gateway tiene `Ingress` (`api.residencialpoli.online` → cloudflared → Traefik → `gateway:4000`).
Postgres, Redis, RabbitMQ y todos los microservicios son `Service` internos del cluster, sin forma de
alcanzarlos desde afuera.

| Componente | Imagen | Puerto interno | Base de datos |
|---|---|---|---|
| gateway | gr-api-gateway | 4000 | — |
| user-microservice | gr-user-microservice (Java) | 8080 | gr_user_db |
| wall-microservice | gr-wall-microservice (Node) | 4100 | gr_wall_db |
| booking-microservice | gr-booking-microservice (Node) | 4200 | gr_booking_db |
| gate-microservice | gr-gate-microservice (Node) | 4300 | gr_gate_db |
| contact-microservice | gr-contact-microservice (FastAPI) | 4500 | gr_contact_db |
| billing-microservice | gr-billing-microservice (FastAPI) | 4400 | gr_billing_db |
| postgres | postgres:16-alpine | 5432 | una instancia, una base por servicio |
| redis | redis:7-alpine | 6379 | — |
| rabbitmq | rabbitmq:4-alpine | 5672 | — |

## Migraciones

Cada servicio Node publica una imagen `migrate-<tag>` y la corre como **initContainer** de su propio
Deployment. Cada rollout migra antes de arrancar el contenedor de la aplicacion, y si la migracion falla, el
pod no queda listo y Helm (`--wait`) no promueve la version. Las migraciones de Knex usan una tabla de bloqueo,
asi que varias replicas arrancando a la vez no migran dos veces. La imagen de migraciones de booking y gate
crea ademas su base (`gr_booking_db`, `gr_gate_db`) en el mismo Postgres si todavia no existe.

## Secretos: donde vive cada uno

| Secreto | Donde vive | Por que |
|---|---|---|
| Credenciales de build (push a GHCR) | `GITHUB_TOKEN` automatico de Actions | Ya tiene permiso `packages:write` |
| Token del webhook Actions → Jenkins | Secrets de la organizacion (`JENKINS_WEBHOOK_URL`, `JENKINS_WEBHOOK_TOKEN`) + credential `gr-deploy-webhook-token` en Jenkins | Solo sirve para disparar el pipeline, no da acceso a la app |
| `DB_PASSWORD`, `JWT_SECRET`, `INTERNAL_SERVICE_TOKEN`, RabbitMQ, CORS (runtime) | `/home/mateodev/gr-infra/.env` en el servidor (`chmod 600`), cargado como Secret `gr-app-secrets` con `kubectl create secret generic --from-env-file` | Nunca pasan por GitHub ni por el chart; los pods los leen con `secretKeyRef` |

`.env.example` documenta que variables existen, sin valores reales.

## Como agregar un servicio nuevo

1. El repo del servicio necesita un `Dockerfile` multietapa con `HEALTHCHECK` y, si tiene base de datos, un
   target `migrate` que la cree si no existe y aplique sus migraciones.
2. En su `ci.yml`, un job `release` que llame al workflow reusable:
   ```yaml
   release:
     name: Build y desplegar
     needs: [build-and-test, docker-smoke-test]
     if: github.ref == 'refs/heads/main' && github.event_name == 'push'
     permissions:
       contents: read
       packages: write
     uses: GestionResidencialPoli/gr-infra/.github/workflows/build-push.yml@main
     with:
       service-name: gr-nuevo-microservice
       compose-service: nuevo-microservice
       migrate-target: true
     secrets:
       JENKINS_WEBHOOK_URL: ${{ secrets.JENKINS_WEBHOOK_URL }}
       JENKINS_WEBHOOK_TOKEN: ${{ secrets.JENKINS_WEBHOOK_TOKEN }}
   ```
3. En `helm/gr-app`: una plantilla con su Deployment (initContainer `migrate` si aplica) y su Service **sin
   Ingress**, y un bloque en `values.yaml` cuya clave sea exactamente el `compose-service` del paso 2
   (`nuevo-microservice.image.tag`, `resources`, `replicas`).
4. Si el gateway debe exponerlo, registrar sus prefijos en `gr-api-gateway` (`src/routes/service-registry.ts`) y
   pasarle la URL interna en `templates/gateway.yaml`.
5. El `Jenkinsfile` no cambia: es generico y reacciona a cualquier `service` que llegue en el webhook.

## Presupuesto de memoria (servidor con 3.7 GiB de RAM)

| Servicio | Limite |
|---|---|
| postgres | 160Mi |
| redis | 80Mi |
| rabbitmq | 256Mi |
| user-microservice (JVM, `-XX:MaxRAMPercentage=75.0`) | 420Mi |
| wall-microservice | 150Mi |
| booking-microservice | 160Mi |
| gate-microservice | 160Mi |
| gateway | 150Mi |
| **Total de la aplicacion** | **~1.5 GiB** |

A eso se suman el plano de control de k3s (unos 640 MB), Jenkins (limitado a 700m) y cloudflared. Los servicios
nuevos se escribieron en Node en vez de Spring Boot justamente por este presupuesto: cada uno cabe en 160Mi,
frente a los ~420Mi de una JVM.

`docker-compose.yml` es el despliegue anterior a k3s; se conserva como referencia y ya no es el mecanismo activo. El Compose de desarrollo integrado vive en `gr-api-gateway/docker-compose.yml` y añade contacto, finanzas y sus dos frontends sin cambiar la topología de producción.
