# Idea in docker X11 (CentOS with Java & SCTP support)

_IntelliJ IDEA start for SCTP development on Linux/Docker_

Preinstallation requirements: wget, curl, [Docker](https://www.docker.com/products/docker-desktop/), [XQuartz or other X11](https://www.xquartz.org/)

To develop an application running using the SCTP protocol, Linux with pre-installed lksctp-tools is required.

MacOS has got any problem with core SCTP support.

This script is designed to simplify development in Java using the SCTP protocol for MacOS.

The suggested script does the following:
* downloads the latest version of IntelliJ IDEA, if there is no local installation
* downloads the latest version of maven
* downloads the latest version of gradle
* Creates a new docker image with a linked idea
* IntelliJ IDEA is launched in docker to the specified X11 Server

The base image is used: _bellsoft/liberica-openjdk-centos:21.0.2-14_

Next, the following is added to the image:
* git
* lksctp-tools
* xorg-x11-server-Xorg
* xorg-x11-xauth
* xorg-x11-apps
* libXtst
* sudo

Since 2025.3 JetBrains ships a single IntelliJ IDEA distribution (Ultimate features are unlocked with a subscription), which unpacks into `idea-IU-<build>`. The optional parameter selects the edition of the local installation and the container (`idea-IC` or `idea-IU`):

```bash
./idea.sh      # the newest local installation, IU wins over IC with the same build
./idea.sh iu   # the newest local IU installation
./idea.sh ic   # the newest local IC installation (IC is no longer distributed)
```

The latest release is downloaded only when there is no suitable local installation. An existing container is started with the installation it was created with.

the **/opt/idea** folder is bound to the _local directory with idea_

the **/opt/maven** folder is linked to a _local directory with maven_

the **/root/IdeaProjects** folder is linked to the _folder where projects are created_

Entrypoint indicates the launch of Idea

[Script run example](https://youtu.be/NNeN_NgXZkg)

[IDEA on Linux in Docker & X11 build example](https://youtu.be/eixzvCB1tlw)

[XQuartz preferences](XQuarts.md)
