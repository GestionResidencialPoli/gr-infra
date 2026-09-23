# syntax=docker/dockerfile:1
#
# Imagen de Jenkins con los plugins de despliegue instalados de forma
# reproducible (nada de clicks en la UI). Se reconstruye solo si cambia
# plugins.txt.
FROM jenkins/jenkins:lts

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
