# IntelliJ IDEA runtime: CentOS Stream with a JDK, SCTP support and X11 client libraries.
# IDEA, Maven and Gradle are not part of the image, idea.sh mounts them from the host.
ARG BASE_IMAGE=quay.io/centos/centos:stream10
FROM ${BASE_IMAGE}

ARG USER_NAME=idea
ARG USER_UID=1000
ARG USER_GID=1000
ARG JDK_PACKAGE=java-21-openjdk-devel

# The user gets the host UID and GID; an existing group with that GID is reused
RUN dnf -y update \
 && dnf -y install findutils lksctp-tools xorg-x11-xauth libXtst sudo git xterm "${JDK_PACKAGE}" \
 && dnf clean all \
 && if ! getent group "${USER_GID}" > /dev/null; then groupadd -g "${USER_GID}" "${USER_NAME}"; fi \
 && useradd -m -u "${USER_UID}" -g "${USER_GID}" -G wheel "${USER_NAME}" \
 && echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USER_NAME}" \
 && chmod 0440 "/etc/sudoers.d/${USER_NAME}" \
 && echo "export PS1='\[\e[0;33m\]\u\[\e[0m\]@\[\e[0;32m\]\h\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]\\$ '" >> "/home/${USER_NAME}/.bashrc" \
 && echo "export PS1='\[\e[0;32m\]\h\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]# '" >> /root/.bashrc \
 && ln -s /opt/maven/bin/mvn /usr/bin/mvn \
 && ln -s /opt/gradle/bin/gradle /usr/bin/gradle \
 && ln -s /opt/idea/bin/idea.sh /usr/bin/idea

COPY --chmod=0755 entrypoint.sh /opt/entry

USER ${USER_NAME}
ENV LANG=C.UTF-8 \
    MAVEN_HOME=/opt/maven \
    MAVEN_OPTS=-Xms128m
WORKDIR /home/${USER_NAME}
EXPOSE 8080 5005
ENTRYPOINT ["/opt/entry"]
