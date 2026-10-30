#!/bin/bash
#
# Runs IntelliJ IDEA in a Docker container and shows it on the host X server (XQuartz on macOS).
# IDEA, Maven, Gradle and the JDK documentation are downloaded next to this script and mounted
# into the container. Settings are IDEA_* environment variables, see README.md.
#
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat << 'EOF'
Usage: ./idea.sh [ic|iu] [-n|--dry-run] [--rebuild] [-h|--help]

  ic, iu         edition of the local IDEA installation and of the container (idea-IC / idea-IU);
                 without it the newest local installation is used, IU wins over IC with the same build
  -n, --dry-run  show what would be downloaded and which docker commands would run
  --rebuild      rebuild the image without cache to pick up base image and package updates
  -h, --help     show this help

Settings are IDEA_* environment variables, see README.md.
EOF
}

log() {
  echo "$*"
}

warn() {
  echo "WARNING: $*" >&2
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

EDITION=
DRY_RUN=0
REBUILD=0
for ARG in "$@"; do
  case "$ARG" in
    [iI][cC]) EDITION=IC ;;
    [iI][uU]) EDITION=IU ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --rebuild) REBUILD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $ARG" ;;
  esac
done

# Settings. The IDEA_ prefix keeps host variables such as MAVEN_VERSION or GRADLE_VERSION out.
: "${IDEA_PROJECTS_PATH:=./IdeaProjects}"
: "${IDEA_RELEASE:=}"                    # pinned IDEA release <version>@<build>, e.g. 2025.2@252.23892.409
: "${IDEA_DEFAULT_CODE:=IU}"             # edition when there is no local installation
: "${IDEA_MAVEN_VERSION:=}"              # latest Maven 3 if empty
: "${IDEA_GRADLE_VERSION:=}"             # latest release if empty, "none" to skip, or a nightly build
: "${IDEA_JDK_VERSION:=21}"
: "${IDEA_BASE_IMAGE:=quay.io/centos/centos:stream10}"
: "${IDEA_IMAGE:=idea:latest}"
: "${IDEA_USER:=idea}"
: "${IDEA_CONTAINER:=}"                  # idea-<edition> if empty
: "${IDEA_HOSTNAME:=}"                   # intellij-idea-<edition> if empty
: "${IDEA_DISPLAY:=}"                    # host.docker.internal:0 on macOS, $DISPLAY on Linux
: "${IDEA_PORTS:=}"                      # published ports, e.g. "8080:8080 5005:5005"
: "${IDEA_GITCONFIG:=$HOME/.gitconfig}"  # included into the container git configuration, empty to disable
: "${IDEA_DOCKER_OPTIONS:=}"             # extra options of docker create

for LEGACY in PROJECTS_PATH DEFAULT_IDEA_CODE IDEA_VERSION IDEA_BUILD DOCKER_IMAGE_NAME DOCKER_IMAGE_VERSION \
              DOCKER_CONTAINER_NAME DOCKER_CONTAINER_HOSTNAME; do
  if [ -n "$(eval echo "\${$LEGACY:-}")" ]; then
    warn "$LEGACY is no longer used, see the IDEA_* settings in README.md"
  fi
done
case "$IDEA_DEFAULT_CODE" in
  IC|IU) ;;
  *) die "IDEA_DEFAULT_CODE must be IC or IU" ;;
esac
case "$IDEA_RELEASE" in
  ""|[0-9]*@[0-9]*) ;;
  *) die "IDEA_RELEASE must be <version>@<build>, e.g. 2025.2@252.23892.409" ;;
esac

for TOOL in docker curl tar unzip; do
  command -v "$TOOL" > /dev/null || die "$TOOL is required"
done
DOCKER_INFO="$(docker info --format '{{.Architecture}} {{.OperatingSystem}}' 2> /dev/null)" || die "Docker is not running"
DOCKER_ARCH="${DOCKER_INFO%% *}"
DOCKER_OS="${DOCKER_INFO#* }"

if [ "$(uname -s)" == Darwin ]; then
  : "${IDEA_DISPLAY:=host.docker.internal:0}"
else
  : "${IDEA_DISPLAY:=${DISPLAY:-:0}}"
fi

# Runs a command, or only prints it in dry-run mode
run() {
  if [ "$DRY_RUN" == 1 ]; then
    printf '+' >&2
    printf ' %q' "$@" >&2
    echo >&2
  else
    "$@"
  fi
}

