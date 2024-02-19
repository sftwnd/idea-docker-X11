# Idea in docker X11 (CentOS with SCTP support)

_IntelliJ IDEA start for SCTP development on Linux/Docker_

Preinstallation required: [Docker](https://www.docker.com/products/docker-desktop/), [XQuartz or other X11](https://www.xquartz.org/)

To develop an application running using the SCTP protocol, Linux with pre-installed lksctp-tools is required.

MacOS has got any problem with core SCTP support.

This script is designed to simplify development in Java using the SCTP protocol for MacOS.

The suggested script does the following:
* downloads the latest version of IntelliJ IDEA
* downloads the latest version of maven
* Creates a new docker image with a linked idea
* At startup, IntelliJ IDEA is launched on the specified X11 Server

The base image is used: _bellsoft/liberica-openjdk-centos:21.0.2-14_

Next, the following is added to the image:
* install
* lksctp-tools
* xorg-x11-server-Xorg
* xorg-x11-xauth
* xorg-x11-apps
* libXtst

If you have a license for IntelliJ IDEA Ultimate, then you can run the script with the IU parameter. In this case, IntelliJ IDEA Ultimate version will be used

```bash
./idea.sh iu
```

the **/opt/idea** folder is bound to the _local directory with idea_

the **/opt/maven** folder is linked to a _local directory with maven_

the **/root/IdeaProjects** folder is linked to the _folder where projects are created_

Entrypoint indicates the launch of Idea

[Script run example](https://youtu.be/NNeN_NgXZkg)

[IDEA on Linux in Docker & X11 build example](https://youtu.be/eixzvCB1tlw)

[XQuartz preferences](XQuarts.md)
