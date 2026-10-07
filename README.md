# docker-slackware
# Author: j1m1l0k0 - 2026

Build system + instalador **específico para Slackware 15.0** que compila o
Docker Engine (Moby), Docker CLI, containerd, runc e BuildKit **a partir dos
fontes oficiais** e gera pacotes nativos `.txz` Slackware. Sem systemd:
inicialização pelo modelo tradicional de init (`/etc/rc.d/rc.docker`).

---

## 1. Requisitos

| Recurso | Mínimo recomendado |
|---|---|
| Sistema | Slackware 15.0 (`x86_64` validado) |
| Kernel | qualquer kernel com os recursos abaixo (validado: 5.15.19) |
| Memória | 2 GB (8+ GB recomendado para o build de 6 componentes) |
| Disco | 20 GB livres (fontes+build≈6–10 GB) |
| Rede | acesso a `github.com` e `go.dev` (para download dos fontes/toolchain) |
| Root | para instalação, módulos do kernel e start do daemon (`sudo`) |

Dependências de build presentes no Slackware 15.0 (validadas pelo
`check-system.sh`): `git`, `curl`, `wget`, `tar`, `xz`, `gzip`, `make`,
`gcc`, `g++`, `pkg-config`, `python3`, `sha256sum`, `installpkg`, `makepkg`,
`sysctl`, `modprobe`, `groupadd`, `iptables`. O `jq` **não** é necessário
(usa-se `python3` para JSON).

## 2. Compatibilidade com Slackware 15.0

- Init: `/etc/rc.d/rc.docker start|stop|restart|status` (PID file, log em
  `/var/log/docker.log`, tratamento de erro).
- Sysctl: o Slackware 15.0 executa `/sbin/sysctl -e --system` no `/etc/rc.d/rc.S`
  (verificado nesta instalação), portanto `/etc/sysctl.d/99-docker.conf` é o
  mecanismo correto e persistente.
- Pacotes: `makepkg`/`installpkg`/`removepkg`/`upgradepkg`; `slack-desc` e
  `doinst.sh` incluídos.
- Boot: bloco idempotente adicionado ao `/etc/rc.d/rc.local` (apenas se o
  `rc.docker` tiver permissão de execução).
- Nenhum unit do systemd é criado nem executado.

### Matriz de versões (verificada em 2026-10-07)

Verificada contra as **release notes oficiais** do Docker Engine 29.8.2
(`containerd v2.3.6`, `runc v1.5.2`, `BuildKit v0.33.1`, `Go 1.26.8`), os
`go.mod` oficiais e as tags/commits do GitHub. Cada componente é pinado por
**tag + commit SHA** em `config/versions.conf`, e o download **falha** se o
commit do checkout não bater com o esperado.

| Componente | Versão | Commit verificado |
|---|---|---|
| Docker Engine (Moby) | 29.8.2 | `8af9fe3a…` |
| Docker CLI | 29.8.2 | `7fc2dff9…` |
| containerd | 2.3.6 | `ee273536…` |
| runc | 1.5.2 | `29dd3dc2…` |
| BuildKit | 0.33.1 | `8c91502c…` |
| Buildx (plugin do CLI) | 0.37.2 | `2d379c0c…` |
| docker-init (tini) | 0.19.0 | `de40ad00…` |
| Go (toolchain) | 1.26.8 | sha256 `d0f743b3…` (go.dev) |

> **Por que não `latest` solto?** Cada componente tem cronograma de release
> próprio; a combinação "última versão de cada" não é a matriz suportada pela
> Docker. Os pares acima são exatamente os empacotados nas `.deb`/`.rpm`
> oficiais do Docker CE para o Engine 29.8.2.

## 3. Kernel recomendado

O kernel **5.15.x do Slackware 15.0** (huge e generic) cobre todos os
recursos. Recursos verificados pelo `check-system.sh` (via `/proc/config.gz`):

