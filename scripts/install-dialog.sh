#!/usr/bin/env bash
# ===========================================================================
# docker-slackware - scripts/install-dialog.sh
# Instalador com interface gráfica baseado em "dialog" (ferramenta padrão do
# Slackware). A instalação dos pacotes usa o INSTALADOR OFICIAL DO SLACKWARE
# (/sbin/installpkg e /sbin/upgradepkg --reinstall --install-new — o mesmo
# motor usado pelo pkgtool/setup), envolvido na interface própria:
#   - seleção de componentes (checklist)
#   - barra de progresso (gauge) por pacote
#   - exibição em tempo real dos ARQUIVOS sendo instalados (lista extraída do
#     próprio pacote .txz que o installpkg está descompactando)
#   - tempo decorrido por pacote, tempo MÉDIO e ETA restante
#
# Uso:
#   sudo scripts/install-dialog.sh            # modo interativo (dialog)
#   sudo scripts/install-dialog.sh --noninteractive [--no-tests]
#                                             # automação (sem dialog)
# Log detalhado: packages/install-dialog.log
# ===========================================================================
# Author: j1m1l0k0 - 2026
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

load_versions

# --- Opções ---------------------------------------------------------------
NONINTERACTIVE=0
RUN_TESTS=1
for a in "$@"; do
  case "${a}" in
    --noninteractive) NONINTERACTIVE=1 ;;
    --no-tests)       RUN_TESTS=0 ;;
    --help|-h)
      printf '%s\n' "Uso: sudo $0 [--noninteractive] [--no-tests]" ; exit 0 ;;
    *) die "Argumento desconhecido: ${a} (uso: $0 [--noninteractive] [--no-tests])" ;;
  esac
done

# --- Requisitos -----------------------------------------------------------
if [ "$(id -u)" != 0 ]; then
  echo "Este instalador precisa de root. Execute: sudo $0 $*"
  exit 1
fi

LOG="${OUT_DIR}/install-dialog.log"
mkdir -p "${OUT_DIR}"
: > "${LOG}"
tee_log() { tee -a "${LOG}"; }

BACKTITLE="Docker para Slackware 15.0 - Instalador (dialog)"
# Ordem de instalação respeitando dependências
ORDER=(runc containerd docker-engine docker-cli buildkit)
# nome -> versão
VER() {
  case "$1" in
    runc)          printf '%s' "${RUNC_VERSION}" ;;
    containerd)    printf '%s' "${CONTAINERD_VERSION}" ;;
    docker-engine) printf '%s' "${ENGINE_VERSION}" ;;
    docker-cli)    printf '%s' "${CLI_VERSION}" ;;
    buildkit)      printf '%s' "${BUILDKIT_VERSION}" ;;
  esac
}
PKG_FILE() { printf '%s/%s-%s-%s-1.txz' "${OUT_DIR}" "$1" "$(VER "$1")" "${PKGARCH}"; }

# --- Helpers de interface -------------------------------------------------
d_msg()    { dialog --backtitle "${BACKTITLE}" --title "$1" --msgbox "$2" 0 0; }
d_yesno()  { dialog --backtitle "${BACKTITLE}" --title "$1" --yesno "$2" 0 0; }
d_info()   { dialog --backtitle "${BACKTITLE}" --title "$1" --infobox "$2" 0 0; sleep 1; }

# Verificação dos pacotes -> lista de arquivos presentes
check_pkgs() { # $@ nomes; imprime em SEL_FILES ou falha
  SEL_FILES=()
  local n
  for n in "$@"; do
    f="$(PKG_FILE "${n}")"
    [ -f "${f}" ] || die "Pacote ausente: ${f} (rode ./build.sh primeiro)"
    SEL_FILES+=("${f}")
  done
}

# --- Detecção de instalação existente -------------------------------------
EXISTING_PKGS="$(ls /var/log/packages 2>/dev/null | grep -E '^(docker|dockerd|docker-engine|containerd|runc|buildkit)-' || true)"

# --- 1. Seleção dos componentes -------------------------------------------
if [ "${NONINTERACTIVE}" = "1" ]; then
  SELECTED=("${ORDER[@]}")
  log "Modo --noninteractive: instalando todos os componentes"
