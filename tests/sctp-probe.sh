#!/bin/bash
#
# Runs inside the container (see sctp.sh) and prints KEY=VALUE facts about SCTP. It installs nothing and changes
# only what the container discards: the sysctl write and the network namespaces are tried and undone.
#
set -u
SUDO=""
[ "$(id -u)" != 0 ] && SUDO="sudo -n"

have() {
  command -v "$1" > /dev/null 2>&1
}

yes_no() {
  if "$@" > /dev/null 2>&1; then echo yes; else echo no; fi
}

knob() {
  cat "/proc/sys/net/sctp/$1" 2> /dev/null || echo unreadable
}

echo "JAVA_MAJOR=$(java -XshowSettings:properties -version 2>&1 | awk '$1 == "java.specification.version" { print $3 }')"
echo "JDK_SCTP_MODULE=$(java --list-modules | grep -q '^jdk\.sctp@' && echo yes || echo no)"
checksctp > /dev/null 2>&1
echo "CHECKSCTP_RC=$?"
echo "LIBSCTP=$(ldconfig -p | grep -q 'libsctp\.so\.1' && echo yes || echo no)"
echo "PROCFS_NODES=$(ls /proc/sys/net/sctp | wc -l | tr -d ' ')"
for TOOL in sysctl ip ss; do
  echo "TOOL_$TOOL=$(yes_no have "$TOOL")"
done

# The values the container was created with
echo "AUTH_ENABLE=$(knob auth_enable)"
echo "UDP_PORT=$(knob udp_port)"
echo "ENCAP_PORT=$(knob encap_port)"

# What --privileged adds: writable /proc/sys and the right to create network namespaces
UDP_PORT_BEFORE="$(knob udp_port)"
if have sysctl && $SUDO sysctl -w net.sctp.udp_port=9900 > /dev/null 2>&1 && [ "$(knob udp_port)" == 9900 ]; then
  echo "SYSCTL_WRITE=yes"
  # The Java probes share the network namespace: with encap_port set, a changed udp_port leaves nobody listening
  $SUDO sysctl -w "net.sctp.udp_port=$UDP_PORT_BEFORE" > /dev/null 2>&1
else
  echo "SYSCTL_WRITE=no"
fi
if have ip && $SUDO ip netns add probe1 > /dev/null 2>&1 && $SUDO ip netns add probe2 > /dev/null 2>&1; then
  echo "NETNS=yes"
else
  echo "NETNS=no"
fi
if have ip; then
  $SUDO ip netns del probe1 > /dev/null 2>&1
  $SUDO ip netns del probe2 > /dev/null 2>&1
fi

# The JDK end to end: open a socket, then a real association over loopback
PROBE_DIR="$(mktemp -d)"
javac --add-modules jdk.sctp -d "$PROBE_DIR" /tests/SctpOpenProbe.java /tests/SctpLoopback.java > /dev/null 2>&1
echo "JAVA_OPEN=$(timeout 60 java --add-modules jdk.sctp -cp "$PROBE_DIR" SctpOpenProbe 2>&1 | head -n1 | cut -d: -f1)"
echo "JAVA_ASSOC=$(timeout 60 java --add-modules jdk.sctp -cp "$PROBE_DIR" SctpLoopback 2>&1 | head -n1 | cut -d' ' -f1)"
rm -rf "$PROBE_DIR"