# sha <bits> [<file>]: hex digest of the file or of stdin
sha() {
  if command -v shasum > /dev/null; then
    shasum -a "$1" ${2:+"$2"} | cut -d' ' -f1
  else
    "sha${1}sum" ${2:+"$2"} | cut -d' ' -f1
  fi
}

# json_field <name> <json>: the first string value of the field
json_field() {
  echo "$2" | grep -oE "\"$1\" *: *\"[^\"]*\"" | sed -n '1s/.*: *"\(.*\)"$/\1/p' || true
}

# Newest local IDEA installation of the given editions (IU wins over IC with the same build)
latest_idea_home() {
  for IDEA_HOME_CODE in "$@"; do
    for IDEA_HOME in idea-"$IDEA_HOME_CODE"-*; do
      if [ -f "$IDEA_HOME/bin/idea.sh" ]; then
        echo "$IDEA_HOME"
      fi
    done
  done | sed -E 's/^idea-(I[CU])-(.*)$/\2 \1 &/' | sort -V | tail -n1 | cut -d' ' -f3
}

# Since 2025.3 JetBrains ships a single unified distribution: idea-<version>.tar.gz unpacks into idea-IU-<build>
unified() {
  [ "$(printf '%s\n' 2025.3 "$1" | sort -V | sed -n 1p)" == "2025.3" ]
}

# download <url> <file>: downloads into <file>.part, so that an interrupted download is not taken for a complete one
download() {
  log "Download $1"
  if curl -fL --retry 3 --progress-bar -o "$2.part" "$1"; then
    mv "$2.part" "$2"
  else
    rm -f "$2.part"
    return 1
  fi
}

# verify <file> <checksum url> <bits>: compares the file with the published checksum
verify() {
  local expected
  expected="$(curl -fsSL --retry 3 "$2" | awk 'NR == 1 { print $1 }')" || return 1
  [ -n "$expected" ] && [ "$(sha "$3" "$1")" == "$expected" ]
}

# install_dist <dir> <marker> <url> <checksum url> <bits>: downloads, verifies and unpacks a distribution into <dir>
install_dist() {
  local dir="$1" marker="$2" url="$3" checksum_url="$4" bits="$5" file top
  file="$(basename "$url")"
  if [ -f "$dir/$marker" ]; then
    log "Use $dir"
    return
  fi
  if [ "$DRY_RUN" == 1 ]; then
    log "Would download $url into $dir"
    return
  fi
  if [ -e "$dir" ]; then
    warn "$dir is incomplete (no $marker), installing it again"
    rm -rf "$dir"
  fi
  if [ -f "$file" ] && verify "$file" "$checksum_url" "$bits"; then
    log "Use the downloaded $file"
  else
    download "$url" "$file" || die "unable to download $url"
    verify "$file" "$checksum_url" "$bits" || { rm -f "$file"; die "checksum mismatch for $file"; }
  fi
  log "Unpack $file"
  rm -rf "$dir.tmp"
  mkdir "$dir.tmp"
  case "$file" in
    *.zip) unzip -q "$file" -d "$dir.tmp" ;;
    *) tar -xzf "$file" -C "$dir.tmp" ;;
  esac || { rm -rf "$dir.tmp"; die "unable to unpack $file"; }
  # The archives have a single top-level directory, whatever its name is
  top="$(find "$dir.tmp" -mindepth 1 -maxdepth 1)"
  if [ ! -d "$top" ] || [ ! -f "$top/$marker" ]; then
    rm -rf "$dir.tmp"
    die "$file has no single top-level directory with $marker"
  fi
  mv "$top" "$dir"
  rm -rf "$dir.tmp" "$file"
}

# Writes the X authority cookie of the display with the address family "wild", which the X server accepts
# from the container. Without a cookie, local connections are allowed with xhost instead.
prepare_xauth() {
  local number="${IDEA_DISPLAY##*:}"
  number="${number%%.*}"
  if [ "$DRY_RUN" == 1 ]; then
    log "Would export the X authority cookie of display :$number into $XAUTH_FILE"
    return 0
  fi
  # Any request starts XQuartz on macOS, and XQuartz renews the cookie on start
  xhost > /dev/null 2>&1 || warn "the X server is not available, start XQuartz"
  mkdir -p "${XAUTH_FILE%/*}"
  chmod 700 "${XAUTH_FILE%/*}"
  rm -f "$XAUTH_FILE"
  if command -v xauth > /dev/null \
     && xauth nlist ":$number" 2> /dev/null | sed -e 's/^..../ffff/' | xauth -f "$XAUTH_FILE" nmerge - 2> /dev/null \
     && [ -s "$XAUTH_FILE" ]; then
    chmod 600 "$XAUTH_FILE"
    return 0
  fi
  rm -f "$XAUTH_FILE"
  warn "no X authority cookie for display :$number, allowing local connections with 'xhost +localhost'"
  warn "enable 'Authenticate connections' in the XQuartz settings to use the cookie instead"
  xhost +localhost > /dev/null 2>&1 || warn "xhost +localhost failed"
  return 1
}

