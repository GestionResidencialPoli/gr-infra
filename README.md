# gr-infra

Fuente de verdad del despliegue de Gestion Residencial Poli. Este repo no
tiene codigo de aplicacion: define que corre, con que recursos, y como llega
ahi cada nueva version.

## Arquitectura

```
push a main (gr-wall-microservice, gr-api-gateway, gr-user-microservice)
        |
        v
  GitHub Actions (runner de GitHub, gratis)
    - build de la imagen (Dockerfile multietapa de cada repo)
    - push a GHCR: ghcr.io/gestionresidencialpoli/<repo>:latest y :sha-<commit>
    - POST al webhook de Jenkins con { service, migrate }
        |
        v
  Jenkins (en el homelab, plugin generic-webhook-trigger)
    - docker compose pull <service>
    - docker compose up -d <service>
```

El homelab **nunca compila nada**. Solo descarga la imagen ya construida y
reinicia el contenedor. Esto es deliberado: el hardware (i5-3450, 3.7 GiB
RAM) no tiene margen para correr builds de Maven/pnpm ademas de los
servicios.

## Por que esta separacion

- **GHCR** en vez de Docker Hub: gratis, ya integrado con el `GITHUB_TOKEN`
  de cada repo, sin credenciales nuevas que gestionar para el build/push.
- **Jenkins solo hace el `pull` + `up`**: es el requisito academico (el
  profesor pide pipelines de Jenkins), pero el trabajo pesado ya lo hizo
  GitHub Actions. Jenkins ejecuta el deploy real, no es cosmetico.
- **Un workflow reusable** (`.github/workflows/build-push.yml`) en vez de
  repetir el build/push en cada repo: agregar un servicio nuevo no implica
  escribir un pipeline desde cero.

## Secretos: donde vive cada uno

| Secreto | Donde vive | Por que |
|---|---|---|
| Credenciales de build (push a GHCR) | `GITHUB_TOKEN` automatico de Actions | No hace falta crear nada, ya tiene permiso `packages:write` |
| Token del webhook Jenkins→GHA | GitHub Actions secrets (`JENKINS_WEBHOOK_URL`, `JENKINS_WEBHOOK_TOKEN`) en cada repo de servicio, + credential `gr-deploy-webhook-token` en Jenkins | Solo sirve para disparar el pipeline, no da acceso a la app |
| `DB_PASSWORD`, `JWT_SECRET`, `INTERNAL_SERVICE_TOKEN`, etc. (runtime) | **Unicamente** en `/home/mateodev/gr-infra/.env` en el servidor, fuera de git, `chmod 600` | El deploy es pull+restart, nunca necesita compilar con esos secretos, asi que nunca tienen que salir del servidor ni pasar por GitHub |

`.env.example` en este repo documenta que variables existen, sin valores
reales. El `.env` real nunca se commitea (ver `.gitignore`).

## Como agregar un servicio nuevo

1. El repo del servicio necesita un `Dockerfile` multietapa (como los que
   ya existen) que exponga un `HEALTHCHECK`.
2. Al final de su `ci.yml`, agregar un job que llame al workflow reusable:
   ```yaml
   release:
     name: Build y desplegar
     needs: build-and-check
     if: github.ref == 'refs/heads/main' && github.event_name == 'push'
     uses: GestionResidencialPoli/gr-infra/.github/workflows/build-push.yml@main
     with:
       service-name: gr-nuevo-servicio
       compose-service: nuevo-servicio
       migrate-target: false
     secrets:
       JENKINS_WEBHOOK_URL: ${{ secrets.JENKINS_WEBHOOK_URL }}
       JENKINS_WEBHOOK_TOKEN: ${{ secrets.JENKINS_WEBHOOK_TOKEN }}
   ```
3. Agregar el bloque del servicio a `docker-compose.yml` en este repo (imagen
   `ghcr.io/gestionresidencialpoli/gr-nuevo-servicio:latest`, `mem_limit`,
   variables de entorno, `depends_on`).
4. Agregar sus variables nuevas (si tiene secretos propios) a `.env.example`
   aqui y al `.env` real del servidor.
5. Listo. El `Jenkinsfile` no cambia — es generico, reacciona a cualquier
   `service` que llegue en el payload del webhook.

## Presupuesto de memoria (servidor con 3.7 GiB RAM)

| Servicio | `mem_limit` |
|---|---|
| postgres | 160m |
| redis | 80m |
| rabbitmq | 256m |
| user-microservice (JVM, `-XX:MaxRAMPercentage=75.0`) | 420m |
| wall-microservice | 150m |
| gateway | 150m |
| **Total en estado estable** | **~1.2 GiB** |

Deja margen sobre los ~2.2 GiB disponibles en el servidor incluso con
Jenkins, cloudflared y el resto de servicios existentes corriendo.
