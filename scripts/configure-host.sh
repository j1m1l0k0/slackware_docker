#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/configure-host.sh
# Configura o Slackware 15.0 para rodar o Docker corretamente:
#   - módulos do kernel (carregados; persistência via rc.docker no boot)
#   - sysctl (/etc/sysctl.d/99-docker.conf - Slackware aplica via rc.S)
#   - /etc/docker/daemon.json (validado, sem sobrescrever configuração do usuário)
#   - /etc/rc.d/rc.docker + entrada no rc.local
#   - grupo 'docker'
#   - iptables: NENHUM flush/exclusão de regras; o dockerd gerencia as
#     próprias chains (nat/filter) conforme "iptables": true.
#
# NÃO faz alterações destrutivas em firewall, /var/lib/docker ou
# /var/lib/containerd. Sempre gera backups antes de modificar arquivos.
# Execute como root (ou com SUDO_PASSWORD setada).
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd python3 sysctl modprobe groupadd

# ---------------------------------------------------------------------------
# 1) Módulos de kernel (carregamento imediato; sem persistência fora do
#    rc.docker, que carrega de novo a cada start)
# ---------------------------------------------------------------------------
log "Carregando módulos de kernel necessários"
MODULES="overlay br_netfilter bridge ip_tables iptable_nat iptable_filter nf_nat nf_conntrack xt_MASQUERADE xt_addrtype ip6_tables veth"
for m in ${MODULES}; do
  if run_root /sbin/modprobe -n "${m}" 2>/dev/null; then
    run_root /sbin/modprobe "${m}" 2>/dev/null && log "  módulo ${m} carregado" || warn "  falha ao carregar ${m}"
  else
    warn "  módulo ${m} indisponível neste kernel"
  fi
done

# ---------------------------------------------------------------------------
# 2) sysctl - /etc/sysctl.d/99-docker.conf
#    (Slackware 15.0: /etc/rc.d/rc.S executa `/sbin/sysctl -e --system`,
#     que processa /etc/sysctl.d/*.conf - verificado no sistema)
# ---------------------------------------------------------------------------
SYSCTL_FILE=/etc/sysctl.d/99-docker.conf
SYSCTL_KEYS=(
  "net.ipv4.ip_forward=1"
  "net.ipv6.conf.all.forwarding=1"
  "net.bridge.bridge-nf-call-iptables=1"
  "net.bridge.bridge-nf-call-ip6tables=1"
)
log "Configurando sysctl (${SYSCTL_FILE})"
# Backup de qualquer versão anterior/proprietária.
if [ -e "${SYSCTL_FILE}" ]; then
  backup_path "${SYSCTL_FILE}"
  if grep -q '# docker-slackware' "${SYSCTL_FILE}" 2>/dev/null; then
    log "  removendo entrada anterior docker-slackware para recriar"
    run_root rm -f "${SYSCTL_FILE}"
  else
    warn "  ${SYSCTL_FILE} existente será preservado; adicionando apenas chaves ausentes"
  fi
fi
TMP_SYSCTL="$(mktemp)"
{
  echo "# docker-slackware ($(date '+%Y-%m-%d %H:%M:%S'))"
  echo "# Configurações de rede necessárias para o Docker Engine."
  for k in "${SYSCTL_KEYS[@]}"; do
    key="${k%%=*}"
    if [ -e "${SYSCTL_FILE}" ] && grep -q "^${key}=" "${SYSCTL_FILE}"; then
      continue
    fi
    echo "${k}"
  done
} > "${TMP_SYSCTL}"
if [ -s "${TMP_SYSCTL}" ]; then
  run_root install -m 0644 "${TMP_SYSCTL}" "${SYSCTL_FILE}"
fi
rm -f "${TMP_SYSCTL}"

log "Aplicando sysctl imediatamente"
set +e
run_root sysctl -w net.ipv4.ip_forward=1
run_root sysctl -w net.ipv6.conf.all.forwarding=1
# bridge-nf só se o módulo br_netfilter estiver carregado
if grep -qw br_netfilter /proc/modules 2>/dev/null; then
  run_root sysctl -w net.bridge.bridge-nf-call-iptables=1
  run_root sysctl -w net.bridge.bridge-nf-call-ip6tables=1
fi
set -e

# ---------------------------------------------------------------------------
# 3) Diretórios de dados
# ---------------------------------------------------------------------------
log "Criando diretórios de dados"
run_root mkdir -p /etc/docker /var/lib/docker /var/lib/containerd
run_root chmod 0711 /var/lib/docker
run_root chmod 0711 /var/lib/containerd

