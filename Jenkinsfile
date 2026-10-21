// Pipeline de despliegue, generico para todos los servicios.
// No hay que tocar este archivo al agregar un servicio nuevo: el nombre
// del servicio (clave usada en values.yaml del chart de Helm) y el tag de
// la imagen llegan en el payload del webhook que dispara GitHub Actions al
// terminar de publicar la imagen en GHCR.
//
// El job se define en jenkins/casc.yaml y hace checkout de este mismo repo,
// asi que el chart que se despliega es siempre el de main (WORKSPACE), sin
// depender de una copia local en el servidor.
pipeline {
    agent any

    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'SERVICE', value: '$.service'],
                [key: 'TAG', value: '$.tag']
            ],
            tokenCredentialId: 'gr-deploy-webhook-token',
            causeString: 'Disparado por GitHub Actions para $SERVICE',
            printContributedVariables: false,
            printPostContent: false
        )
    }

    environment {
        NAMESPACE = 'gr-app'
        // Montado por host/jenkins/docker-compose.yml (ServiceAccount acotado a gr-app).
        KUBECONFIG = '/var/jenkins_home/.kube/jenkins-config'
    }

    stages {
        // La primera ejecucion (sin payload) solo sirve para que Jenkins registre
        // el trigger del webhook; no despliega nada.
        stage('Desplegar') {
            when { expression { env.SERVICE?.trim() && env.TAG?.trim() } }
            steps {
                sh '''
                    # Las UIs viven bajo uis.services.<nombre>; el resto bajo <nombre>.
                    case "$SERVICE" in
                        *-ui) KEY="uis.services.${SERVICE}.image.tag" ;;
                        *)    KEY="${SERVICE}.image.tag" ;;
                    esac
                    helm upgrade gr-app helm/gr-app -n "$NAMESPACE" --install \
                        --reset-then-reuse-values \
                        -f helm/gr-app/values-prod.yaml \
                        --set "${KEY}=sha-${TAG}" \
                        --wait --timeout 300s
                '''
            }
        }
    }

    post {
        failure {
            echo "Fallo el despliegue de ${env.SERVICE}. Helm no promueve un rollout que no pasa el readiness/liveness, asi que la version anterior sigue corriendo."
        }
    }
}
