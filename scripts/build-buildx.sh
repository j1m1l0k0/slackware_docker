#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-buildx.sh
# Compila o plugin de CLI docker/buildx $BUILDX_VERSION (fonte oficial) e
# deixa o binário em $SRC_DIR/buildx/bin/buildx. Ele é empacotado dentro do
# pacote docker-cli (em /usr/libexec/docker/cli-plugins/docker-buildx),
# espelhando o que os pacotes oficiais .deb/.rpm da Docker fazem.
# Ldflags: github.com/docker/buildx/version.{Package,Version,Revision}
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
go_env

SRC="${SRC_DIR}/buildx"
[ -d "${SRC}/.git" ] || die "Fontes do buildx não baixadas (scripts/download-sources.sh)"

PKG="github.com/docker/buildx"
VERSION_LDFLAGS="-X ${PKG}/version.Package=${PKG} -X ${PKG}/version.Version=v${BUILDX_VERSION} -X ${PKG}/version.Revision=${BUILDX_COMMIT}"

mkdir -p "${SRC}/bin"
log "Compilando docker-buildx ${BUILDX_VERSION} (estático)"
( cd "${SRC}" && \
  CGO_ENABLED=0 \
  go build -mod=vendor -o "${SRC}/bin/buildx" \
    -ldflags "-s -w ${VERSION_LDFLAGS}" \
    ./cmd/buildx )

[ -x "${SRC}/bin/buildx" ] || die "buildx não produzido"
"${SRC}/bin/buildx" version || true

if [ "${RUN_TESTS:-light}" != "none" ]; then
  run_go_tests "${SRC}" "buildx" 600
fi

ok "buildx ${BUILDX_VERSION} compilado (empacotado com o docker-cli)."
exit 0