# Where an existing container reads the X authority from: $XAUTHORITY, or ~/.Xauthority in older containers
container_xauth_target() {
  local target
  target="$(docker container inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$IDEA_CONTAINER" \
            | sed -n 's/^XAUTHORITY=//p')"
  if [ -z "$target" ]; then
    target="$(docker container inspect --format '{{.Config.WorkingDir}}' "$IDEA_CONTAINER")/.Xauthority"
  fi
  echo "$target"
}

# start_container <X authority path in the container>: starts the container with the current cookie
start_container() {
  if prepare_xauth; then
    run docker cp -a "$XAUTH_FILE" "$IDEA_CONTAINER:$1"
  fi
  run docker start "$IDEA_CONTAINER" > /dev/null
  log "IntelliJ IDEA is starting in the container $IDEA_CONTAINER"
}

# Without an argument the edition of the newest local installation is used
if [ -z "$EDITION" ]; then
  EDITION="$(latest_idea_home IC IU | sed -E 's/^idea-(I[CU])-.*$/\1/')"
fi
: "${EDITION:=$IDEA_DEFAULT_CODE}"
: "${IDEA_CONTAINER:=idea-$EDITION}"
: "${IDEA_HOSTNAME:=intellij-idea-$(echo "$EDITION" | tr '[:upper:]' '[:lower:]')}"
USER_HOME="/home/$IDEA_USER"
XAUTH_FILE="$PWD/.xauth/Xauthority"
XAUTH_TARGET=/tmp/.idea-xauth

# Running IDEA containers: by image and by name, because containers created
# from a previous build of the image are not matched by the ancestor filter
RUNNING_CONTAINERS="$({
  docker ps --filter "ancestor=$IDEA_IMAGE" --format "{{.Names}}"
  docker ps --filter "name=^idea-I[CU]$" --filter "name=^$IDEA_CONTAINER$" --format "{{.Names}}"
} | sort -u | xargs)"
if [ -n "$RUNNING_CONTAINERS" ]; then
  die "IntelliJ IDEA is already running: $RUNNING_CONTAINERS"
fi

if docker container inspect "$IDEA_CONTAINER" > /dev/null 2>&1; then
  if [ "$REBUILD" == 1 ]; then
    warn "--rebuild does not change the existing container $IDEA_CONTAINER, remove it to create a new one"
  fi
  log "Start the existing container $IDEA_CONTAINER"
  start_container "$(container_xauth_target)"
  exit 0
fi

# Maven
MAVEN_VERSION="$IDEA_MAVEN_VERSION"
if [ -z "$MAVEN_VERSION" ]; then
  MAVEN_VERSION="$(curl -fsSL --retry 3 https://archive.apache.org/dist/maven/maven-3/ \
                   | sed -nE 's/.*href="([0-9]+\.[0-9]+\.[0-9]+)\/".*/\1/p' | sort -V | tail -n1 || true)"
  [ -n "$MAVEN_VERSION" ] || die "unable to detect the latest Maven version"
fi
MAVEN_HOME="apache-maven-$MAVEN_VERSION"
MAVEN_URL="https://archive.apache.org/dist/maven/maven-${MAVEN_VERSION%%.*}/$MAVEN_VERSION/binaries/$MAVEN_HOME-bin.tar.gz"
log "Maven $MAVEN_VERSION"
install_dist "$MAVEN_HOME" bin/mvn "$MAVEN_URL" "$MAVEN_URL.sha512" 512

# Gradle: a release, or a nightly build from distributions-snapshots if requested explicitly
GRADLE_HOME=
if [ "$IDEA_GRADLE_VERSION" != none ]; then
  GRADLE_VERSION="$IDEA_GRADLE_VERSION"
  if [ -z "$GRADLE_VERSION" ]; then
    GRADLE_VERSION="$(json_field version "$(curl -fsSL --retry 3 https://services.gradle.org/versions/current || true)")"
    [ -n "$GRADLE_VERSION" ] || die "unable to detect the latest Gradle release"
  fi
  case "$GRADLE_VERSION" in
    *+*) GRADLE_URL="https://services.gradle.org/distributions-snapshots/gradle-$GRADLE_VERSION-bin.zip" ;;
    *) GRADLE_URL="https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" ;;
  esac
  GRADLE_HOME="gradle-$GRADLE_VERSION"
  log "Gradle $GRADLE_VERSION"
  install_dist "$GRADLE_HOME" bin/gradle "$GRADLE_URL" "$GRADLE_URL.sha256" 256
