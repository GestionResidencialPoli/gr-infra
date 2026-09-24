// Pipeline de despliegue, generico para todos los servicios.
// No hay que tocar este archivo al agregar un servicio nuevo: el nombre
// del servicio (clave usada en values.yaml del chart de Helm) y el tag de
// la imagen llegan en el payload del webhook que dispara GitHub Actions al
// terminar de publicar la imagen en GHCR.
pipeline {
    agent any

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'SERVICE', value: '$.service'],
                [key: 'TAG', value: '$.tag'],
                [key: 'MIGRATE', value: '$.migrate']
            ],
            tokenCredentialId: 'gr-deploy-webhook-token',
            causeString: 'Disparado por GitHub Actions para $SERVICE',
            printContributedVariables: false,
            printPostContent: false
        )
    }

    environment {
        CHART_DIR = '/home/mateodev/gr-infra/helm/gr-app'
        NAMESPACE = 'gr-app'
        KUBECONFIG = '/home/mateodev/.kube/jenkins-config'
    }

    stages {
        stage('Migraciones') {
            when { expression { env.MIGRATE == 'true' } }
            steps {
                sh 'kubectl delete job wall-migrate -n "$NAMESPACE" --ignore-not-found'
                sh 'helm upgrade gr-app "$CHART_DIR" -n "$NAMESPACE" --reuse-values --set wallMigrate.image.tag=sha-${TAG}'
                sh 'kubectl wait --for=condition=complete job/wall-migrate -n "$NAMESPACE" --timeout=180s'
            }
        }

        stage('Desplegar') {
            steps {
                sh 'helm upgrade gr-app "$CHART_DIR" -n "$NAMESPACE" --install --reuse-values --set ${SERVICE}.image.tag=sha-${TAG} --wait --timeout 180s'
            }
        }
    }

    post {
        failure {
            echo "Fallo el despliegue de ${env.SERVICE}. Helm no promueve un rollout que no pasa el readiness/liveness, asi que la version anterior sigue corriendo."
        }
    }
}