- namespaces (`CONFIG_NAMESPACES`), cgroups (`CONFIG_CGROUPS`, `CONFIG_MEMCG`)
- overlayfs (`CONFIG_OVERLAY_FS`) — storage `overlay2`
- bridge (`CONFIG_BRIDGE`, `CONFIG_BRIDGE_NETFILTER`) — rede docker0
- netfilter/iptables (`CONFIG_NETFILTER`, `CONFIG_IP_NF_IPTABLES`,
  `CONFIG_IP_NF_NAT`, `CONFIG_NF_NAT`, `CONFIG_NF_CONNTRACK`,
  `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE`)
- IPv6 nat (`CONFIG_IP6_NF_IPTABLES`)
- seccomp (`CONFIG_SECCOMP`, `CONFIG_SECCOMP_FILTER`) — para perfis de
  segurança do Docker
- veth (`CONFIG_VETH`) — para as bridges de contêiner
- (opcional) user namespaces (`CONFIG_USER_NS`)

Se algum estiver ausente o script **para** e mostra exatamente o que falta.

## 4. cgroup v1 vs v2

O Slackware 15.0 monta **cgroup v1** por padrão (`/etc/rc.d/rc.S`). O Docker
Engine 29 suporta v1 (deprecated desde v29, suporte garantido **até
2029** — docs oficiais), então **não fazemos alterações no boot** por padrão.

- Detecção de v2: `test -f /sys/fs/cgroup/cgroup.controllers`.
- Se quiser migrar para **cgroup v2** (recomendado pela Docker):
  1. Adicione `cgroup_no_v1=all` (e, se usar initrd, `systemd.unified_cgroup_hierarchy=1`
     não se aplica sem systemd — no Slackware basta `cgroup_no_v1=all`) aos
     parâmetros do kernel no LILO (`/etc/lilo.conf`, rode `lilo` depois) ou
     no configurador do GRUB.
  2. Verifique `mount | grep cgroup` mostrando apenas `cgroup2`.
  3. Reverta simplesmente removendo o parâmetro.

O projeto não altera `rc.S` nem o boot automaticamente: apenas informa.

## 5. Dependências (Go e ferramentas)

O Slackware 15.0 não traz Go; o `go` presente em alguns ambientes
(`gccgo 1.16`) **não atende** ao requisito `go 1.26.8` dos componentes.
O projeto baixa o **toolchain oficial** `go1.26.8.linux-amd64.tar.gz` do
`go.dev/dl`, verifica o **sha256 do JSON oficial** e o instala **isolado** em
`<projeto>/toolchain/go` — nada no sistema é alterado. O download é passo
separado (`build-go-toolchain.sh`) para você inspecionar antes, conforme a
regra “não baixar Go arbitrário”.

## 6. Como compilar

```console
$ cd docker-slackware
$ ./build.sh                 # verifica sistema → baixa Go → baixa fontes → compila → gera .txz
# ou, por etapas:
$ ./build.sh check           # só a verificação do sistema
$ ./build.sh go              # só o toolchain Go
$ ./build.sh download        # só os fontes (com verificação de commits)
$ ./build.sh runc            # um componente isolado
$ ./build.sh --run-tests     # roda teste Go (full) em cada componente
```

Resultado em `packages/`:

```console
docker-engine-29.8.2-x86_64-1.txz
docker-cli-29.8.2-x86_64-1.txz
containerd-2.3.6-x86_64-1.txz
runc-1.5.2-x86_64-1.txz
buildkit-0.33.1-x86_64-1.txz
CHECKSUMS.sha256
docker-build-manifest.txt     # versões, commits, Go, kernel, arquitetura, datas
backups/                      # backups de configuração (rollback)
```

Regras de build seguidas: nenhuma instalação durante o build (somente
staging), nenhum `curl | sh`, todo download validado, fontes pinados por
commit, builds sequenciais (memória), e os comandos `go build` replicam os
`hack/make/*.sh` e `Dockerfile` oficiais de cada projeto.

**Desvios documentados** (por indisponibilidade de libs no Slackware):

