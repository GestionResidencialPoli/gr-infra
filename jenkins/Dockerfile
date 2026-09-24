# syntax=docker/dockerfile:1
#
# Imagen de Jenkins con los plugins de despliegue y el cliente de Docker
# instalados de forma reproducible (nada de clicks en la UI). El pipeline
# corre dentro de este contenedor y controla al Docker del host a traves
# del socket montado (Docker-outside-of-Docker) para hacer `docker compose
# pull/up` de los servicios ya construidos.
FROM jenkins/jenkins:lts

USER root

# Cliente de Docker + plugin de compose (sin el daemon, usamos el del host)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Mismo GID que el grupo "docker" del host (ver `getent group docker`), para
# que el usuario jenkins pueda usar /var/run/docker.sock sin correr como root.
RUN groupadd -g 988 docker-host && usermod -aG docker-host jenkins

# kubectl + helm: el deploy real es via Helm contra el k3s del host (el
# docker-cli de arriba queda solo para diagnostico puntual).
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
