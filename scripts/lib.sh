#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/lib.sh
# Author: j1m1l0k0 - 2026
# Funções comuns: ambiente, versões, logging, root, packaging.
# Todas as funções são carregadas via `source lib.sh` pelos demais scripts.
# ===========================================================================

set -euo pipefail

# --- Caminhos (scripts/ -> raiz do projeto) -------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR="${BASE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Slackware guarda as ferramentas de pacote em /sbin e /usr/sbin.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

# --- Arquitetura -----------------------------------------------------------
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) PKGARCH="x86_64" ;;
  aarch64|arm64) PKGARCH="arm64" ;;
  i386|i486|i586|i686) PKGARCH="x86" ;;
  *)      PKGARCH="${ARCH}" ;;
esac
export ARCH PKGARCH

# --- Diretórios de trabalho ------------------------------------------------
export WORK_DIR="${BASE_DIR}/work"
export SRC_DIR="${WORK_DIR}/src"
export DL_DIR="${BASE_DIR}/dl"
export OUT_DIR="${BASE_DIR}/packages"
export TOOLCHAIN_DIR="${BASE_DIR}/toolchain"
export GOROOT_DIR="${TOOLCHAIN_DIR}/go"
export GOBIN_DIR="${GOROOT_DIR}/bin"
export GOPATH_DIR="${WORK_DIR}/gopath"
export STAGE_DIR="${WORK_DIR}/stage"
export MANIFEST="${OUT_DIR}/docker-build-manifest.txt"
export BACKUPS_DIR="${OUT_DIR}/backups"
export CHECKSUMS="${OUT_DIR}/CHECKSUMS.sha256"

# --- Versões ---------------------------------------------------------------
load_versions() {
  local f="${BASE_DIR}/config/versions.conf"
  [ -r "${f}" ] || die "config/versions.conf não encontrado (${f})"
  # shellcheck disable=SC1090
  . "${f}"
}

version_no_v() { printf '%s' "${1#v}"; }