else
  command -v dialog >/dev/null 2>&1 || {
    echo "Erro: 'dialog' não encontrado (ferramenta padrão do Slackware)."
    echo "Instale com: slackpkg install dialog   (ou use --noninteractive)"
    exit 1
  }
  d_msg "Bem-vindo" "Este instalador vai instalar o Docker Engine ${ENGINE_VERSION}\nCLI ${CLI_VERSION}, containerd ${CONTAINERD_VERSION}, runc ${RUNC_VERSION}\ne BuildKit ${BUILDKIT_VERSION} como pacotes .txz nativos do Slackware.\n\nOs pacotes são instalados com /sbin/installpkg (instalador oficial\ndo Slackware), exibindo os arquivos e o progresso.\n\nSem systemd: o daemon é gerenciado por /etc/rc.d/rc.docker.\n\nContinuar?"
  SEL="$(dialog --backtitle "${BACKTITLE}" --stdout --title "Componentes" \
    --checklist "Selecione os componentes a instalar:" 0 0 5 \
    runc          "${RUNC_VERSION} - runtime OCI"          on \
    containerd    "${CONTAINERD_VERSION} - runtime Docker" on \
    docker-engine "${ENGINE_VERSION} - daemon dockerd"     on \
    docker-cli    "${CLI_VERSION} - CLI + plugin buildx"   on \
    buildkit      "${BUILDKIT_VERSION} - buildkitd+buildctl" on )"
  [ -n "${SEL}" ] || { d_msg "Cancelado" "Nenhum componente selecionado. Instalação cancelada."; exit 1; }
  SELECTED=(${SEL})
fi

# Aplica a ordem de dependência à seleção
SEL_LIST=()
for n in "${ORDER[@]}"; do
  case " ${SELECTED[*]} " in
    *" ${n} "*) SEL_LIST+=("${n}") ;;
  esac
done
[ "${#SEL_LIST[@]}" -gt 0 ] || die "Nenhum componente selecionado."

check_pkgs "${SEL_LIST[@]}"

# --- 2. Confirmação --------------------------------------------------------
SUMMARY="Serão instalados os pacotes (via /sbin/installpkg, oficial):\n"
for n in "${SEL_LIST[@]}"; do
  SUMMARY+="  • ${n}-$(VER "${n}")-${PKGARCH}-1.txz\n"
done
SUMMARY+="\nAVISOS IMPORTANTES:\n"
SUMMARY+="  - /var/lib/docker e /var/lib/containerd NUNCA são apagados.\n"
SUMMARY+="  - As regras de firewall existentes NÃO são modificadas.\n"
SUMMARY+="  - Arquivos de configuração do host são alterados com backup.\n"
if [ -n "${EXISTING_PKGS}" ]; then
  SUMMARY+="\nInstalação Docker anterior detectada (será substituída):\n${EXISTING_PKGS}\n"
fi
SUMMARY+="\nContinuar com a instalação?"
if [ "${NONINTERACTIVE}" = "1" ]; then
  printf '%b\n' "${SUMMARY}"
else
  d_yesno "Confirmação" "${SUMMARY}" || { d_msg "Cancelado" "Instalação cancelada pelo usuário."; exit 1; }
fi

# --- 3. Verificação de checksums -------------------------------------------
if [ "${NONINTERACTIVE}" = "1" ]; then
  log "Verificando CHECKSUMS.sha256"
  ( cd "${OUT_DIR}" && sha256sum -c CHECKSUMS.sha256 ) | tee_log || die "Verificação de checksums FALHOU. Pacotes corrompidos?"
else
  d_info "Verificando" "Conferindo a integridade dos pacotes (CHECKSUMS.sha256)..."
  ( cd "${OUT_DIR}" && sha256sum -c CHECKSUMS.sha256 ) 2>&1 | tee_log || {
    d_msg "FALHA" "A verificação de checksums falhou.\nO pacote pode estar corrompido. Não será instalado."; exit 1; }
fi

# --- 4. Instalação (installpkg oficial) com progresso -----------------------
# Estatísticas: tempo por pacote, média acumulada e ETA.
TOTAL_TIME=0.0
i=0
TOTAL_N="${#SEL_FILES[@]}"

# Retorna {arquivos, tamanho-MB, lista} do pacote via tar (oficial, mesmo
# formato que o installpkg descompacta).
pkg_meta() { # $1=pacote ; define PKG_FLIST PKG_NFILES PKG_MB
  local out
  out="$(tar -tvJf "$1" 2>/dev/null)"
  # count + bytes dos arquivos regulares (sem diretórios)
  PKG_MB="$(awk 'BEGIN{s=0} $1 ~ /^-/ {s+=$3} END{printf "%0.1f", s/1048576}' <<<"${out}")"
  PKG_NFILES="$(awk 'BEGIN{n=0} $1 ~ /^-/ {n++} END{print n+0}' <<<"${out}")"
  PKG_FLIST=($(awk '$1 ~ /^-/ {gsub(/^\.\//,""); print $NF}' <<<"${out}"))
}

