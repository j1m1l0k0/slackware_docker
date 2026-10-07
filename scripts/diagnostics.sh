#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/diagnostics.sh
# Author: j1m1l0k0 - 2026
# Gera docker-diagnostics.txt com as informações clássicas de diagnóstico
# do Slackware (NÃO usa journalctl/systemd):
#   /var/log/docker.log, ps aux | grep dockerd, /proc/cgroups, mounts,
#   iptables, NAT, sysctl, kernel, docker info.
# Requer root para algumas coletas (iptables); usa sudo quando preciso.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

OUTFILE="${OUT_DIR}/docker-diagnostics.txt"
mkdir -p "${OUT_DIR}"
: > "${OUTFILE}"

section() { printf '\n===== %s =====\n' "$1" >> "${OUTFILE}"; }

section "Data/Hora"
date >> "${OUTFILE}"

section "uname -a / kernel"
uname -a >> "${OUTFILE}" 2>&1

section "Slackware"
grep -E '^(NAME|VERSION|ID)=' /etc/os-release >> "${OUTFILE}" 2>&1 || true

section "/var/log/docker.log (últimas 200 linhas)"
if [ -r /var/log/docker.log ]; then
  tail -n 200 /var/log/docker.log >> "${OUTFILE}" 2>&1
else
  echo "(não existe /var/log/docker.log)" >> "${OUTFILE}"
fi

section "ps aux | grep dockerd"
run_root sh -c 'ps aux | grep -E "[d]ockerd|[c]ontainerd|[b]uildkitd"' >> "${OUTFILE}" 2>&1 || true

section "/proc/cgroups"
cat /proc/cgroups >> "${OUTFILE}" 2>&1 || true

section "mount | grep cgroup"
mount | grep cgroup >> "${OUTFILE}" 2>&1 || true

section "mount | grep overlay"
mount | grep overlay >> "${OUTFILE}" 2>&1 || true

section "filesystems suportados (overlay)"
grep -E 'overlay|cgroup' /proc/filesystems >> "${OUTFILE}" 2>&1 || true

section "iptables -L"
run_root iptables -L >> "${OUTFILE}" 2>&1 || echo "(iptables indisponível)" >> "${OUTFILE}"

section "iptables -t nat -L"
run_root iptables -t nat -L >> "${OUTFILE}" 2>&1 || echo "(iptables -t nat indisponível)" >> "${OUTFILE}"

section "sysctl docker/net"
for k in net.ipv4.ip_forward net.ipv6.conf.all.forwarding net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables; do
  printf '%s = %s\n' "${k}" "$(cat /proc/sys/$(echo ${k} | tr '.' '/') 2>/dev/null || echo n/a)" >> "${OUTFILE}"
done

section "módulos de kernel carregados (linux relevantes)"
lsmod | grep -E 'overlay|br_netfilter|bridge|iptable|nf_nat|nf_conntrack|xt_' >> "${OUTFILE}" 2>&1 || true

section "configuração do kernel (funções do Docker)"
if [ -r /proc/config.gz ]; then
  zcat /proc/config.gz | grep -E 'CONFIG_(NAMESPACES|CGROUPS|MEMCG|OVERLAY_FS|BRIDGE|BRIDGE_NETFILTER|NF_CONNTRACK|NF_NAT|IP_NF|NETFILTER_XT_MATCH_ADDRTYPE|SECCOMP|USER_NS|VETH)=' >> "${OUTFILE}" 2>&1 || true
fi

section "cgroup v2?"
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  echo "cgroup v2 ATIVO" >> "${OUTFILE}"
else
  echo "cgroup v1 (v2 inativo)" >> "${OUTFILE}"
fi

section "docker info (se o daemon responder)"
if [ -S /var/run/docker.sock ]; then
  run_root docker info >> "${OUTFILE}" 2>&1 || run_root docker info --format '{{json .}}' >> "${OUTFILE}" 2>&1 || true
else
  echo "(socket /var/run/docker.sock não existe)" >> "${OUTFILE}"
fi

section "docker version (se instalado)"
command -v docker >/dev/null 2>&1 && run_root docker version >> "${OUTFILE}" 2>&1 || true

section "espaco em /var/lib/docker"
df -h /var/lib/docker >> "${OUTFILE}" 2>&1 || true

section "dmesg - kernel tail (overlay/bridge/netfilter)"
dmesg 2>/dev/null | tail -n 50 | grep -iE 'overlay|bridge|netfilter|nat|seccomp' >> "${OUTFILE}" 2>&1 || true

if [ -f "${MANIFEST}" ]; then
  section "Manifest do build"
  cat "${MANIFEST}" >> "${OUTFILE}"
fi

ok "Relatório gerado: ${OUTFILE}"
exit 0