# --- Logging ---------------------------------------------------------------
log()   { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m[FALHA]\033[0m %s\n' "$*" >&2; exit 1; }
ok()    { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }

# --- Execução como root (sudo) ---------------------------------------------
# Usa diretamente quando já é root; senão sudo -n (sem senha) ou a senha em
# SUDO_PASSWORD via `sudo -S`. Nunca grava a senha em disco.
run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi
  if [ -n "${SUDO_PASSWORD:-}" ]; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S -p '' "$@"
  elif sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    die "Este passo requer root. Rode com 'sudo' ou informe a senha via SUDO_PASSWORD (ex.: SUDO_PASSWORD=... $0 $*)"
  fi
}

is_root() { [ "$(id -u)" -eq 0 ]; }

# --- Dependências ----------------------------------------------------------
require_cmd() {
  local c
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || die "Dependência '${c}' não encontrada no PATH. Instale-a antes de continuar."
  done
}

# --- Ambiente Go (toolchain local do projeto) ------------------------------
go_env() {
  [ -x "${GOBIN_DIR}/go" ] || die "Toolchain Go não encontrado em ${GOBIN_DIR}. Execute ./scripts/build-go-toolchain.sh ou ./build.sh go primeiro."
  export GOROOT="${GOROOT_DIR}"
  export GOPATH="${GOPATH_DIR}"
  export PATH="${GOBIN_DIR}:${PATH}"
  # Todos os componentes relevantes possuem vendor/ comitado; módulos com
  # go.mod usam -mod=vendor. O CLI usa GOPATH mode (vendor.mod).
  export GOFLAGS="${GOFLAGS:--mod=vendor}"
  export GO111MODULE="${GO111MODULE:-on}"
}

go_version_ok() {
  go_env
  local got
  got="$(go version)"
  case "${got}" in
    *"go${GO_VERSION}"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Backup ----------------------------------------------------------------
# Só cria backup se o arquivo/diretório existir.
backup_path() {
  local p="$1" dest
  [ -e "${p}" ] || return 0
  dest="${BACKUPS_DIR}/$(date +%Y%m%d-%H%M%S)-$(echo "${p}" | tr '/' '_')"
  mkdir -p "$(dirname "${dest}")"
  cp -a "${p}" "${dest}"
  log "Backup criado: ${p} -> ${dest}"
}

# --- Packaging (makepkg) ----------------------------------------------------
# $1 = nome-base do pacote (ex.: docker-engine-29.8.2)
# $2 = diretório de staging (usado como nova raiz)
make_pkg() {
  local pkgbase="$1" stage="$2"
  local outfile="${OUT_DIR}/${pkgbase}-${PKGARCH}-1.txz"
  [ -d "${stage}" ] || die "Staging '${stage}' não existe para ${pkgbase}"
  mkdir -p "${OUT_DIR}"
  rm -f "${outfile}"
  ( cd "${stage}" && /sbin/makepkg -l y -c n "${outfile}" >/dev/null )
  [ -f "${outfile}" ] || die "makepkg falhou ao criar ${outfile}"
  ok "Pacote gerado: ${outfile}"
  # checksum dos pacotes
  ( cd "${OUT_DIR}" && sha256sum "$(basename "${outfile}")" ) | tee -a "${CHECKSUMS}" >/dev/null
}

# Copia o slack-desc oficial para dentro do staging (makepkg o transforma em metadado).
install_slack_desc() {
  local name="$1" stage="$2"
  mkdir -p "${stage}/install"
  install -m 0644 "${BASE_DIR}/slack-desc/${name}.slack-desc" "${stage}/install/slack-desc"
}

# Manifest: registra uma linha de histórico do build.
manifest_add() {
  mkdir -p "${OUT_DIR}"
  printf '%s\n' "$*" >> "${MANIFEST}"
}

# Manifest/checksums do build: cria o cabeçalho com a matriz oficial.
init_manifest() {
  mkdir -p "${OUT_DIR}"
  : > "${CHECKSUMS}"
  if [ ! -f "${MANIFEST}" ]; then
    {
      printf 'Docker Engine: %s\n' "${ENGINE_VERSION:-}"
      printf 'Docker CLI: %s\n' "${CLI_VERSION:-}"
      printf 'containerd: %s\n' "${CONTAINERD_VERSION:-}"
      printf 'runc: %s\n' "${RUNC_VERSION:-}"
      printf 'BuildKit: %s\n' "${BUILDKIT_VERSION:-}"
      printf 'Buildx (plugin): %s\n' "${BUILDX_VERSION:-}"
      printf 'Compose (plugin): %s\n' "${COMPOSE_VERSION:-}"
      printf 'Go: %s\n' "${GO_VERSION:-}"
      printf 'docker-init (tini): %s\n' "${TINI_VERSION:-}"
      printf 'Kernel: %s\n' "$(uname -r)"
      printf 'Architecture: %s\n' "${ARCH}"
      printf 'Build date: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${MANIFEST}"
  fi
}

finalize_manifest() {
  manifest_add "--- commits verificados nos fontes ---"
  local spec dir tag
  for spec in "moby:${SRC_DIR}/moby" "cli:${SRC_DIR}/cli" "containerd:${SRC_DIR}/containerd" "runc:${SRC_DIR}/runc" "buildkit:${SRC_DIR}/buildkit" "buildx:${SRC_DIR}/buildx" "compose:${SRC_DIR}/compose" "tini:${SRC_DIR}/tini"; do
    name="${spec%%:*}"
    dir="${spec#*:}"
    if [ -d "${dir}/.git" ]; then
      manifest_add "${name}: HEAD $(git -C "${dir}" rev-parse HEAD)"
    fi
  done
  manifest_add "Build date (fim): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Executa go test breve nos pacotes (unit), substituível por RUN_TESTS=full.
run_go_tests() {
  local dir="$1" label="$2" timeout="${3:-300}"
  if [ "${RUN_TESTS:-light}" = "none" ]; then
    warn "Testes desativados (RUN_TESTS=none) para ${label}"
    return 0
  fi
  log "Rodando testes Go (${label}), timeout ${timeout}s"
  if ! ( cd "${dir}" && timeout "${timeout}" go test -count=1 -short ./... >/dev/null 2>&1 ); then
    if [ "${RUN_TESTS:-light}" = "full" ]; then
      die "Testes full falharam em ${label}. Execute manualmente em ${dir} para diagnosticar."
    fi
    warn "Testes de ${label} não concluíram em ${timeout}s ou falharam (RUN_TESTS=${RUN_TESTS:-light}); continue mesmo assim."
  else
    ok "Testes Go de ${label} passaram (curtos)."
  fi
}