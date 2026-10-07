#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/check-system.sh
# Author: j1m1l0k0 - 2026
# Verifica o sistema antes do build/instalação:
#   - Slackware 15.0, arquitetura
#   - kernel (namespaces, cgroups, overlay, bridge, netfilter, iptables,
#     NAT, conntrack, seccomp)
#   - cgroup v1 / v2
#   - CPU, RAM, espaço em disco, módulos disponíveis
#   - dependências de build e de sistema
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

PASS=0; WARN=0; FAIL=0
report() { # report P/W/F "mensagem"
  case "$1" in
    PASS) PASS=$((PASS+1)); ok "   $2" ;;
    WARN) WARN=$((WARN+1)); warn "   $2" ;;
    FAIL) FAIL=$((FAIL+1)); printf '\033[1;31m[FALHA]\033[0m   %s\n' "$2" >&2 ;;
  esac
}

load_versions

log "=== 1. Sistema operacional ==="
if [ -r /etc/os-release ] && grep -qE '^ID=slackware$' /etc/os-release; then
  SVER="$(sed -n 's/^VERSION_ID="\?\([^"]*\)"\?/\1/p' /etc/os-release)"
  report PASS "Slackware ${SVER}"
  [ "${SVER}" = "15.0" ] || report WARN "Versão ${SVER} != 15.0: o projeto foi validado para 15.0"
else
  report FAIL "Sistema não é Slackware (o projeto é específico para Slackware 15.0)"
fi

log "=== 2. Arquitetura ==="
case "${ARCH}" in
  x86_64) report PASS "x86_64 (am64d)" ;;
  aarch64|arm64)
    report WARN "aarch64 detectado: o projeto prioriza x86_64; pacotes serão chamados de ${PKGARCH}"
    ;;
  *) report WARN "Arquitetura ${ARCH} não testada oficialmente (matriz validada para amd64)" ;;
esac

log "=== 3. Kernel ==="
KVER="$(uname -r)"
report PASS "Kernel: ${KVER} (${ARCH})"
if [ -f /proc/config.gz ]; then
  KCFG=/proc/config.gz
elif [ -r "/boot/config-${KVER}" ]; then
  KCFG="/boot/config-${KVER}"
else
  KCFG=""
fi
if [ -n "${KCFG}" ]; then
  # Função: cfg CONFIG_FOO  -> PASS se =y ou =m; cfg_req CONFIG_FOO -> exigir =y
  cfg() {
    local v
    v="$(zcat "${KCFG}" 2>/dev/null | sed -n "s/^${1}=//p" | head -1)"
    case "${v}" in y|m) report PASS "${1} (${v})" ;; *) report FAIL "${1} ausente" ;; esac
  }
  cfg CONFIG_NAMESPACES
  cfg CONFIG_CGROUPS
  cfg CONFIG_MEMCG
  cfg CONFIG_OVERLAY_FS
  cfg CONFIG_BRIDGE
  cfg CONFIG_BRIDGE_NETFILTER
  cfg CONFIG_NETFILTER
  cfg CONFIG_NF_CONNTRACK
  cfg CONFIG_NF_NAT
  cfg CONFIG_IP_NF_IPTABLES
  cfg CONFIG_IP_NF_NAT
  cfg CONFIG_IP_NF_FILTER
  cfg CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
  cfg CONFIG_IP6_NF_IPTABLES
  cfg CONFIG_VETH
  zcat "${KCFG}" 2>/dev/null | grep -q '^CONFIG_SECCOMP=y' && report PASS "CONFIG_SECCOMP (y)" || report WARN "CONFIG_SECCOMP ausente (seccomp desnecessário para rodar, mas recomendado)"
  zcat "${KCFG}" 2>/dev/null | grep -q '^CONFIG_USER_NS=y' && report PASS "CONFIG_USER_NS (y)" || report WARN "CONFIG_USER_NS ausente (usernamespaces; opcional)"
else
  report WARN "configuração do kernel não encontrada (/proc/config.gz ou /boot/config-*)"
fi

log "=== 4. cgroup ==="
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  report PASS "cgroup v2 em uso"
  CGVER=2
elif grep -q cgroup /proc/filesystems && [ -d /sys/fs/cgroup ]; then
  report PASS "cgroup v1 em uso (suportado pelo Docker Engine até 2029; migração p/ v2 recomendada)"
  CGVER=1
  report WARN "cgroup v2 NÃO ativo: nenhuma alteração automática será feita. Para ativar na boot (opcional, reversível) adicione: cgroup_no_v1=all (e ajuste rc.S/initrd). Veja README."