| Componente | Oficial | Aqui | Motivo |
|---|---|---|---|
| runc | estático + `libpathrs` | **dinâmico** (`libseccomp.so`) + fallback `pathrslite` | sem `libseccomp.a` e sem lib C `libpathrs` no Slackware (o runc usa o fallback oficial `!libpathrs`) |
| buildkitd | estático + seccomp | **dinâmico** + seccomp | idem |
| docker engine/proxy | dinâmico | dinâmico | igual ao oficial |
| containerd/ctr/shim | estático | estático | `libc.a` presente ✓ |
| docker cli/buildctl/buildx | estático | estático | puro Go |

## 7. Como instalar

```console
$ sudo ./build.sh install
# ou manualmente:
$ sudo scripts/install.sh
```

Ordem de instalação (dependências): `runc` → `containerd` → `docker-engine`
→ `docker-cli` → `buildkit`. Se já existir uma instalação Docker, o script
**pergunta** antes de substituir e **nunca apaga** `/var/lib/docker` nem
`/var/lib/containerd`.

O `install.sh` também executa o `configure-host.sh`, que:

- carrega os módulos do kernel (backup automático em `packages/backups/`),
- cria `/etc/sysctl.d/99-docker.conf` (sem sobrescrever arquivos do usuário),
- cria `/etc/docker/daemon.json` **validado** (não toca em um existente),
- instala `/etc/rc.d/rc.docker` e o hook do `rc.local`,
- cria o grupo `docker` (gid 263).

## 8. Como iniciar o Docker

```console
$ sudo /etc/rc.d/rc.docker start
$ sudo /etc/rc.d/rc.docker status
$ docker info                # ex.: Cgroup Version, Storage Driver overlay2
```

## 9. Como habilitar no boot

O instalador adiciona um bloco `#<<docker-slackware>>` ao
`/etc/rc.d/rc.local`. O Docker só inicia no boot se `/etc/rc.d/rc.docker`
estiver **executável** (o padrão do Slackware: `chmod -x` desabilita scripts
de init). Para desabilitar o boot automático:

```console
$ sudo chmod -x /etc/rc.d/rc.docker
```

## 10. Como adicionar usuário ao grupo docker

```console
$ sudo usermod -aG docker <usuario>
```

O usuário precisa refazer login (ou `newgrp docker`) para que o grupo tenha
efeito.

## 11. Como desinstalar

```console
$ sudo scripts/uninstall.sh            # remove pacotes + rc.docker + rc.local + sysctl
$ sudo scripts/uninstall.sh --purge-data  # TAMBÉM apaga /var/lib/docker e /var/lib/containerd (2 confirmações)
```

## 12. Rollback

Toda modificação de arquivo do host gera um backup em
`packages/backups/` (por exemplo `…-etc_docker_daemon.json`). Para reverter:

1. Pare o daemon: `sudo /etc/rc.d/rc.docker stop`.
2. `sudo removepkg docker-engine docker-cli containerd runc buildkit`
   (ou `scripts/uninstall.sh`).
3. Restaure os arquivos dos backups:
   `sudo cp -a packages/backups/<data>-etc_rc.d_rc.local /etc/rc.d/rc.local`
   (idem para `etc_rc.d_rc.docker`, `etc_sysctl.d_99-docker.conf`,
   `etc_docker/…`).
4. Se tiver migrado para cgroup v2, remova o parâmetro de boot e rode `lilo`.

## 13. Como atualizar

1. Confira a matriz atual na documentação oficial do Docker Engine
   (release notes) e atualize `config/versions.conf` (versões, tags e SHAs).
2. `./build.sh` regenera os pacotes.
3. `sudo scripts/install.sh --yes` instala por cima (via `upgradepkg`),
   preservando `/var/lib/docker`.

Não há “auto-update”: versões são pinadas e revisadas por você. Os shas de
commit evitam que a mudança de uma tag seja silenciosa.

## 14. Como diagnosticar

`journalctl` **não** existe no Slackware. O diagnóstico usa:

