#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/download-sources.sh
# Baixa os fontes oficiais (git, tags exatas) e VERIFICA o commit SHASUM de
# cada checkout contra a matriz em config/versions.conf.
# Também prepara o layout GOPATH do docker/cli (que usa vendor.mod, sem
# go.mod) tal como o fluxo oficial do projeto.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd git curl

FETCH_ONE() { # FETCH_ONE URL TAG NOME COMMIT_ESPERADO
  local url="$1" tag="$2" name="$3" expect="$4"
  local dest="${SRC_DIR}/${name}"
  if [ -d "${dest}/.git" ]; then
    log "Fontes já presentes: ${name} (pulando download)"
  else
    log "Baixando ${name} @ ${tag}"
    mkdir -p "${SRC_DIR}"
    git clone --depth 1 --branch "${tag}" "${url}" "${dest}"
  fi
  local got
  got="$(git -C "${dest}" rev-parse HEAD)"
  if [ "${got}" != "${expect}" ]; then
    die "FONTE NÃO CONFIÁVEL: ${name} HEAD==${got}, esperado ${expect}. Abortando."
  fi
  ok "${name} verificada: ${expect} (${tag})"
}

[ -d "${SRC_DIR}" ] || mkdir -p "${SRC_DIR}"
[ -d "${GOPATH_DIR}/src/github.com/docker" ] || mkdir -p "${GOPATH_DIR}/src/github.com/docker"
[ -d "${GOPATH_DIR}/src/github.com/moby" ] || mkdir -p "${GOPATH_DIR}/src/github.com/moby"

FETCH_ONE "${ENGINE_URL}" "${ENGINE_TAG}" moby "${ENGINE_COMMIT}"
FETCH_ONE "${CLI_URL}" "${CLI_TAG}" cli "${CLI_COMMIT}"
FETCH_ONE "${CONTAINERD_URL}" "${CONTAINERD_TAG}" containerd "${CONTAINERD_COMMIT}"
FETCH_ONE "${RUNC_URL}" "${RUNC_TAG}" runc "${RUNC_COMMIT}"
FETCH_ONE "${BUILDKIT_URL}" "${BUILDKIT_TAG}" buildkit "${BUILDKIT_COMMIT}"
FETCH_ONE "${BUILDX_URL}" "${BUILDX_TAG}" buildx "${BUILDX_COMMIT}"
FETCH_ONE "${TINI_URL}" "${TINI_TAG}" tini "${TINI_COMMIT}"

# GOPATH mode para o cli (sem go.mod na raiz; usa vendor.mod + vendor/).
if [ ! -e "${GOPATH_DIR}/src/github.com/docker/cli" ]; then
  ln -s "${SRC_DIR}/cli" "${GOPATH_DIR}/src/github.com/docker/cli"
fi
ok "Layout GOPATH do docker/cli pronto: ${GOPATH_DIR}/src/github.com/docker/cli -> ${SRC_DIR}/cli"

log "Todos os fontes baixados e verificados."
exit 0