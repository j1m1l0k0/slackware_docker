#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-cli.sh
# Author: j1m1l0k0 - 2026
# Compila o Docker CLI $CLI_VERSION (docker) a partir do fonte oficial.
# O repositório docker/cli NÃO tem go.mod (usa vendor.mod + vendor/): o
# fluxo oficial compila em modo GOPATH. Reproduzimos isso aqui:
#   $GOPATH/src/github.com/docker/cli + `make binary`
# (scripts/build/binary + scripts/build/.variables, com CGO_ENABLED=0 para
#  um binário estático puro).
# O pacote docker-cli também contém o plugin buildx (docker-buildx) na
# localização oficial /usr/libexec/docker/cli-plugins/ e as completions.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd make
go_env

CLI_DIR="${GOPATH_DIR}/src/github.com/docker/cli"
[ -d "${CLI_DIR}/.git" ] || die "Fontes do CLI não preparadas (scripts/download-sources.sh)"

STAGE="${STAGE_DIR}/docker-cli"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/usr/bin" "${STAGE}/usr/libexec/docker/cli-plugins"
mkdir -p "${STAGE}/usr/share/bash-completion/completions"
mkdir -p "${STAGE}/usr/share/fish/vendor_completions.d"
mkdir -p "${STAGE}/usr/share/zsh/site-functions"

log "Compilando docker CLI ${CLI_VERSION} (GOPATH mode, CGO_ENABLED=0, static)"
# GOFLAGS=-mod=vendor é inválido em GOPATH mode; limpar.
( cd "${CLI_DIR}" && \
  env GOFLAGS= GO111MODULE=auto CGO_ENABLED=0 GO_LINKMODE=static \
  make binary )

TARGET_BIN="$(ls "${CLI_DIR}"/build/docker-linux-* 2>/dev/null | head -1)"
[ -n "${TARGET_BIN}" ] && [ -x "${TARGET_BIN}" ] || die "CLI não gerou build/docker-linux-*"
install -m 0755 "${TARGET_BIN}" "${STAGE}/usr/bin/docker"

# Plugin buildx (construído por build-buildx.sh) entra no pacote do CLI.
BX="${SRC_DIR}/buildx/bin/buildx"
if [ -x "${BX}" ]; then
  install -m 0755 "${BX}" "${STAGE}/usr/libexec/docker/cli-plugins/docker-buildx"
  ok "Plugin buildx incluído em docker-cli."
else
  warn "buildx não encontrado em ${BX}; rode scripts/build-buildx.sh antes. docker buildx ficará indisponível."
fi

# Completions (contrib/completion do próprio projeto)
if [ -d "${CLI_DIR}/contrib/completion/bash" ]; then
  install -m 0644 "${CLI_DIR}/contrib/completion/bash/docker" "${STAGE}/usr/share/bash-completion/completions/docker"
fi
if [ -d "${CLI_DIR}/contrib/completion/fish" ]; then
  install -m 0644 "${CLI_DIR}/contrib/completion/fish/docker.fish" "${STAGE}/usr/share/fish/vendor_completions.d/docker.fish"
fi
if [ -d "${CLI_DIR}/contrib/completion/zsh" ]; then
  install -m 0644 "${CLI_DIR}/contrib/completion/zsh/_docker" "${STAGE}/usr/share/zsh/site-functions/_docker"
fi

install_slack_desc docker-cli "${STAGE}"
make_pkg "docker-cli-${CLI_VERSION}" "${STAGE}"

manifest_add "Docker CLI: ${CLI_VERSION} (${CLI_COMMIT}) [static, GOPATH mode; com buildx ${BUILDX_VERSION}]"
ok "docker-cli ${CLI_VERSION} compilado e empacotado."
exit 0