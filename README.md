# Idea in docker X11 (CentOS with Java & SCTP support)

_IntelliJ IDEA start for SCTP development on Linux/Docker_

Preinstallation requirements: curl, [Docker](https://www.docker.com/products/docker-desktop/), [XQuartz or other X11](https://www.xquartz.org/) configured as described in [XQuartz.md](XQuartz.md)

To develop an application running using the SCTP protocol, Linux with pre-installed lksctp-tools is required. macOS has no native SCTP support.

This script is designed to simplify development in Java using the SCTP protocol for macOS: IntelliJ IDEA runs in a Linux container and is shown on the macOS desktop.

The suggested script does the following:
* downloads the latest version of IntelliJ IDEA, if there is no local installation
* downloads the latest versions of Maven 3 and Gradle and the JDK API documentation
* verifies the published checksums of the downloads
* builds the docker image from the [Dockerfile](Dockerfile) when it is missing or its inputs have changed
* creates the container and launches IntelliJ IDEA on the XQuartz display

The base image is _quay.io/centos/centos:stream10_. The image adds lksctp-tools, a JDK (21 by default), git, sudo, xauth, libXtst and xterm. IntelliJ IDEA, Maven and Gradle stay on the host and are mounted into the container.

## Usage

```bash
./idea.sh            # the newest local installation, IU wins over IC with the same build
./idea.sh iu         # the newest local IU installation
./idea.sh ic         # the newest local IC installation (IC is no longer distributed)
./idea.sh --dry-run  # show what would be downloaded and which docker commands would run
./idea.sh --rebuild  # rebuild the image without cache to pick up package updates
```

Since 2025.3 JetBrains ships a single IntelliJ IDEA distribution (Ultimate features are unlocked with a subscription), which unpacks into `idea-IU-<build>`. The latest release is downloaded only when there is no suitable local installation. An existing container is started with the installation it was created with.

## Settings

Settings are environment variables. The `IDEA_` prefix keeps host variables such as `MAVEN_VERSION` or `GRADLE_VERSION` out, and the former names (`PROJECTS_PATH`, `MAVEN_VERSION`, `DOCKER_IMAGE_NAME`, …) are no longer read.

| Variable | Default | Meaning |
|---|---|---|
| `IDEA_PROJECTS_PATH` | `./IdeaProjects` | host directory mounted as `~/IdeaProjects` |
| `IDEA_RELEASE` | | pinned IntelliJ IDEA release `<version>@<build>`, e.g. `2025.2@252.23892.409` |
| `IDEA_DEFAULT_CODE` | `IU` | edition when there is no local installation |
| `IDEA_MAVEN_VERSION` | latest 3.x | Maven version |
| `IDEA_GRADLE_VERSION` | latest release | Gradle version, `none` to skip Gradle, or a nightly build such as `9.10.0-20261030002218+0000` |
| `IDEA_JDK_VERSION` | `21` | JDK in the image (`java-<version>-openjdk-devel`): 21 or 25 on CentOS Stream 10, 17 needs the Stream 9 base image; the documentation is downloaded for 17 and 21 |
| `IDEA_BASE_IMAGE` | `quay.io/centos/centos:stream10` | base image |
| `IDEA_IMAGE` | `idea:latest` | image name |
| `IDEA_USER` | `idea` | container user; it gets the host UID and GID and passwordless sudo |
| `IDEA_CONTAINER` | `idea-<edition>` | container name |
| `IDEA_HOSTNAME` | `intellij-idea-<edition>` | container hostname |
| `IDEA_DISPLAY` | `host.docker.internal:0` | X display of the container (`$DISPLAY` on Linux) |
| `IDEA_PORTS` | | published ports, e.g. `"8080:8080 5005:5005"` |
| `IDEA_GITCONFIG` | `~/.gitconfig` | git configuration mounted read-only; empty to disable |
| `IDEA_DOCKER_OPTIONS` | | extra options of `docker create` |

## Container

| Container | Host |
|---|---|
| **/opt/idea** | the local directory with IntelliJ IDEA (`idea-IU-<build>` or `idea-IC-<build>`) |
| **/opt/maven** | the local directory with Maven (`apache-maven-<version>`) |
| **/opt/gradle** | the local directory with Gradle (`gradle-<version>`) |
| **~/IdeaProjects** | `IDEA_PROJECTS_PATH` |
| **~/.m2** | `~/.m2` |
| **~/docs** | `docs` with the JDK API documentation |
| **~** | the docker volume `<container>-home`: IDE settings, plugins, caches, `~/.gradle`, `~/.jdks` |

The entry point launches IntelliJ IDEA; `docker stop` shuts it down gracefully. The X server is accessed with the XQuartz cookie, so the `xhost` access control stays enabled. Docker Desktop forwards the SSH agent of macOS (the launchd one) into the container.

## Updating IntelliJ IDEA

The IDE settings live in the home volume, so the container can be recreated:

```bash
docker rm idea-IU            # the volume idea-IU-home is kept
rm -rf idea-IU-<old build>   # or pin IDEA_RELEASE
./idea.sh iu
```

[Script run example](https://youtu.be/NNeN_NgXZkg)

[IDEA on Linux in Docker & X11 build example](https://youtu.be/eixzvCB1tlw)

[XQuartz preferences](XQuartz.md)
