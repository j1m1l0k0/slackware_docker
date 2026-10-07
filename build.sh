#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - build.sh (ponto de entrada)
# Author: j1m1l0k0 - 2026
#
# Pipeline completo:
#   1. check-system.sh     (Slackware 15.0, kernel, cgroup, deps)
#   2. build-go-toolchain.sh (Go oficial, sha256 verificado)
#   3. download-sources.sh (fontes oficiais pinados + verificação de commit)
#   4. builds (runc, containerd, moby, buildx, cli, buildkit)
#   5. packages/*.txz + CHECKSUMS.sha256 + docker-build-manifest.txt
#
# Uso:
#   ./build.sh                  # pipeline completa (sem instalar)
#   ./build.sh <componente>     # compila um único: runc|containerd|moby|cli|buildkit|buildx
#   ./build.sh check|go|download
#   ./build.sh install          # atalho para scripts/install.sh
#   ./build.sh --run-tests      # roda testes Go (full) durante os builds
#   ./build.sh --skip-check     # pula a checagem de sistema
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/scripts/lib.sh"

RUN_TESTS="${RUN_TESTS:-light}"
SKIP_CHECK=0
CMD="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --run-tests) RUN_TESTS="full" ;;
    --skip-check) SKIP_CHECK=1 ;;
    check|go|download|runc|containerd|moby|cli|buildkit|buildx|install|all) CMD="$1" ;;
    *) die "Argumento desconhecido: $1 (uso: ./build.sh [componente] [--run-tests] [--skip-check])" ;;
  esac
  shift
done
export RUN_TESTS

load_versions

case "${CMD}" in
  check)
    "${BASE_DIR}/scripts/check-system.sh"
    ;;
  go)
    "${BASE_DIR}/scripts/build-go-toolchain.sh"
    ;;
  download)
    [ "${SKIP_CHECK}" = "1" ] || "${BASE_DIR}/scripts/check-system.sh"
    "${BASE_DIR}/scripts/download-sources.sh"
    ;;
  runc|containerd|moby|cli|buildkit|buildx)
    [ "${SKIP_CHECK}" = "1" ] || "${BASE_DIR}/scripts/check-system.sh"
    "${BASE_DIR}/scripts/download-sources.sh"
    "${BASE_DIR}/scripts/build-go-toolchain.sh"
    case "${CMD}" in
      runc)       B="build-runc.sh" ;;
      containerd) B="build-containerd.sh" ;;
      moby)       B="build-moby.sh" ;;
      buildx)     B="build-buildx.sh" ;;
      buildkit)   B="build-buildkit.sh" ;;
      cli)        B="build-cli.sh" ;;
    esac
    init_manifest
    "${BASE_DIR}/scripts/${B}"
    ;;
  install)
    "${BASE_DIR}/scripts/install.sh"
    ;;
  all)
    [ "${SKIP_CHECK}" = "1" ] || "${BASE_DIR}/scripts/check-system.sh"
    "${BASE_DIR}/scripts/build-go-toolchain.sh"
    "${BASE_DIR}/scripts/download-sources.sh"
    init_manifest
    log "=== Compilando todos os componentes (sequencialmente) ==="
    for s in build-runc build-containerd build-moby build-buildx build-cli build-buildkit; do
      "${BASE_DIR}/scripts/${s}.sh"
    done
    finalize_manifest
    log "=== Pipeline concluído ==="
    ;;
esac

exit 0