#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-containerd.sh
# Compila containerd $CONTAINERD_VERSION (estático, como a distribuição
# oficial) a partir do fonte oficial e gera
#   packages/containerd-<version>-<arch>-1.txz
# Binários instalados: /usr/bin/containerd, containerd-shim-runc-v2, ctr,
# containerd-stress.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd make
go_env

SRC="${SRC_DIR}/containerd"
[ -d "${SRC}/.git" ] || die "Fontes do containerd não baixadas (scripts/download-sources.sh)"

# libc.a existe no Slackware -> contrução estática oficial (STATIC=1)
if [ ! -f /usr/lib64/libc.a ] && [ ! -f /usr/lib/libc.a ]; then
  warn "Sem libc estática: contrução dinâmica (desvio do oficial)"
  STATIC_MODE=0
else
  STATIC_MODE=1
fi

STAGE="${STAGE_DIR}/containerd"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/usr/bin"

log "Compilando containerd ${CONTAINERD_VERSION} (STATIC=${STATIC_MODE})"
if [ "${STATIC_MODE}" = "1" ]; then
  if ! ( cd "${SRC}" && make STATIC=1 binaries ); then
    warn "Contrução estática falhou; tentando dinâmica"
    ( cd "${SRC}" && make binaries )
  fi
else
  ( cd "${SRC}" && make binaries )
fi

for b in containerd containerd-shim-runc-v2 ctr containerd-stress; do
  [ -x "${SRC}/bin/${b}" ] || die "binário não produzido: bin/${b}"
done

if [ "${RUN_TESTS:-light}" != "none" ]; then
  run_go_tests "${SRC}" "containerd" 600
fi

for b in containerd containerd-shim-runc-v2 ctr containerd-stress; do
  install -m 0755 "${SRC}/bin/${b}" "${STAGE}/usr/bin/${b}"
done
install_slack_desc containerd "${STAGE}"
make_pkg "containerd-${CONTAINERD_VERSION}" "${STAGE}"

manifest_add "containerd: ${CONTAINERD_VERSION} (${CONTAINERD_COMMIT}) [estático: ${STATIC_MODE}]"
ok "containerd ${CONTAINERD_VERSION} compilado e empacotado."
exit 0