# ---------------------------------------------------------------------------
# 4) daemon.json (criar somente se não existir; nunca sobrescrever usuário)
# ---------------------------------------------------------------------------
DAEMON_JSON=/etc/docker/daemon.json
if [ -e "${DAEMON_JSON}" ]; then
  backup_path "${DAEMON_JSON}"
  warn "${DAEMON_JSON} já existe: NÃO foi modificado (backup em ${BACKUPS_DIR}). Se precisar da configuração padrão do projeto, copie de config/daemon.json manualmente."
else
  # overlay2 requer filesystem com suporte (d_type). ext4/xfs/btrfs: ok.
  ROOTFS="$(awk '$2=="/"{print $3}' /proc/mounts 2>/dev/null)"
  DRIVER="overlay2"
  case "${ROOTFS}" in
    ext4|xfs|btrfs) : ;;
    *) warn "Filesystem raiz '${ROOTFS}': overlay2 não garantido; usando vfs"
       DRIVER="vfs" ;;
  esac
  log "Criando ${DAEMON_JSON} (storage-driver=${DRIVER})"
  DAEMON_TMP="$(mktemp)"
  python3 - "${DRIVER}" "${DAEMON_TMP}" <<'PYEOF'
import json, sys
driver, path = sys.argv[1], sys.argv[2]
cfg = {
    "storage-driver": driver,
    "iptables": True,
    "ip6tables": True,
    "features": {"buildkit": True},
    "log-driver": "json-file",
    "log-opts": {"max-size": "10m", "max-file": "3"},
}
with open(path, "w") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")
PYEOF
  # Validação do JSON antes de instalar
  python3 -m json.tool "${DAEMON_TMP}" >/dev/null || die "daemon.json gerado é inválido"
  run_root install -m 0644 "${DAEMON_TMP}" "${DAEMON_JSON}"
  rm -f "${DAEMON_TMP}"
  ok "daemon.json criado e validado"
fi

# ---------------------------------------------------------------------------
# 5) rc.docker + rc.local (init tradicional do Slackware)
# ---------------------------------------------------------------------------
RC_DOCKER=/etc/rc.d/rc.docker
backup_path "${RC_DOCKER}"
log "Instalando ${RC_DOCKER}"
run_root install -m 0755 "${BASE_DIR}/config/rc.docker" "${RC_DOCKER}"

RC_LOCAL=/etc/rc.d/rc.local
log "Habilitando docker no boot via ${RC_LOCAL}"
backup_path "${RC_LOCAL}"
# Bloco idempotente com marcadores
BLOCK_START='#<<docker-slackware:start>>'
BLOCK_END='#<<docker-slackware:end>>'
if grep -q "${BLOCK_START}" "${RC_LOCAL}" 2>/dev/null; then
  log "  rc.local já possui o bloco docker-slackware"
else
  TMP_RC="$(mktemp)"
  cp -a "${RC_LOCAL}" "${TMP_RC}"
  {
    echo ""
    echo "${BLOCK_START}"
    echo "# Inicia o Docker na inicialização se /etc/rc.d/rc.docker estiver habilitado."
    echo "# Remova este bloco para desabilitar (ou remova a permissão de execução"
    echo "# de /etc/rc.d/rc.docker)."
    echo 'if [ -x /etc/rc.d/rc.docker ]; then'
    echo '  /etc/rc.d/rc.docker start > /dev/null 2>&1'
    echo 'fi'
    echo "${BLOCK_END}"
  } >> "${TMP_RC}"
  run_root install -m 0755 "${TMP_RC}" "${RC_LOCAL}"
  rm -f "${TMP_RC}"
  log "  bloco de boot adicionado em ${RC_LOCAL}"
fi

# ---------------------------------------------------------------------------
# 6) Grupo docker
# ---------------------------------------------------------------------------
if run_root /usr/sbin/groupadd -g 263 docker 2>/dev/null || \
   run_root /usr/sbin/groupadd docker 2>/dev/null; then
  ok "Grupo 'docker' criado"
elif run_root /usr/bin/getent group docker >/dev/null 2>&1; then
  ok "Grupo 'docker' já existe"
else
  warn "Não foi possível criar o grupo 'docker'"
fi

log ""
printf 'Instrução para o primeiro usuário UTF-8 correto:\n'
printf '  sudo usermod -aG docker <usuario>\n'
printf 'AVISO DE SEGURANÇA: pertencer ao grupo docker equivale, na prática, a\n'
printf 'possuir privilégios elevados sobre o host (root sem senha para o socket\n'
printf 'do daemon). Apenas adicione usuários em quem confia.\n\n'

ok "Configuração do host concluída."
exit 0