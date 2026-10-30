# Idea in docker X11 (CentOS with Java & SCTP support)

_IntelliJ IDEA start for SCTP development on Linux/Docker_

Preinstallation requirements: curl, [Docker](https://www.docker.com/products/docker-desktop/), [XQuartz or other X11](https://www.xquartz.org/) configured as described in [XQuartz.md](XQuartz.md)

To develop an application running using the SCTP protocol, Linux with pre-installed lksctp-tools is required. macOS has no native SCTP support.

This script is designed to simplify development in Java using the SCTP protocol for macOS: IntelliJ IDEA runs in a Linux container and is shown on the macOS desktop.

Changes are listed in the [releases](https://github.com/sftwnd/idea-docker-X11/releases).

The suggested script does the following:
* downloads the latest version of IntelliJ IDEA, if there is no local installation
* downloads the latest versions of Maven 3 and Gradle and the JDK API documentation
* verifies the published checksums of the downloads
* builds the docker image from the [Dockerfile](Dockerfile) when it is missing or its inputs have changed
* creates the container and launches IntelliJ IDEA on the XQuartz display

The base image is _quay.io/centos/centos:stream10_. The image adds lksctp-tools, iproute and procps-ng (`ss`, `ip`, `sysctl`), a JDK (25 by default), git, sudo, xauth, libXtst and xterm. IntelliJ IDEA, Maven and Gradle stay on the host and are mounted into the container.

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
| `IDEA_JDK_VERSION` | `25` | JDK in the image (`java-<version>-openjdk-devel`): 21 or 25 on CentOS Stream 10, 17 needs the Stream 9 base image; the documentation is downloaded for 17, 21 and 25 |
| `IDEA_BASE_IMAGE` | `quay.io/centos/centos:stream10` | base image |
| `IDEA_IMAGE` | `idea:latest` | image name |
| `IDEA_USER` | `idea` | container user; it gets the host UID and GID and passwordless sudo |
| `IDEA_CONTAINER` | `idea-<edition>` | container name |
| `IDEA_HOSTNAME` | `intellij-idea-<edition>` | container hostname |
| `IDEA_DISPLAY` | `host.docker.internal:0` | X display of the container (`$DISPLAY` on Linux) |
| `IDEA_PORTS` | | published ports, e.g. `"8080:8080 5005:5005"` |
| `IDEA_GITCONFIG` | `~/.gitconfig` | host git configuration included into the container one; empty to disable |
| `IDEA_PRIVILEGED` | `true` | `true` or `false`: create the container with `--privileged`, see [SCTP settings](#sctp-settings) |
| `IDEA_SCTP_AUTH_ENABLE` | `1` | `net.sctp.auth_enable` of the container: SCTP authentication ([RFC 4895](https://www.rfc-editor.org/rfc/rfc4895)); empty to keep the kernel default |
| `IDEA_SCTP_UDP_PORT` | | `net.sctp.udp_port`: the UDP port to receive SCTP over UDP ([RFC 6951](https://www.rfc-editor.org/rfc/rfc6951)) on, e.g. `9899`; not set by default |
| `IDEA_SCTP_ENCAP_PORT` | | `net.sctp.encap_port`: the UDP port to send SCTP over UDP to, e.g. `9899`; not set by default |
| `IDEA_DOCKER_OPTIONS` | | extra options of `docker create`, passed after the options above |

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
| **~/.gitconfig-host** | `IDEA_GITCONFIG`, read-only |

The entry point launches IntelliJ IDEA; `docker stop` shuts it down gracefully. The X server is accessed with the XQuartz cookie, so the `xhost` access control stays enabled. Docker Desktop forwards the SSH agent of macOS (the launchd one) into the container. On the first start the container gets `~/.gitconfig`, which includes the host configuration and replaces its credential helpers (macOS programs such as osxkeychain) with the git credential cache.

## SCTP settings

`IDEA_PRIVILEGED` and the `IDEA_SCTP_*` settings become options of `docker create`: `--privileged` and `--sysctl net.sctp.<name>=<value>`.

* `net.sctp.*` are kernel parameters of the network namespace of the container, which Docker sets when it creates the container, so they work without `--privileged` too.
* SCTP over UDP is off until the ports are set. Uncomment `IDEA_SCTP_UDP_PORT` and `IDEA_SCTP_ENCAP_PORT` in the settings of `idea.sh`, or export them: `IDEA_SCTP_UDP_PORT=9899 IDEA_SCTP_ENCAP_PORT=9899 ./idea.sh`. Once `encap_port` is set, new associations send their packets to that UDP port, so the peer must listen on it, and an application in the container that talks to itself needs `udp_port` equal to `encap_port`; otherwise the association is never established.
* `--privileged` lets you change the parameters inside the container (`sudo sysctl -w net.sctp.hb_interval=5000`) and create network namespaces (`sudo ip netns add peer`) to test multihoming. It also gives the container root-level access to the Docker VM, where the projects, `~/.m2` and the SSH agent are mounted. With `IDEA_PRIVILEGED=false` SCTP, authentication and the parameters above keep working, but `sysctl -w` and `ip netns` do not.
* The options are fixed when the container is created, and so is its image. `idea.sh` warns when an existing container differs from the settings; recreate it, the home volume is kept: `docker rm idea-IU && ./idea.sh iu`.

## Checking SCTP

```bash
docker exec idea-IU checksctp   # SCTP supported
docker exec idea-IU sysctl net.sctp.auth_enable net.sctp.udp_port net.sctp.encap_port
```

## Tests

```bash
tests/options.sh   # the docker options built from the settings, with idea.sh --dry-run; builds and starts nothing
tests/sctp.sh      # builds the image and checks SCTP in it: privileged and unprivileged containers, JDK, a loopback association
```

`tests/sctp.sh <image>` checks an existing image instead of building one, and `IDEA_JDK_VERSION` is the JDK it expects (25 by default). Docker is required, and no IDEA container may be running for `tests/options.sh`.

## Updating IntelliJ IDEA

The IDE settings live in the home volume, so the container can be recreated:

```bash
docker rm idea-IU            # the volume idea-IU-home is kept
rm -rf idea-IU-<old build>   # or pin IDEA_RELEASE
./idea.sh iu
```

## Upgrading from earlier versions

Settings are `IDEA_*` variables now:

| Before | Now |
|---|---|
| `PROJECTS_PATH` | `IDEA_PROJECTS_PATH` |
| `MAVEN_VERSION` | `IDEA_MAVEN_VERSION` |
| `GRADLE_VERSION`, `GRADLE_BUILD` | `IDEA_GRADLE_VERSION` (`<version>-<build>` for a nightly build) |
| `IDEA_VERSION`, `IDEA_BUILD` | `IDEA_RELEASE` (`<version>@<build>`) |
| `DEFAULT_IDEA_CODE` | `IDEA_DEFAULT_CODE` |
| `DOCKER_IMAGE_NAME`, `DOCKER_IMAGE_VERSION` | `IDEA_IMAGE` (`<name>:<tag>`) |
| `DOCKER_CONTAINER_NAME` | `IDEA_CONTAINER` |
| `DOCKER_CONTAINER_HOSTNAME` | `IDEA_HOSTNAME` |
| `DISPLAY_HOST`, `DISPLAY_ID` (edited in the script) | `IDEA_DISPLAY` |

* The image is built from the committed [Dockerfile](Dockerfile), which replaces the generated one, so `idea:latest` is rebuilt once when a new container is created.
* `xhost +` is no longer used. XQuartz needs **Authenticate connections**, see [XQuartz.md](XQuartz.md).
* An existing container is started as before and gets the XQuartz cookie, but its home directory is not a volume. To keep the IDE settings, copy the home directory into the volume before recreating the container:

  ```bash
  docker cp idea-IU:/home/idea/. - | docker run --rm -i --user 0 -v idea-IU-home:/home/idea --entrypoint tar idea:latest -xf - -C /home/idea
  docker rm idea-IU
  ./idea.sh iu
  ```

## Troubleshooting

* **Can't connect to X11 window server.** XQuartz creates a new cookie on every start, and `idea.sh` copies the current one into the container. Start the container with `./idea.sh` rather than `docker start`. If the host name changed after XQuartz started, restart XQuartz. Check the security options in [XQuartz.md](XQuartz.md).
* **IntelliJ IDEA is already running.** The container is running. Stop it with `docker stop idea-IU`.
* **SSH keys are missing in the container.** Docker Desktop forwards only the macOS launchd agent. Load the keys into it with `SSH_AUTH_SOCK=$(launchctl getenv SSH_AUTH_SOCK) ssh-add ~/.ssh/<key>`.
* **What will happen?** `./idea.sh --dry-run` shows the selected installation, the downloads and the docker commands without changing anything.

[Script run example](https://youtu.be/NNeN_NgXZkg) (earlier version of the script)

[IDEA on Linux in Docker & X11 build example](https://youtu.be/eixzvCB1tlw) (earlier version of the script)

[XQuartz preferences](XQuartz.md)
