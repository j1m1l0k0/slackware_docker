#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/uninstall.sh
# Remove os pacotes docker-slackware (removepkg), o rc.docker, o bloco do
# rc.local e o sysctl docker-slackware, SEM apagar /var/lib/docker nem
# /var/lib/containerd (imagens/volumes/containers ficam preservados) a menos
# que --purge-data seja confirmado duas vezes.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

PURGE=0
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --purge-data) PURGE=1 ;;
    --yes|-y) YES=1 ;;
    *) die "Argumento desconhecido: $1" ;;
  esac
  shift
done

confirm() {
  [ "${YES}" = "1" ] && return 0
  printf '%s [s/N] ' "$1"
  read -r ans
  case "${ans}" in s|S|y|Y) return 0 ;; *) return 1 ;; esac
}

# 1) Para o daemon
if run_root /etc/rc.d/rc.docker status >/dev/null 2>&1; then
  run_root /etc/rc.d/rc.docker stop || true
fi

# 2) removepkg para cada componente instalado pelo projeto
for pat in "docker-engine-*" "docker-cli-*" "containerd-*" "runc-*" "buildkit-*"; do
  for p in /var/log/packages/${pat}; do
    [ -e "${p}" ] || continue
    name="$(basename "${p}")"
    if confirm "Remover pacote ${name}?"; then
      run_root /sbin/removepkg "${name}"
      ok "Removido: ${name}"
    fi
  done
done

# 3) Bloco docker + rc.docker
RC_LOCAL=/etc/rc.d/rc.local
if grep -q '#<<docker-slackware:start>>' "${RC_LOCAL}" 2>/dev/null; then
  if confirm "Remover bloco docker-slackware de ${RC_LOCAL}?"; then
    backup_path "${RC_LOCAL}"
    TMP_RC="$(mktemp)"
    sed '/#<<docker-slackware:start>>/,/#<<docker-slackware:end>>/d' "${RC_LOCAL}" > "${TMP_RC}"
    run_root install -m 0755 "${TMP_RC}" "${RC_LOCAL}"
    rm -f "${TMP_RC}"
    ok "Bloco removido de ${RC_LOCAL}"
  fi
fi
if [ -e /etc/rc.d/rc.docker ]; then
  if confirm "Remover /etc/rc.d/rc.docker?"; then
    backup_path /etc/rc.d/rc.docker
    run_root rm -f /etc/rc.d/rc.docker
  fi
fi

# 4) sysctl docker-slackware
if [ -e /etc/sysctl.d/99-docker.conf ] && grep -q '# docker-slackware' /etc/sysctl.d/99-docker.conf; then
  if confirm "Remover /etc/sysctl.d/99-docker.conf (do projeto)?"; then
    backup_path /etc/sysctl.d/99-docker.conf
    run_root rm -f /etc/sysctl.d/99-docker.conf
  fi
fi

# 5) Dados (somente com --purge-data e confirmação dupla)
if [ "${PURGE}" = "1" ]; then
  if confirm "APAGAR /var/lib/docker e /var/lib/containerd (irreversível)?"; then
    if confirm "Duplo confirme: tem certeza absoluta?"; then
      run_root rm -rf /var/lib/docker /var/lib/containerd
      ok "Dados apagados."
    fi
  fi
else
  log "/var/lib/docker e /var/lib/containerd preservados. Use --purge-data para apagá-los."
fi

ok "Desinstalação concluída (backups em ${BACKUPS_DIR})."
exit 0