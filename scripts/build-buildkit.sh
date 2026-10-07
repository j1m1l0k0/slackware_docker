#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-buildkit.sh
# Author: j1m1l0k0 - 2026
# Compila BuildKit $BUILDKIT_VERSION (buildkitd + buildctl) do fonte
# oficial e gera packages/buildkit-<version>-<arch>-1.txz em /usr/bin.
#
# O fluxo oficial (`make binaries`) exige Docker buildx (ovo/galinha);
# replicamos os comandos `go build` do Dockerfile oficial do projeto
# (docker-bake.hcl/Dockerfile):
#   buildkitd: tags "seccomp" (e netgo/osusergo/static_build nas releases
#              estáticas); aqui DINÂMICO por falta de libseccomp.a no
#              Slackware (desvio documentado). CGO=1 linka libseccomp.so.
#   buildctl : CGO_ENABLED=0, binário estático.
# Ldflags de versão: github.com/moby/buildkit/version.{Package,Version,Revision}
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
go_env

SRC="${SRC_DIR}/buildkit"
[ -d "${SRC}/.git" ] || die "Fontes do BuildKit não baixadas (scripts/download-sources.sh)"

STAGE="${STAGE_DIR}/buildkit"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/usr/bin"

PKG="github.com/moby/buildkit"
VERSION_LDFLAGS="-X ${PKG}/version.Package=${PKG} -X ${PKG}/version.Version=v${BUILDKIT_VERSION} -X ${PKG}/version.Revision=${BUILDKIT_COMMIT}"

log "Compilando buildctl (estático)"
( cd "${SRC}" && \
  CGO_ENABLED=0 \
  go build -mod=vendor -o "${STAGE}/usr/bin/buildctl" \
    -ldflags "-s -w ${VERSION_LDFLAGS}" \
    ./cmd/buildctl )

log "Compilando buildkitd (dinâmico, seccomp via libseccomp.so)"
( cd "${SRC}" && \
  CGO_ENABLED=1 \
  go build -mod=vendor -tags "seccomp" \
    -o "${STAGE}/usr/bin/buildkitd" \
    -ldflags "-s -w ${VERSION_LDFLAGS}" \
    ./cmd/buildkitd )

"${STAGE}/usr/bin/buildctl" version || true
"${STAGE}/usr/bin/buildkitd" --version || true

if [ "${RUN_TESTS:-light}" != "none" ]; then
  run_go_tests "${SRC}" "buildkit" 600
fi

install_slack_desc buildkit "${STAGE}"
make_pkg "buildkit-${BUILDKIT_VERSION}" "${STAGE}"

manifest_add "BuildKit: ${BUILDKIT_VERSION} (${BUILDKIT_COMMIT}) [buildkitd dinâmico/com seccomp; buildctl estático]"
ok "buildkit ${BUILDKIT_VERSION} compilado e empacotado."
exit 0