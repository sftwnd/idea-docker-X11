#!/bin/bash
#
# Checks the docker options that idea.sh builds from its settings. It runs idea.sh --dry-run, so nothing is
# downloaded, built or started; only a throwaway container is created for the warning checks. No IDEA container
# may be running, idea.sh refuses to continue then.
#
# Usage: tests/options.sh
#
set -uo pipefail
cd "$(dirname "$0")/.."

TEST_CONTAINER=idea-options-test
TEST_IMAGE=idea-options-test:empty
PASSED=0
FAILED=0

cleanup() {
  docker rm -f "$TEST_CONTAINER" > /dev/null 2>&1
  docker rmi "$TEST_IMAGE" > /dev/null 2>&1
}
trap cleanup EXIT

# pass <description> / fail <description> <details>
pass() {
  PASSED=$((PASSED + 1))
  echo "  ok    $1"
}
fail() {
  FAILED=$((FAILED + 1))
  echo "  FAIL  $1: $2"
}

# idea <VAR=value>...: runs idea.sh --dry-run with the settings; the output is in $OUTPUT, the status in $STATUS.
# Pinned versions keep the dry run offline, and the settings of the host environment do not leak in.
idea() {
  OUTPUT="$(env -u IDEA_PRIVILEGED -u IDEA_SCTP_AUTH_ENABLE -u IDEA_SCTP_UDP_PORT -u IDEA_SCTP_ENCAP_PORT \
                -u IDEA_JDK_VERSION -u IDEA_DOCKER_OPTIONS -u IDEA_PORTS -u IDEA_BASE_IMAGE -u IDEA_USER \
                IDEA_RELEASE=2025.2@252.23892.409 IDEA_MAVEN_VERSION=3.9.12 IDEA_GRADLE_VERSION=none \
                IDEA_CONTAINER="$TEST_CONTAINER" IDEA_IMAGE=idea-options-test:local IDEA_GITCONFIG= \
                "$@" ./idea.sh --dry-run 2>&1)"
  STATUS=$?
  CREATE="$(echo "$OUTPUT" | grep '^+ docker create' || true)"
  BUILD="$(echo "$OUTPUT" | grep '^+ docker build' || true)"
}

# has <description> <text>: the docker create command contains the words; lacks is the opposite
has() {
  case "$CREATE " in
    *" $2 "*) pass "$1" ;;
    *) fail "$1" "no '$2' in: $CREATE" ;;
  esac
}
lacks() {
  case "$CREATE " in
    *"$2"*) fail "$1" "found '$2' in: $CREATE" ;;
    *) pass "$1" ;;
  esac
}

# rejects <description> <message> <VAR=value>...: idea.sh stops with the message
rejects() {
  local description="$1" message="$2"
  shift 2
  idea "$@"
  if [ "$STATUS" != 0 ] && echo "$OUTPUT" | grep -qF "$message"; then
    pass "$description"
  else
    fail "$description" "status $STATUS: $OUTPUT"
  fi
}

# warns <description> <yes|no> <VAR=value>...: idea.sh warns that the existing container differs from the settings
warns() {
  local description="$1" expected="$2" actual=no
  shift 2
  idea "$@"
  if echo "$OUTPUT" | grep -q "^WARNING: the container $TEST_CONTAINER has"; then
    actual=yes
  fi
  if [ "$STATUS" == 0 ] && [ "$actual" == "$expected" ]; then
    pass "$description"
  else
    fail "$description" "status $STATUS, warning $actual: $OUTPUT"
  fi
}

command -v docker > /dev/null || { echo "docker is required" >&2; exit 2; }
cleanup

echo "defaults"
idea
[ "$STATUS" == 0 ] && pass "dry run succeeds" || fail "dry run succeeds" "status $STATUS: $OUTPUT"
has "privileged" "--privileged"
has "net.sctp.auth_enable=1" "--sysctl net.sctp.auth_enable=1"
lacks "udp_port is not set" "net.sctp.udp_port"
lacks "encap_port is not set" "net.sctp.encap_port"
case "$BUILD " in
  *" --build-arg JDK_PACKAGE=java-25-openjdk-devel "*) pass "JDK 25 in the image" ;;
  *) fail "JDK 25 in the image" "$BUILD" ;;
esac