fi

# JDK: the package in the image and its API documentation (only 17 and 21 are downloadable without an Oracle account)
case "$IDEA_JDK_VERSION" in
  8|1.8) JDK_PACKAGE=java-1.8.0-openjdk-devel ;;
  *) JDK_PACKAGE="java-$IDEA_JDK_VERSION-openjdk-devel" ;;
esac
case "$IDEA_JDK_VERSION" in
  17) DOCS_URL=https://download.oracle.com/otn_software/java/jdk/17.0.10+11/a473b47039a34b169d45b00685dea3dd/jdk-17.0.10_doc-all.zip ;;
  21) DOCS_URL=https://download.oracle.com/otn_software/java/jdk/21.0.2+13/f2283984656d49d69e91c558476027ac/jdk-21.0.2_doc-all.zip ;;
  *) DOCS_URL= ;;
esac
run mkdir -p docs
if [ -z "$DOCS_URL" ]; then
  log "No downloadable documentation for JDK $IDEA_JDK_VERSION"
elif [ -f "docs/${DOCS_URL##*/}" ]; then
  log "Use docs/${DOCS_URL##*/}"
elif [ "$DRY_RUN" == 1 ]; then
  log "Would download $DOCS_URL"
elif ! download "$DOCS_URL" "docs/${DOCS_URL##*/}"; then
  warn "unable to download the JDK documentation, continuing without it"
fi

# IntelliJ IDEA: the newest local installation of the edition, unless a release is pinned
IDEA_HOME=
if [ -z "$IDEA_RELEASE" ]; then
  IDEA_HOME="$(latest_idea_home "$EDITION")"
fi
if [ -n "$IDEA_HOME" ]; then
  log "Use $IDEA_HOME"
else
  if [ -n "$IDEA_RELEASE" ]; then
    RELEASE_VERSION="${IDEA_RELEASE%@*}"
    RELEASE_BUILD="${IDEA_RELEASE#*@}"
    if unified "$RELEASE_VERSION"; then
      IDEA_FILE="idea-$RELEASE_VERSION"
    else
      IDEA_FILE="idea$EDITION-$RELEASE_VERSION"
    fi
    if [ "$DOCKER_ARCH" == aarch64 ]; then
      IDEA_FILE="$IDEA_FILE-aarch64"
    fi
    IDEA_URL="https://download.jetbrains.com/idea/$IDEA_FILE.tar.gz"
    IDEA_CHECKSUM_URL="$IDEA_URL.sha256"
  else
    RELEASE_JSON="$(curl -fsSL --retry 3 'https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release')" \
      || die "unable to get the latest IntelliJ IDEA release"
    PLATFORM=linux
    if [ "$DOCKER_ARCH" == aarch64 ]; then
      PLATFORM=linuxARM64
    fi
    DOWNLOAD_JSON="$(echo "$RELEASE_JSON" | grep -oE "\"$PLATFORM\":\{[^}]*\}" || true)"
    RELEASE_VERSION="$(json_field version "$RELEASE_JSON")"
    RELEASE_BUILD="$(json_field build "$RELEASE_JSON")"
    IDEA_URL="$(json_field link "$DOWNLOAD_JSON")"
    IDEA_CHECKSUM_URL="$(json_field checksumLink "$DOWNLOAD_JSON")"
    if [ -z "$RELEASE_VERSION" ] || [ -z "$RELEASE_BUILD" ] || [ -z "$IDEA_URL" ] || [ -z "$IDEA_CHECKSUM_URL" ]; then
      die "unexpected answer of the JetBrains releases service"
    fi
  fi
  if unified "$RELEASE_VERSION"; then
    IDEA_HOME="idea-IU-$RELEASE_BUILD"
  else
    IDEA_HOME="idea-$EDITION-$RELEASE_BUILD"
  fi
  log "IntelliJ IDEA $RELEASE_VERSION, build $RELEASE_BUILD"
  install_dist "$IDEA_HOME" bin/idea.sh "$IDEA_URL" "$IDEA_CHECKSUM_URL" 256
fi