```console
$ sudo scripts/diagnostics.sh     # gera packages/docker-diagnostics.txt
```

O relatório contém: `/var/log/docker.log` (tail), `ps aux | grep dockerd`,
`/proc/cgroups`, `mount | grep cgroup`, `mount | grep overlay`,
`iptables -L`, `iptables -t nat -L`, sysctl de rede, módulos carregados,
configuração do kernel, `docker info` e o manifest do build.

Problemas comuns:

- **Daemon não inicia**: veja `/var/log/docker.log`; conferir se os módulos
  carregaram (`lsmod | grep -E 'overlay|br_netfilter'`) e se
  `net.bridge.bridge-nf-call-iptables` está ativo.
- **`iptables` falha**: o Slackware usa `iptables 1.8.7 (legacy)`; o daemon
  cria as próprias chains `DOCKER`/`DOCKER-USER` — nunca rode `iptables -F`
  estando o daemon ligado sem entender o que está fazendo.
- **overlay2 indisponível**: `docker info` mostrará o driver escolhido; se o
  filesystem não suportar `d_type`, o instalador cai automaticamente para
  `vfs` com aviso.

## 15. Riscos de segurança do grupo docker

Pertenecer ao grupo `docker` equivale, **na prática, a acesso root no host**:
qualquer membro pode montar volumes, executar contêineres com acesso total ao
sistema de arquivos, escrever em `/etc/crontab`, ler `/etc/shadow`, criar
devices, etc. **Adicione ao grupo apenas usuários em quem confia como root.**
Esta é a mesma política adotada pela Docker oficial.

### Segurança do build/instalação

- `set -e` e `set -o pipefail` em todos os scripts; validação de argumentos.
- Downloads com verificação: commits Git pinados para os fontes; sha256
  oficial (via JSON do `go.dev`) para o toolchain Go.
- Nenhum `curl | sh`; nenhuma execução remota.
- Nenhum `iptables -F/-X` nem remoção de regras; o daemon gerencia as chains.
- Nenhum flush de `/var/lib/docker`/`/var/lib/containerd` sem confirmação.
- Backups automáticos de `/etc/docker`, `/etc/rc.d/rc.docker`,
  `/etc/sysctl.d/99-docker.conf`, `/etc/rc.d/rc.local` e `/etc/modprobe.d/*`
  quando existirem e forem modificados.

## Estrutura

```console
docker-slackware/
├── README.md
├── build.sh                     # orquestrador (check → go → download → builds)
├── config/
│   ├── versions.conf            # matriz de versões pinada (tags + SHAs + sha256 Go)
│   ├── daemon.json              # template validado do daemon
│   └── rc.docker                # script de init instalado em /etc/rc.d/
├── scripts/
│   ├── lib.sh                   # funções comuns (root sudo, backup, makepkg, manifest)
│   ├── check-system.sh          # Slackware 15.0/kernel/cgroup/deps
│   ├── download-sources.sh      # fontes oficiais + verificação de commit
│   ├── build-go-toolchain.sh    # Go 1.26.8 oficial (sha256 verificado), isolado
│   ├── build-runc.sh            # runc
│   ├── build-containerd.sh      # containerd (estático)
│   ├── build-moby.sh            # dockerd + docker-proxy + docker-init
│   ├── build-cli.sh             # docker CLI (+ completions)
│   ├── build-buildkit.sh        # buildkitd + buildctl
│   ├── build-buildx.sh          # plugin docker-buildx (vai no pacote docker-cli)
│   ├── configure-host.sh        # módulos, sysctl, daemon.json, rc.docker, grupo
│   ├── install.sh               # installpkg + configuração + start
│   ├── uninstall.sh             # removepkg + limpeza reversível
│   └── diagnostics.sh           # docker-diagnostics.txt (sem journalctl)
├── slack-desc/                  # descrições de pacote (slack-desc)
├── tests/
│   └── test-docker.sh           # docker info, hello-world, buildx, docker build
└── packages/                    # .txz + CHECKSUMS.sha256 + manifest + backups
```