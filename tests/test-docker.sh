#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - tests/test-docker.sh
# Author: j1m1l0k0 - 2026
# Testes automáticos de pós-instalação (sem systemd):
#   docker version, docker info (cgroup/storage), hello-world,
#   docker buildx version e um build Dockerfile mínimo com `docker build`.
# Os comandos docker são executados via sudo quando o usuário atual não
# pertence ao grupo 'docker' (não adicionamos usuários automaticamente).
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../scripts/lib.sh"

DOK()   { printf '\033[1;32m[OK]\033[0m   %s\n' "$1"; }
DFAIL() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$1"; exit 1; }
DWARN() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }

command -v docker >/dev/null 2>&1 || DFAIL "docker CLI não está no PATH."

# O socket é do grupo docker; executa como root quando necessário.
DOCKER_CMD=(run_root docker)
D() { "${DOCKER_CMD[@]}" "$@"; }

log "→ docker version"
D version || DFAIL "docker version falhou (daemon não respondeu)."
DOK "docker version"

log "→ docker info"
INFO="$(D info 2>&1 || true)"
printf '%s\n' "${INFO}" | head -40
echo "${INFO}" | grep -q 'Server Version' || DFAIL "docker info não mostra o servidor. Diagnóstico: ./scripts/diagnostics.sh"

log "→ docker info --format (cgroup, driver)"
CGV="$(D info --format '{{json .CgroupVersion}}' 2>&1 || true)"
DRV="$(D info --format '{{json .Driver}}' 2>&1 || true)"
ROOTDIR="$(D info --format '{{json .DockerRootDir}}' 2>&1 || true)"
printf 'Cgroup Version : %s\nStorage Driver : %s\nDocker Root Dir: %s\n' "${CGV}" "${DRV}" "${ROOTDIR}"
echo "${DRV}" | grep -qE 'overlay2|vfs|btrfs' || DWARN "Storage driver inesperado: ${DRV}"
DOK "docker info (cgroup=${CGV}, driver=${DRV}, root=${ROOTDIR})"

log "→ docker run --rm hello-world"
if D run --rm hello-world; then
  DOK "hello-world OK"
else
  DFAIL "hello-world falhou (rede? ver /var/log/docker.log)."
fi

log "→ docker buildx version"
if D buildx version; then
  DOK "buildx OK"
else
  DWARN "buildx indisponível (pacote docker-cli sem plugin buildx?)"
fi

log "→ docker build (BuildKit): FROM alpine; RUN echo 'Docker on Slackware works'"
TMPD="$(mktemp -d)"
cat > "${TMPD}/Dockerfile" <<'EOF'
FROM alpine:latest
RUN echo "Docker on Slackware works"
EOF
if D build -t docker-slackware-test "${TMPD}"; then
  DOK "docker build OK"
else
  DFAIL "docker build falhou (BuildKit)."
fi

log "→ docker run da imagem construída"
if D run --rm docker-slackware-test echo "Slackware container OK"; then
  DOK "container de teste OK"
else
  DFAIL "container de teste falhou."
fi

D rmi docker-slackware-test >/dev/null 2>&1 || true
rm -rf "${TMPD}"

DOK "Todos os testes de Docker concluídos com sucesso."
exit 0