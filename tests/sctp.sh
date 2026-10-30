#!/bin/bash
#
# Checks SCTP in the image: the kernel, the userland, the JDK and the container profile of idea.sh.
#
# Usage: tests/sctp.sh [image]
#   Without an image the Dockerfile is built as idea-sctp-test:local, and the image is removed afterwards.
#   IDEA_JDK_VERSION (25 by default) is the JDK the image must have.
#
# The profiles are the ones idea.sh creates the container with:
#   privileged    --privileged and the three SCTP sysctls: everything is checked
#   unprivileged  IDEA_PRIVILEGED=false: SCTP and authentication work, sysctl -w and ip netns do not
#
set -uo pipefail
cd "$(dirname "$0")/.."

JDK_VERSION="${IDEA_JDK_VERSION:-25}"
IMAGE="${1:-}"
BUILT_IMAGE=
PASSED=0
FAILED=0

cleanup() {
  if [ -n "$BUILT_IMAGE" ]; then
    docker rmi "$BUILT_IMAGE" > /dev/null 2>&1
  fi
}
trap cleanup EXIT

# check <description> <expected> <actual>
check() {
  if [ "$2" == "$3" ]; then
    PASSED=$((PASSED + 1))
    echo "  ok    $1"
  else
    FAILED=$((FAILED + 1))
    echo "  FAIL  $1: expected '$2', got '$3'"
  fi
}

# fact <KEY>: the value printed by sctp-probe.sh
fact() {
  echo "$FACTS" | sed -n "s/^$1=//p" | head -n1
}

# probe <docker run options>: runs the probe in the image and keeps its facts
probe() {
  FACTS="$(docker run --rm --entrypoint bash "$@" --volume "$PWD/tests:/tests:ro" "$IMAGE" /tests/sctp-probe.sh 2>&1)" \
    || { echo "  FAIL  the probe did not run:"; echo "$FACTS"; FAILED=$((FAILED + 1)); }
}

command -v docker > /dev/null || { echo "docker is required" >&2; exit 2; }
if [ -z "$IMAGE" ]; then
  IMAGE=idea-sctp-test:local
  echo "Build $IMAGE with java-$JDK_VERSION-openjdk-devel"
  docker build --quiet --build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)" \
    --build-arg "JDK_PACKAGE=java-$JDK_VERSION-openjdk-devel" -t "$IMAGE" . > /dev/null || { echo "build failed" >&2; exit 2; }
  BUILT_IMAGE="$IMAGE"
fi

echo "privileged: --privileged and auth_enable, udp_port, encap_port"
probe --privileged --sysctl net.sctp.auth_enable=1 --sysctl net.sctp.udp_port=9899 --sysctl net.sctp.encap_port=9899
check "JDK $JDK_VERSION" "$JDK_VERSION" "$(fact JAVA_MAJOR)"
check "module jdk.sctp" yes "$(fact JDK_SCTP_MODULE)"
check "checksctp" 0 "$(fact CHECKSCTP_RC)"
check "libsctp.so.1 is registered" yes "$(fact LIBSCTP)"
check "sysctl is installed" yes "$(fact TOOL_sysctl)"
check "ip is installed" yes "$(fact TOOL_ip)"
check "ss is installed" yes "$(fact TOOL_ss)"
check "net.sctp.auth_enable" 1 "$(fact AUTH_ENABLE)"
check "net.sctp.udp_port" 9899 "$(fact UDP_PORT)"
check "net.sctp.encap_port" 9899 "$(fact ENCAP_PORT)"
check "sysctl -w inside the container" yes "$(fact SYSCTL_WRITE)"
check "two network namespaces" yes "$(fact NETNS)"
check "SctpServerChannel.open()" OPEN_OK "$(fact JAVA_OPEN)"
# udp_port and encap_port are both 9899 here, so this association runs encapsulated in UDP
check "one-to-one association over loopback, SCTP over UDP" ASSOC_RC=0 "$(fact JAVA_ASSOC)"
echo "  info  $(fact PROCFS_NODES) nodes in /proc/sys/net/sctp, kernel $(docker run --rm --entrypoint uname "$IMAGE" -r)"

# The same probe without libsctp.so.1: jdk.sctp must report that SCTP is unsupported, so the checks above are not vacuous
echo "negative control: libsctp.so.1 hidden"
NEGATIVE="$(docker run --rm --user 0 --entrypoint bash --volume "$PWD/tests:/tests:ro" "$IMAGE" -c '
  PROBE_DIR="$(mktemp -d)"
  javac --add-modules jdk.sctp -d "$PROBE_DIR" /tests/SctpOpenProbe.java > /dev/null 2>&1
  mkdir "$PROBE_DIR/hidden"
  mv "$(dirname "$(ldconfig -p | awk "/libsctp\.so\.1 /{print \$NF}")")"/libsctp.so.1* "$PROBE_DIR/hidden"
  ldconfig
  java --add-modules jdk.sctp -cp "$PROBE_DIR" SctpOpenProbe 2>&1 | head -n1 | cut -d: -f1' 2>&1)"
check "SctpServerChannel.open() without libsctp.so.1" UOE_OK "$NEGATIVE"

echo "unprivileged: IDEA_PRIVILEGED=false, auth_enable only"
probe --sysctl net.sctp.auth_enable=1
check "net.sctp.auth_enable" 1 "$(fact AUTH_ENABLE)"
check "net.sctp.udp_port is not set" 0 "$(fact UDP_PORT)"
check "net.sctp.encap_port is not set" 0 "$(fact ENCAP_PORT)"
check "sysctl -w is refused" no "$(fact SYSCTL_WRITE)"
check "SctpServerChannel.open()" OPEN_OK "$(fact JAVA_OPEN)"
check "one-to-one association over loopback" ASSOC_RC=0 "$(fact JAVA_ASSOC)"

echo
echo "passed: $PASSED, failed: $FAILED"
[ "$FAILED" == 0 ]