else
  report FAIL "cgroups não montados"
  CGVER=0
fi

log "=== 5. Recursos ==="
NCORES="$(nproc || echo 1)"
report PASS "CPUs: ${NCORES}"
# RAM
MEM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
if [ "${MEM_MB:-0}" -ge 2048 ]; then
  report PASS "RAM: ${MEM_MB} MB"
else
  report WARN "RAM: ${MEM_MB} MB (compilação de 6 componentes Go pode ser lenta)"
fi
# Disco (onde ficará o build e /var/lib/docker)
DISK_KB="$(df -P / | awk 'NR==2 {print $4}')"
DISK_MB=$((DISK_KB/1024))
if [ "${DISK_MB}" -ge 20000 ]; then
  report PASS "Espaço em disco: ${DISK_MB} MB disponíveis"
else
  report FAIL "Espaço em disco insuficiente (< 20 GB)"
fi
FW="$(df -P /var/lib 2>/dev/null | awk 'NR==2 {print $1}')"
ROOTFS="$(awk '$2=="/"{print $3}' /proc/mounts 2>/dev/null || echo desconhecido)"
case "${ROOTFS}" in
  ext4|xfs|btrfs) report PASS "Filesystem raiz: ${ROOTFS} (overlay2 compatível)" ;;
  *) report WARN "Filesystem raiz: ${ROOTFS}; overlay2 pode não funcionar; será validado na instalação" ;;
esac

log "=== 6. Módulos do kernel disponíveis ==="
declare -a MODS=(overlay br_netfilter bridge ip_tables iptable_nat iptable_filter nf_nat nf_conntrack xt_MASQUERADE xt_addrtype ip6_tables veth)
MISSING_MODS=()
for m in "${MODS[@]}"; do
  if /sbin/modprobe -n "${m}" >/dev/null 2>&1; then
    report PASS "módulo disponível: ${m}"
  else
    MISSING_MODS+=("${m}")
    report WARN "módulo indisponível: ${m}"
  fi
done

log "=== 7. Dependências ==="
require_cmd git curl wget tar xz gzip make gcc g++ pkg-config python3 sha256sum installpkg makepkg
for c in git curl wget tar xz gzip make gcc g++ pkg-config python3 sha256sum installpkg makepkg; do
  report PASS "${c}: $(command -v "${c}")"
done
if command -v jq >/dev/null 2>&1; then
  report PASS "jq: $(command -v jq) (opcional)"
else
  report WARN "jq ausente: usar-se-á python3 para JSON"
fi
# iptables
if command -v iptables >/dev/null 2>&1; then
  report PASS "iptables: $(iptables -V 2>/dev/null)"
else
  report FAIL "iptables ausente (rede do Docker depende dele)"
fi
# libseccomp (seccomp do runc/buildkit)
if [ -f /usr/include/seccomp.h ] && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libseccomp; then
  report PASS "libseccomp (dev) presente: seccomp habilitado em runc/buildkitd"
else
  report WARN "libseccomp dev ausente: runc/buildkitd sem seccomp"
fi

log "=== 8. Toolchain Go ==="
if command -v go >/dev/null 2>&1; then
  report WARN "go do sistema: $(go version) (o build usará o toolchain local ${GO_VERSION} em ${GOROOT_DIR})"
else
  report WARN "nenhum go no sistema (o projeto baixa o toolchain oficial ${GO_VERSION})"
fi

log "=== 9. Instalação prévia de Docker? ==="
if ls /usr/bin/dockerd /usr/bin/docker /usr/bin/containerd /usr/bin/runc /usr/bin/buildkitd >/dev/null 2>&1; then
  report WARN "componentes Docker já presentes em /usr/bin (a instalação perguntará antes de substituir)"
else
  report PASS "nenhum componente Docker detectado em /usr/bin"
fi
PKG_DOCKER="$(ls /var/log/packages 2>/dev/null | grep -E '^(docker|dockerd|docker-engine|containerd|runc|buildkit)' || true)"
if [ -n "${PKG_DOCKER}" ]; then
  report WARN "pacotes já instalados: $(echo ${PKG_DOCKER})"
else
  report PASS "nenhum pacote Docker/containerd/runc em /var/log/packages"
fi

printf '\n\033[1;34m=== Resumo: %d OK, %d avisos, %d falhas ===\033[0m\n' "${PASS}" "${WARN}" "${FAIL}"
if [ "${FAIL}" -gt 0 ]; then
  die "${FAIL} verificação(ões) crítica(s) falharam (veja acima)."
fi
exit 0