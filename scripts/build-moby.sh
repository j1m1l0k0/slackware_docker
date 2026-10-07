#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-moby.sh
# Author: j1m1l0k0 - 2026
# Compila Docker Engine (Moby) $ENGINE_VERSION a partir do fonte oficial.
#
# O fluxo oficial usa `docker buildx bake`; aqui replicamos EXATAMENTE os
# comandos `go build` dos scripts oficiais do projeto (hack/make/dynbinary-*,
# hack/make/.binary, hack/make/.go-autogen) nativamente, sem precisar de
# Docker:
#   dockerd       -> cmd/dockerd       (tags: nri_no_wasm, -buildmode=pie)
#   docker-proxy  -> cmd/docker-proxy  (tags: nri_no_wasm, -buildmode=pie)
#   docker-init   -> tini $TINI_VERSION (cmake, como hack/dockerfile/install/tini.installer)
# Ver também daemon/graphdriver.priority=overlay2 (uso recomendado para o
# driver de storage; mesmo padrão usado no exemplo do Makefile do Moby).
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd make cmake
go_env

SRC="${SRC_DIR}/moby"
TINI="${SRC_DIR}/tini"
[ -d "${SRC}/.git" ] || die "Fontes do Moby não baixadas (scripts/download-sources.sh)"
[ -d "${TINI}/.git" ] || die "Fontes do tini não baixadas (scripts/download-sources.sh)"

STAGE="${STAGE_DIR}/docker-engine"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/usr/bin" "${STAGE}/usr/libexec/docker"

GITCOMMIT="${ENGINE_COMMIT}"
VERSION="${ENGINE_VERSION}"
# Formato compatível com o oficial (RFC3339, sem espaço)
BUILDTIME="$(TZ=UTC date -u --rfc-3339=ns | sed 's/ /T/')"
PLATFORM="linux/${PKGARCH}"
PRODUCT="Docker Engine"
LICENSE="Apache-2.0"

LDFLAGS="-w \
  -X \"github.com/moby/moby/v2/dockerversion.Version=${VERSION}\" \
  -X \"github.com/moby/moby/v2/dockerversion.GitCommit=${GITCOMMIT}\" \
  -X \"github.com/moby/moby/v2/dockerversion.BuildTime=${BUILDTIME}\" \
  -X \"github.com/moby/moby/v2/dockerversion.PlatformName=${PLATFORM}\" \
  -X \"github.com/moby/moby/v2/dockerversion.ProductName=${PRODUCT}\" \
  -X \"github.com/moby/moby/v2/dockerversion.DefaultProductLicense=${LICENSE}\""

# Mesma preferência do Makefile do Moby: overlay2 antes de zfs/vfs
DOCKER_LDFLAGS="-X github.com/moby/moby/v2/daemon/graphdriver.priority=overlay2"

# Tags usadas pelo dynbinary oficial: nri_no_wasm (netgo/osusergo/static_build removidos)
BUILDTAGS="nri_no_wasm"

log "Compilando dockerd (dynamic, tags: ${BUILDTAGS})"
( cd "${SRC}" && \
  CGO_ENABLED=1 \
  go build -mod=vendor -tags "${BUILDTAGS}" -buildmode=pie \
    -o "${STAGE}/usr/bin/dockerd" \
    -ldflags "${LDFLAGS} ${DOCKER_LDFLAGS}" \
    ./cmd/dockerd )

log "Compilando docker-proxy (dynamic)"
( cd "${SRC}" && \
  CGO_ENABLED=1 \
  go build -mod=vendor -tags "${BUILDTAGS}" -buildmode=pie \
    -o "${STAGE}/usr/libexec/docker/docker-proxy" \
    -ldflags "${LDFLAGS}" \
    ./cmd/docker-proxy )

log "Compilando docker-init (tini ${TINI_VERSION})"
( cd "${TINI}" && \
  cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 . >/dev/null && \
  make tini-static )
[ -x "${TINI}/tini-static" ] || die "tini-static não produzido"
install -m 0755 "${TINI}/tini-static" "${STAGE}/usr/libexec/docker/docker-init"

"${STAGE}/usr/bin/dockerd" --version || true
"${STAGE}/usr/libexec/docker/docker-proxy" --version || true

if [ "${RUN_TESTS:-light}" != "none" ]; then
  run_go_tests "${SRC}/daemon" "moby/daemon" 600
fi

install_slack_desc docker-engine "${STAGE}"
# doinst.sh: cria o grupo docker na instalação (padrão Slackware via chroot)
cat > "${STAGE}/install/doinst.sh" <<'EOF'
#!/bin/sh
# Cria o grupo 'docker' (gid 263 preferido; senão gid automático)
if ! grep -q '^docker:' etc/group 2>/dev/null; then
  chroot . /usr/sbin/groupadd -g 263 docker 2>/dev/null || \
  chroot . /usr/sbin/groupadd docker 2>/dev/null || true
fi
# Descarta o PID file residual de uma execução anterior
if [ -f var/run/docker.pid ]; then
  if ! kill -0 "$(cat var/run/docker.pid 2>/dev/null)" 2>/dev/null; then
    rm -f var/run/docker.pid
  fi
fi
EOF
chmod 0755 "${STAGE}/install/doinst.sh"

make_pkg "docker-engine-${ENGINE_VERSION}" "${STAGE}"

manifest_add "Docker Engine: ${ENGINE_VERSION} (${ENGINE_COMMIT}) dockerd/docker-proxy dynamic, docker-init=tini-${TINI_VERSION}"
ok "docker-engine ${ENGINE_VERSION} compilado e empacotado."
exit 0