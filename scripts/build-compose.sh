#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-compose.sh
# Author: j1m1l0k0 - 2026
# Compila o plugin de CLI docker/compose $COMPOSE_VERSION (fonte oficial,
# tag v5.6.0 verificada) e deixa o binário em $SRC_DIR/compose/bin/build/
# docker-compose. Ele é empacotado dentro do pacote docker-cli (em
# /usr/libexec/docker/cli-plugins/docker-compose), espelhando o pacote
# oficial docker-compose-plugin (.deb/.rpm) da Docker.
# Reproduz o alvo `make build` oficial do projeto (link do Makefile oficial):
#   GO111MODULE=on go build -trimpath -tags "e2e"
#     -ldflags "-w -X github.com/docker/compose/v5/internal.Version=v5.6.0"
#     -o bin/build/docker-compose ./cmd
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
go_env

SRC="${SRC_DIR}/compose"
[ -d "${SRC}/.git" ] || die "Fontes do compose não baixadas (scripts/download-sources.sh)"

PKG="github.com/docker/compose/v5"
VERSION_LDFLAGS="-X ${PKG}/internal.Version=v${COMPOSE_VERSION}"

# O repositório possui vendor/ comitado (mesmo caso do buildx); se ausente,
# usa -mod=mod (dependências baixadas na build, como no fluxo oficial).
if [ -d "${SRC}/vendor" ]; then
  MODE_FLAG="-mod=vendor"
else
  MODE_FLAG="-mod=mod"
fi

mkdir -p "${SRC}/bin/build"
log "Compilando docker-compose ${COMPOSE_VERSION} (plugin CLI, estático)"
( cd "${SRC}" && \
  CGO_ENABLED=0 GOFLAGS="${MODE_FLAG}" \
  go build -trimpath -tags "e2e" \
    -ldflags "-s -w ${VERSION_LDFLAGS}" \
    -o "${SRC}/bin/build/docker-compose" \
    ./cmd )

[ -x "${SRC}/bin/build/docker-compose" ] || die "docker-compose não produzido"
"${SRC}/bin/build/docker-compose" version || true

if [ "${RUN_TESTS:-light}" != "none" ]; then
  run_go_tests "${SRC}" "compose" 900
fi

manifest_add "docker-compose: ${COMPOSE_VERSION} (${COMPOSE_COMMIT}) [plugin CLI \"docker compose\"; estático]"
ok "docker-compose ${COMPOSE_VERSION} compilado (empacotado com o docker-cli)."
exit 0