# Image: rebuilt when the Dockerfile, the entry point or the build arguments change
BUILD_ARGS=(
  --build-arg "BASE_IMAGE=$IDEA_BASE_IMAGE"
  --build-arg "USER_NAME=$IDEA_USER"
  --build-arg "USER_UID=$(id -u)"
  --build-arg "USER_GID=$(id -g)"
  --build-arg "JDK_PACKAGE=$JDK_PACKAGE"
)
IMAGE_CONFIG="$({ cat Dockerfile entrypoint.sh; echo "${BUILD_ARGS[*]}"; } | sha 256)"
if [ "$REBUILD" == 1 ]; then
  log "Rebuild the image $IDEA_IMAGE"
  run docker build --pull --no-cache "${BUILD_ARGS[@]}" --label "idea-docker.config=$IMAGE_CONFIG" -t "$IDEA_IMAGE" .
elif [ "$(docker image inspect --format '{{index .Config.Labels "idea-docker.config"}}' "$IDEA_IMAGE" 2> /dev/null || true)" \
       != "$IMAGE_CONFIG" ]; then
  log "Build the image $IDEA_IMAGE"
  run docker build "${BUILD_ARGS[@]}" --label "idea-docker.config=$IMAGE_CONFIG" -t "$IDEA_IMAGE" .
else
  log "The image $IDEA_IMAGE is up to date"
fi

# Container. The home directory is a volume, so settings, plugins and caches survive recreating the container.
PROJECTS_DIR="${IDEA_PROJECTS_PATH/#\~/$HOME}"
case "$PROJECTS_DIR" in
  /*) ;;
  *) PROJECTS_DIR="$PWD/${PROJECTS_DIR#./}" ;;
esac
run mkdir -p "$PROJECTS_DIR" "$HOME/.m2"
CREATE_OPTIONS=(
  --init --stop-timeout 60
  --name "$IDEA_CONTAINER" --hostname "$IDEA_HOSTNAME"
  -e "DISPLAY=$IDEA_DISPLAY" -e "XAUTHORITY=$XAUTH_TARGET"
  --mount "type=volume,source=$IDEA_CONTAINER-home,target=$USER_HOME"
  --mount "type=bind,source=$PWD/$IDEA_HOME,target=/opt/idea"
  --mount "type=bind,source=$PWD/$MAVEN_HOME,target=/opt/maven"
  --mount "type=bind,source=$HOME/.m2,target=$USER_HOME/.m2"
  --mount "type=bind,source=$PROJECTS_DIR,target=$USER_HOME/IdeaProjects"
  --mount "type=bind,source=$PWD/docs,target=$USER_HOME/docs"
)
if [ -n "$GRADLE_HOME" ]; then
  CREATE_OPTIONS+=(--mount "type=bind,source=$PWD/$GRADLE_HOME,target=/opt/gradle")
fi
if [ -n "$IDEA_GITCONFIG" ] && [ -f "$IDEA_GITCONFIG" ]; then
  CREATE_OPTIONS+=(--mount "type=bind,source=$IDEA_GITCONFIG,target=$USER_HOME/.gitconfig-host,readonly")
fi
if [ "$DOCKER_OS" == "Docker Desktop" ]; then
  # Docker Desktop forwards the host SSH agent through a socket that belongs to root:root
  CREATE_OPTIONS+=(--mount "type=bind,source=/run/host-services/ssh-auth.sock,target=/run/host-services/ssh-auth.sock"
                   -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock --group-add 0)
elif [ -S "${SSH_AUTH_SOCK:-}" ]; then
  CREATE_OPTIONS+=(--mount "type=bind,source=$SSH_AUTH_SOCK,target=/run/ssh-agent.sock" -e SSH_AUTH_SOCK=/run/ssh-agent.sock)
fi
if [ "$(uname -s)" != Darwin ] && [ -d /tmp/.X11-unix ]; then
  CREATE_OPTIONS+=(--mount "type=bind,source=/tmp/.X11-unix,target=/tmp/.X11-unix")
fi
for PORT in $IDEA_PORTS; do
  CREATE_OPTIONS+=(-p "$PORT")
done
read -r -a EXTRA_OPTIONS <<< "$IDEA_DOCKER_OPTIONS"
CREATE_OPTIONS+=(${EXTRA_OPTIONS[@]+"${EXTRA_OPTIONS[@]}"})

log "Create the container $IDEA_CONTAINER"
run docker create "${CREATE_OPTIONS[@]}" "$IDEA_IMAGE" > /dev/null
start_container "$XAUTH_TARGET"