echo "settings"
idea IDEA_PRIVILEGED=false
lacks "IDEA_PRIVILEGED=false removes --privileged" "--privileged"
has "IDEA_PRIVILEGED=false keeps auth_enable" "--sysctl net.sctp.auth_enable=1"
idea IDEA_SCTP_AUTH_ENABLE=0
has "IDEA_SCTP_AUTH_ENABLE=0" "--sysctl net.sctp.auth_enable=0"
idea IDEA_SCTP_AUTH_ENABLE=
lacks "empty IDEA_SCTP_AUTH_ENABLE is not passed" "net.sctp.auth_enable"
idea IDEA_SCTP_UDP_PORT=9899
has "IDEA_SCTP_UDP_PORT" "--sysctl net.sctp.udp_port=9899"
lacks "encap_port stays unset" "net.sctp.encap_port"
idea IDEA_SCTP_UDP_PORT=9899 IDEA_SCTP_ENCAP_PORT=9898
has "IDEA_SCTP_UDP_PORT again" "--sysctl net.sctp.udp_port=9899"
has "IDEA_SCTP_ENCAP_PORT" "--sysctl net.sctp.encap_port=9898"
idea IDEA_JDK_VERSION=21
case "$BUILD " in
  *" --build-arg JDK_PACKAGE=java-21-openjdk-devel "*) pass "IDEA_JDK_VERSION=21" ;;
  *) fail "IDEA_JDK_VERSION=21" "$BUILD" ;;
esac
idea IDEA_DOCKER_OPTIONS="--sysctl net.sctp.auth_enable=0"
case "$CREATE" in
  *"--sysctl net.sctp.auth_enable=1"*"--sysctl net.sctp.auth_enable=0"*) pass "IDEA_DOCKER_OPTIONS come last" ;;
  *) fail "IDEA_DOCKER_OPTIONS come last" "$CREATE" ;;
esac

echo "invalid settings"
rejects "IDEA_PRIVILEGED=yes" "IDEA_PRIVILEGED must be true or false" IDEA_PRIVILEGED=yes
rejects "IDEA_SCTP_AUTH_ENABLE=2" "IDEA_SCTP_AUTH_ENABLE must be 0 or 1" IDEA_SCTP_AUTH_ENABLE=2
rejects "IDEA_SCTP_UDP_PORT=abc" "IDEA_SCTP_UDP_PORT must be a port number" IDEA_SCTP_UDP_PORT=abc
rejects "IDEA_SCTP_UDP_PORT=65536" "IDEA_SCTP_UDP_PORT must be a port number" IDEA_SCTP_UDP_PORT=65536
rejects "IDEA_SCTP_UDP_PORT=0123456789" "IDEA_SCTP_UDP_PORT must be a port number" IDEA_SCTP_UDP_PORT=0123456789
rejects "IDEA_SCTP_ENCAP_PORT=09899 (octal for the kernel)" "IDEA_SCTP_ENCAP_PORT must be a port number" IDEA_SCTP_ENCAP_PORT=09899
idea IDEA_SCTP_UDP_PORT=65535 IDEA_SCTP_ENCAP_PORT=0
[ "$STATUS" == 0 ] && has "ports 65535 and 0 are valid" "--sysctl net.sctp.udp_port=65535" || fail "ports 65535 and 0 are valid" "$OUTPUT"

echo "existing container: privileged, auth_enable=1, udp_port=9899"
# An empty image is enough to create a container; it is never started
tar -cT /dev/null | docker import - "$TEST_IMAGE" > /dev/null \
  && docker create --name "$TEST_CONTAINER" --privileged --sysctl net.sctp.auth_enable=1 --sysctl net.sctp.udp_port=9899 \
       "$TEST_IMAGE" /bin/true > /dev/null \
  || { echo "unable to create the test container" >&2; exit 2; }
warns "the same settings: no warning" no IDEA_SCTP_UDP_PORT=9899
warns "udp_port missing from the settings: warning" yes
warns "different udp_port: warning" yes IDEA_SCTP_UDP_PORT=9900
warns "IDEA_PRIVILEGED=false: warning" yes IDEA_SCTP_UDP_PORT=9899 IDEA_PRIVILEGED=false
warns "encap_port added: warning" yes IDEA_SCTP_UDP_PORT=9899 IDEA_SCTP_ENCAP_PORT=9899
warns "auth_enable dropped: warning" yes IDEA_SCTP_UDP_PORT=9899 IDEA_SCTP_AUTH_ENABLE=

echo
echo "passed: $PASSED, failed: $FAILED"
[ "$FAILED" == 0 ]