fmt_time() { awk -v s="$1" 'BEGIN{printf "%0.1f", s}'; }

install_one() { # $1=pacote; retorno em INSTALL_RC e INSTALL_ELAPSED
  local f="$1" start now elapsed pkglog ipid cur j
  local pct=$(( (i) * 100 / TOTAL_N ))
  pkglog="${OUT_DIR}/.install-one.log.tmp"
  : > "${pkglog}"
  # Lista real de arquivos do pacote (os mesmos que o installpkg vai instalar)
  pkg_meta "${f}"

  if [ -f "/var/log/packages/$(basename "${f}" .txz)" ]; then
    /sbin/upgradepkg --reinstall --install-new "${f}" >"${pkglog}" 2>&1 &
  else
    /sbin/installpkg "${f}" >"${pkglog}" 2>&1 &
  fi
  ipid=$!
  start="$(date +%s.%N)"
  j=0
  while kill -0 "${ipid}" 2>/dev/null; do
    now="$(date +%s.%N)"
    elapsed="$(fmt_time "$(awk -v a="${start}" -v b="${now}" 'BEGIN{print b-a}')")"
    # percentual: progresso dos pacotes concluídos + meio-passada no atual
    pct=$(( i * 100 / TOTAL_N + (100 / TOTAL_N) / 2 ))
    # próximo arquivo da lista (quando a lista acaba, mostra o andamento)
    if [ "${j}" -lt "${#PKG_FLIST[@]}" ]; then
      cur="${PKG_FLIST[${j}]}"
      j=$((j + 1))
    else
      cur="finalizando extração/scripts de instalação..."
    fi
    if [ "${NONINTERACTIVE}" != "1" ]; then
      printf 'XXX\n%d\n' "${pct}"
      printf 'Instalando: %s  (%d/%d)\n' "$(basename "${f}")" "$((i+1))" "${TOTAL_N}"
      printf '  arquivo: %s\n' "${cur}"
      printf '  arquivos: %d  ·  %s MB\n' "${PKG_NFILES}" "${PKG_MB}"
      printf '  tempo pkg: %ss  ·  média: %ss  ·  ETA: %ss\n' \
        "${elapsed}" "$(fmt_time "$(awk -v t="${TOTAL_TIME}" -v n="${i}" 'BEGIN{if(n>0) print t/n; else print 0}')")" \
        "$(fmt_time "$(awk -v t="${TOTAL_TIME}" -v n="${i}" -v left="$((TOTAL_N - i))" 'BEGIN{if(n>0) print t/n*left; else print 0}')")"
      printf 'XXX\n'
    fi
    sleep 0.06
  done
  INSTALL_RC=0
  wait "${ipid}" || INSTALL_RC=$?
  now="$(date +%s.%N)"
  INSTALL_ELAPSED="$(fmt_time "$(awk -v a="${start}" -v b="${now}" 'BEGIN{print b-a}')")"
  cat "${pkglog}" | tee_log
  rm -f "${pkglog}"
}

if [ "${NONINTERACTIVE}" = "1" ]; then
  for f in "${SEL_FILES[@]}"; do
    i=$((i + 1))
    log "Instalando $(basename "${f}") (${i}/${TOTAL_N}) via /sbin/installpkg (oficial)"
    install_one "${f}"
    log "  concluído em ${INSTALL_ELAPSED}s"
    TOTAL_TIME="$(awk -v t="${TOTAL_TIME}" -v e="${INSTALL_ELAPSED}" 'BEGIN{print t+e}')"
    [ "${INSTALL_RC}" = "0" ] || die "Falha na instalação de $(basename "${f}") (veja ${LOG})"
  done
else
  FIFO="$(mktemp -u /tmp/dialog-install.XXXXXX)"
  mkfifo "${FIFO}"
  dialog --backtitle "${BACKTITLE}" --title "Instalando pacotes .txz (installpkg oficial)" \
    --gauge "Iniciando..." 10 72 0 < "${FIFO}" &
  GAUGE_PID=$!
  exec 9>"${FIFO}"
  for f in "${SEL_FILES[@]}"; do
    install_one "${f}"
    TOTAL_TIME="$(awk -v t="${TOTAL_TIME}" -v e="${INSTALL_ELAPSED}" 'BEGIN{print t+e}')"
    if [ "${INSTALL_RC}" != "0" ]; then
      printf 'XXX\n100\nFALHA em %s\nXXX\n' "$(basename "${f}")" >&9
      exec 9>&-
      rm -f "${FIFO}"
      wait "${GAUGE_PID}" 2>/dev/null || true
      d_msg "FALHA" "Falha na instalação de $(basename "${f}").\nDetalhes: ${LOG}"
      exit 1
    fi
    i=$((i + 1))
  done
  printf 'XXX\n100\nConcluído: %d pacotes em %ss (média %ss)\nXXX\n' \
    "${TOTAL_N}" "$(fmt_time "${TOTAL_TIME}")" \
    "$(fmt_time "$(awk -v t="${TOTAL_TIME}" -v n="${TOTAL_N}" 'BEGIN{print t/n}')")" >&9
  sleep 1
  exec 9>&-
  wait "${GAUGE_PID}" 2>/dev/null || true
  rm -f "${FIFO}"
