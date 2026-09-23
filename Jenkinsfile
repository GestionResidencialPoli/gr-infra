// Pipeline de despliegue, generico para todos los servicios.
// No hay que tocar este archivo al agregar un servicio nuevo: el nombre
// del servicio (que debe coincidir con la clave del docker-compose.yml)
// llega en el payload del webhook que dispara GitHub Actions al terminar
// de publicar la imagen en GHCR.
pipeline {
    agent any

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'SERVICE', value: '$.service'],
                [key: 'MIGRATE', value: '$.migrate']
            ],
            tokenCredentialId: 'gr-deploy-webhook-token',
            causeString: 'Disparado por GitHub Actions para $SERVICE',
            printContributedVariables: false,
            printPostContent: false
        )
    }

    environment {
        COMPOSE_FILE = '/home/mateodev/gr-infra/docker-compose.yml'
        ENV_FILE = '/home/mateodev/gr-infra/.env'
    }

    stages {
        stage('Migraciones') {
            when { expression { env.MIGRATE == 'true' } }
            steps {
                sh 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull "${SERVICE}-migrate"'
                sh 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up "${SERVICE}-migrate"'
            }
        }

        stage('Desplegar') {
            steps {
                sh 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull "$SERVICE"'
                sh 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$SERVICE" --remove-orphans'
            }
        }
    }

    post {
        failure {
            echo "Fallo el despliegue de ${env.SERVICE}. La version anterior sigue corriendo (docker compose no detiene un contenedor sano si el pull falla)."
        }
    }
}
