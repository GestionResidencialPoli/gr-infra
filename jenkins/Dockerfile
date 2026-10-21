# syntax=docker/dockerfile:1
#
# Imagen de Jenkins con los plugins de despliegue, kubectl y helm instalados de
# forma reproducible (nada de clicks en la UI). Todo el estado (usuario admin,
# credential del webhook y el job gr-deploy) se declara en casc.yaml y se
# alimenta con variables de entorno en tiempo de ejecucion.
FROM jenkins/jenkins:lts

USER root

# kubectl + helm: el deploy es via Helm contra el k3s del host.
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

USER jenkins

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
