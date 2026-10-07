#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/build-go-toolchain.sh
# Author: j1m1l0k0 - 2026
# Baixa e instala o toolchain Go oficial em ~/docker-slackware/toolchain/go
# (isolado do sistema), com verificação de sha256 a partir do JSON oficial
# de go.dev/dl. NENHUM binário é instalado em diretórios do sistema.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd curl tar sha256sum

mkdir -p "${DL_DIR}" "${TOOLCHAIN_DIR}"

TGZ="${DL_DIR}/${GO_TGZ}"

if [ -x "${GOBIN_DIR}/go" ]; then
  cur="$( "${GOBIN_DIR}/go" version )"
  case "${cur}" in
    *"go${GO_VERSION}"*) ok "Toolchain Go ${GO_VERSION} já presente em ${GOROOT_DIR}"; exit 0 ;;
    *) warn "Toolchain Go incompatível em ${GOROOT_DIR}: ${cur}; substituindo por ${GO_VERSION}" ;;
  esac
fi

if [ ! -f "${TGZ}" ]; then
  log "Baixando ${GO_URL} (oficial go.dev)"
  curl -fSL --retry 3 -o "${TGZ}" "${GO_URL}"
fi

log "Verificando sha256 de ${TGZ}"
actual="$(sha256sum "${TGZ}" | awk '{print $1}')"
if [ "${actual}" != "${GO_SHA256}" ]; then
  # Insiste no valor do JSON oficial por conta própria, sem inventar:
  fetch="$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json&include=all' | python3 -c "
import json,sys
want='${GO_TGZ}'
for r in json.load(sys.stdin):
    if r.get('version') != 'go${GO_VERSION}':
        continue
    for f in r['files']:
        if f['filename'] == want:
            print(f['sha256']); break
" 2>/dev/null || true)"
  if [ -n "${fetch}" ] && [ "${fetch}" != "${GO_SHA256}" ]; then
    die "sha256 inesperado: download=${actual}, versions.conf=${GO_SHA256}, dance oficial=${fetch}. NÃO instalando."
  fi
  die "sha256 inválido para ${GO_TGZ}: obtido=${actual} esperado=${GO_SHA256}. Delete ${TGZ} e tente novamente."
fi
ok "sha256 verificado: ${actual}"

# Extrai o toolchain (destruímos apenas o diretório isolado do projeto)
rm -rf "${GOROOT_DIR}"
mkdir -p "${GOROOT_DIR}"
tar -C "${GOROOT_DIR}" --strip-components=1 -xzf "${TGZ}"

if ! go_version_ok; then
  die "Toolchain instalado não relata go${GO_VERSION}: $( "${GOBIN_DIR}/go" version )"
fi
ok "Go ${GO_VERSION} pronto: ${GOBIN_DIR}"
exit 0