fi

log "Tempo total de instalação: ${TOTAL_TIME}s (média ${TOTAL_N} pacotes)"

# --- 5. Configuração do host -----------------------------------------------
if [ "${NONINTERACTIVE}" = "1" ]; then
  log "Configurando o host (módulos, sysctl, daemon.json, rc.docker, grupo docker)"
  "${SCRIPT_DIR}/configure-host.sh" 2>&1 | tee_log || die "configure-host.sh falhou (veja ${LOG})"
else
  d_info "Host" "Configurando o host (módulos, sysctl, /etc/docker/daemon.json,\n/etc/rc.d/rc.docker, grupo docker)..."
  "${SCRIPT_DIR}/configure-host.sh" 2>&1 | tee_log | \
    sed -r 's/\x1B\[[0-9;]*[mK]//g' |
    dialog --backtitle "${BACKTITLE}" --title "Configuração do host" \
      --programbox "Executando configure-host.sh..." 22 76 \
    || true
  RC="${PIPESTATUS[0]}"
  [ "${RC}" = "0" ] || { d_msg "FALHA" "configure-host.sh falhou.\nDetalhes: ${LOG}"; exit 1; }
fi

# --- 6. Iniciar o daemon ----------------------------------------------------
if [ "${NONINTERACTIVE}" = "1" ]; then
  log "Iniciando Docker (rc.docker start)"
  /etc/rc.d/rc.docker start 2>&1 | tee_log || warn "Daemon não iniciou; veja ${LOG}"
  /etc/rc.d/rc.docker status 2>&1 | tee_log || true
else
  if d_yesno "Daemon" "Iniciar o Docker agora?"; then
    /etc/rc.d/rc.docker start 2>&1 | tee_log || true
    STAT="$(/etc/rc.d/rc.docker status 2>&1 || true)"
    d_msg "Daemon" "${STAT}"
  fi
fi

# --- 7. Testes de pós-instalação --------------------------------------------
if [ "${RUN_TESTS}" = "1" ]; then
  if [ "${NONINTERACTIVE}" = "1" ]; then
    log "Executando testes de pós-instalação"
    "${SCRIPT_DIR}/../tests/test-docker.sh" 2>&1 | tee_log || warn "Testes falharam (veja ${LOG})"
  else
    if d_yesno "Testes" "Rodar os testes de pós-instalação agora?\n(docker version/info, hello-world, buildx, docker build)"; then
      "${SCRIPT_DIR}/../tests/test-docker.sh" 2>&1 | tee_log | \
        sed -r 's/\x1B\[[0-9;]*[mK]//g' |
        dialog --backtitle "${BACKTITLE}" --title "Testes de pós-instalação" \
          --programbox "Executando testes..." 22 76 \
        || true
    fi
  fi
fi

# --- 8. Resumo + aviso de segurança ----------------------------------------
FINAL="Instalação concluída com sucesso em ${TOTAL_TIME}s (média: $(fmt_time "$(awk -v t="${TOTAL_TIME}" -v n="${TOTAL_N}" 'BEGIN{print t/n}')")s por pacote)!\n\n"
FINAL+="Iniciar/parar/status:  /etc/rc.d/rc.docker {start|stop|restart|status}\n"
FINAL+="Log do daemon:          /var/log/docker.log\n"
FINAL+="Log deste instalador:   ${LOG}\n"
FINAL+="\nSEGURANÇA: o grupo 'docker' NÃO recebeu usuários ainda.\n"
FINAL+="Para usar o docker como usuário comum:\n"
FINAL+="  sudo usermod -aG docker <usuario>\n"
FINAL+="(pertencer ao grupo docker equivale a root no host: adicione\n"
FINAL+="somente usuários de confiança.)"
if [ "${NONINTERACTIVE}" = "1" ]; then
  printf '%b\n' "${FINAL}"
  ok "Instalação concluída. Log: ${LOG}"
else
  d_msg "Concluído" "${FINAL}"
fi

exit 0