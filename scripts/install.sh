#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/install.sh
# Author: j1m1l0k0 - 2026
# Instala os pacotes .txz gerados usando installpkg/removepkg do Slackware,
# configura o host e (opcionalmente) inicia o Docker e roda os testes.
#
# Uso:
#   sudo scripts/install.sh                 # com prompts
#   SUDO_PASSWORD=... scripts/install.sh    # senha via env (não sai em logs)
#   scripts/install.sh --yes --no-tests     # sem confirmações/automação
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd installpkg removepkg

YES=0
RUN_TESTS_AFTER=1
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --no-tests) RUN_TESTS_AFTER=0 ;;
    *) die "Argumento desconhecido: $1" ;;
  esac
  shift
done

# --- Detecção de instalação existente (nunca substituir sem confirmar) -----
EXISTING="$(ls /usr/bin/dockerd /usr/bin/docker /usr/bin/containerd /usr/bin/runc /usr/bin/buildkitd 2>/dev/null || true)"
EXISTING_PKGS="$(ls /var/log/packages 2>/dev/null | grep -E '^(docker|dockerd|docker-engine|containerd|runc|buildkit)-' || true)"
if [ -n "${EXISTING}" ] || [ -n "${EXISTING_PKGS}" ]; then
  printf '\033[1;33mAVISO:\033[0m uma instalação Docker já existe:\n'
  [ -n "${EXISTING}" ] && printf '  binários: %s\n' "${EXISTING}"
  [ -n "${EXISTING_PKGS}" ] && printf '  pacotes:  %s\n' "${EXISTING_PKGS}"
  printf '  Os pacotes novos serão instalados POR CIMA do existente.\n'
  printf '  /var/lib/docker e /var/lib/containerd NUNCA são apagados.\n'
  if [ "${YES}" != "1" ]; then
    printf 'Continuar mesmo assim? [s/N] '
    read -r ans
    case "${ans}" in s|S|y|Y) : ;; *) die "Abortado pelo usuário." ;; esac
  fi
fi

# Os pacotes devem existir
PKGS=(
  "runc-${RUNC_VERSION}"
  "containerd-${CONTAINERD_VERSION}"
  "docker-engine-${ENGINE_VERSION}"
  "docker-cli-${CLI_VERSION}"
  "buildkit-${BUILDKIT_VERSION}"
)
for p in "${PKGS[@]}"; do
  f="${OUT_DIR}/${p}-${PKGARCH}-1.txz"
  [ -f "${f}" ] || die "Pacote ausente: ${f} (rode ./build.sh primeiro)"
done

# --- Config do host (backups etc.) antes de instalar os binários -----------
"${SCRIPT_DIR}/configure-host.sh"

# --- Instalação via installpkg (ordem de dependência) ----------------------
for p in "${PKGS[@]}"; do
  f="${OUT_DIR}/${p}-${PKGARCH}-1.txz"
  if ls /var/log/packages/"${p}"-* >/dev/null 2>&1; then
    log "Substituindo pacote ${p}"
    run_root /sbin/upgradepkg --reinstall --install-new "${f}"
  else
    log "Instalando ${p}"
    run_root /sbin/installpkg "${f}"
  fi
  ok "Instalado: $(basename "${f}")"
done

log "Docker, CLI, containerd, runc e BuildKit instalados."
if [ "${RUN_TESTS_AFTER}" = "1" ]; then
  set +e
  run_root /etc/rc.d/rc.docker start
  START_RC=$?
  set -e
  if [ "${START_RC}" = "0" ]; then
    run_root "${SCRIPT_DIR}/../tests/test-docker.sh"
  else
    warn "rc.docker start falhou; executando diagnóstico (sem systemd)."
    run_root "${SCRIPT_DIR}/diagnostics.sh" || true
  fi
fi

printf '\n\033[1;34mPróximo passo:\033[0m\n'
printf '  %s\n' 'sudo usermod -aG docker <usuario>'
printf '  %s\n' 'sudo /etc/rc.d/rc.docker status'
ok "Instalação concluída."
exit 0