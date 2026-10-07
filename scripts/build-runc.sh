#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-runc.sh
# Author: j1m1l0k0 - 2026
# Compila runc $RUNC_VERSION a partir do fonte oficial e gera
#   packages/runc-<version>-<arch>-1.txz
# Build tags oficiais: "seccomp urfave_cli_no_docs libpathrs"
# Desvio: sem a biblioteca C libpathrs (compilada com Rust e embarcada nos
# binários oficiais), o runc usa o fallback oficial "pathrslite" (tag
# `!libpathrs` em features_pathrslite.go) — configuração de build suportada
# pelo projeto, sem perda de funcionalidade para o Docker Engine.
# Nota: sem libseccomp.a no Slackware o binário é dinâmico (libseccomp.so),
# desvio documentado em relação ao lançamento estático oficial.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd make
go_env

SRC="${SRC_DIR}/runc"
[ -d "${SRC}/.git" ] || die "Fontes do runc não baixadas (scripts/download-sources.sh)"

STAGE="${STAGE_DIR}/runc"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/usr/bin"

log "Compilando runc ${RUNC_VERSION} (seccomp + pathrslite fallback)"
( cd "${SRC}" && \
  CGO_ENABLED=1 \
  make BUILDTAGS="seccomp urfave_cli_no_docs" )
[ -x "${SRC}/runc" ] || die "make runc não produziu ./runc"

"${SRC}/runc" --version
if [ "${RUN_TESTS:-light}" != "none" ]; then
  run_go_tests "${SRC}" "runc" 600
fi

install -m 0755 "${SRC}/runc" "${STAGE}/usr/bin/runc"
install_slack_desc runc "${STAGE}"
make_pkg "runc-${RUNC_VERSION}" "${STAGE}"

manifest_add "runc: ${RUNC_VERSION} (${RUNC_COMMIT}) [tags: seccomp urfave_cli_no_docs; sem libpathrs -> fallback pathrslite; dinâmico: libseccomp.so]"
ok "runc ${RUNC_VERSION} compilado e empacotado."
exit 0