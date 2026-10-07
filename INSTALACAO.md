# Instalação dos pacotes Docker para Slackware 15.0

Este documento explica como instalar os pacotes `.txz` nativos gerados pelo
[sistema de build](README.md) em um **Slackware 15.0 x86_64** (sem systemd,
init tradicional via `/etc/rc.d/rc.docker`).

Pacotes incluídos (ordem de dependência):

| Ordem | Pacote | Versão | Conteúdo |
|---|---|---|---|
| 1 | `runc` | 1.5.2 | runtime OCI de baixo nível |
| 2 | `containerd` | 2.3.6 | runtime de containers do Docker |
| 3 | `docker-engine` | 29.8.2 | `dockerd`, `docker-proxy`, `docker-init` |
| 4 | `docker-cli` | 29.8.2 | CLI `docker` + plugin `docker-buildx` |
| 5 | `buildkit` | 0.33.1 | `buildkitd` + `buildctl` |

---

## 1. Pré-requisitos

- Slackware 15.0 (x86_64), kernel 5.15.x.
- Acesso **root** (`su -` ou `sudo`).
- Kernel com namespaces, cgroups (v1 — mantido por projeto), `overlay`,
  `bridge`, netfilter/NAT, seccomp — os módulos são carregados pelo
  `configure-host.sh`/`rc.docker`.
- A instalação **não** apaga `/var/lib/docker` nem `/var/lib/containerd`.
- A instalação **não** altera as regras de firewall existentes (o dockerd
  gerencia as próprias chains com `"iptables": true`).

---

## 2. Obter os pacotes (uma das opções)

```console
# Opção A: clonar o repositório (pacotes em packages/)
$ git clone git@github.com:j1m1l0k0/slackware_docker.git
$ cd slackware_docker

# Opção B: apenas os pacotes
$ ls packages/
buildkit-0.33.1-x86_64-1.txz
containerd-2.3.6-x86_64-1.txz
docker-engine-29.8.2-x86_64-1.txz
docker-cli-29.8.2-x86_64-1.txz
runc-1.5.2-x86_64-1.txz
```

**Verificar a integridade dos pacotes** (opcional, recomendado):

```console
$ cd packages
$ sha256sum -c CHECKSUMS.sha256
runc-1.5.2-x86_64-1.txz: OK
containerd-2.3.6-x86_64-1.txz: OK
docker-engine-29.8.2-x86_64-1.txz: OK
docker-cli-29.8.2-x86_64-1.txz: OK
buildkit-0.33.1-x86_64-1.txz: OK
```

---

## 3. Instalação

### 3.0 Instalador gráfico (`dialog` — ferramenta padrão do Slackware)

Instalador interativo baseado no `dialog`, usando o **`/sbin/installpkg`**
(motor oficial do Slackware, o mesmo do `pkgtool`/`setup`) com:

- seleção de componentes (checklist) e confirmações;
- **barra de progresso** por pacote;
- **arquivos sendo instalados em tempo real** (lista extraída do próprio
  `.txz` que o `installpkg` está descompactando, com contagem e tamanho);
- **tempo decorrido por pacote, tempo médio e ETA** restante;

```console
$ sudo scripts/install-dialog.sh
```

Para automação (sem interface):

```console
$ sudo scripts/install-dialog.sh --noninteractive [--no-tests]
```

O log fica em `packages/install-dialog.log`.

### 3.1 Automática (recomendada)

Com os scripts do repositório (executa configure-host + instalação +
início do daemon + testes):

```console
$ sudo ./build.sh install

# ou:
$ sudo scripts/install.sh
```

### 3.2 Manual (somente `installpkg`)

Instale na **ordem de dependência**:

```console
$ cd packages
$ sudo /sbin/installpkg runc-1.5.2-x86_64-1.txz
$ sudo /sbin/installpkg containerd-2.3.6-x86_64-1.txz
$ sudo /sbin/installpkg docker-engine-29.8.2-x86_64-1.txz
$ sudo /sbin/installpkg docker-cli-29.8.2-x86_64-1.txz
$ sudo /sbin/installpkg buildkit-0.33.1-x86_64-1.txz
```

Para substituir uma instalação anterior:

```console
$ sudo /sbin/upgradepkg --reinstall --install-new docker-engine-29.8.2-x86_64-1.txz
```

### 3.3 Configuração do host (`configure-host.sh`)

Necessária na primeira instalação. Faz backup automático de qualquer arquivo
que for modificar (em `packages/backups/`):

- carrega os módulos do kernel (`overlay`, `br_netfilter`, `bridge`,
  `ip_tables`, `iptable_nat`, ... — via `modprobe -n` antes de carregar);
- cria `/etc/sysctl.d/99-docker.conf` (`ip_forward`, `bridge-nf-call-...`);
- cria `/etc/docker/daemon.json` **validado** (`overlay2`, `iptables: true`,
  BuildKit `features.buildkit: true`, log `json-file` com rotação) — se já
  existir, **não é sobrescrito** (só backup);
- instala `/etc/rc.d/rc.docker` e adiciona o bloco de boot no `rc.local`;
- cria o grupo `docker` (gid 263).

```console
$ sudo scripts/configure-host.sh
```

---

## 4. Iniciar o daemon

```console
$ sudo /etc/rc.d/rc.docker start      # inicia dockerd
$ sudo /etc/rc.d/rc.docker status     # PID + socket
$ sudo /etc/rc.d/rc.docker restart
$ sudo /etc/rc.d/rc.docker stop
```

- Log: `/var/log/docker.log`
- PID file: `/run/docker.pid`
- Socket da API: `/var/run/docker.sock`

**Boot automático:** o bloco adicionado em `/etc/rc.d/rc.local` inicia o
Docker na inicialização se `/etc/rc.d/rc.docker` tiver permissão de execução.
Para desabilitar: `sudo chmod -x /etc/rc.d/rc.docker` (ou remova o bloco).

---

## 5. Verificação (testes de pós-instalação)

```console
$ sudo tests/test-docker.sh
```

Testes executados: `docker version`, `docker info` (CgroupVersion, Driver,
RootDir), `docker run --rm hello-world`, `docker buildx version` e um
`docker build` mínimo (FROM alpine; RUN echo) seguido de `docker run`.

Exemplo de execução manual:

```console
$ sudo docker version
$ sudo docker info --format '{{.ServerVersion}} {{.Driver}} {{json .CgroupVersion}}'
$ sudo docker run --rm hello-world
$ sudo docker buildx version
```

> Docker 29 no cgroup **v1** é deprecado mas oficialmente suportado até
> maio/2029 (docs.docker.com/engine/deprecated). Este projeto mantém v1 por
> design; não alteramos o modos de inicialização do kernel.

---

## 6. Grupo `docker` (segurança)

O usuário **não** é adicionado ao grupo `docker` automaticamente:

```console
$ sudo usermod -aG docker <usuario>     # sair e entrar de novo para aplicar
```

**AVISO:** pertencer ao grupo `docker` equivale, na prática, a ter root no
host (o socket do daemon permite acesso total). Adicione apenas usuários em
quem confia.

---

## 7. Desinstalação / rollback

```console
$ sudo /etc/rc.d/rc.docker stop
$ sudo removepkg docker-cli docker-engine containerd runc buildkit
```

- `/var/lib/docker` e `/var/lib/containerd` **nunca são apagados** pelos
  scripts (remova manualmente se desejar).
- Backups de configuração alterada ficam em `packages/backups/`
  (ex.: `rc.local`, `daemon.json`, `rc.docker`) e podem ser restaurados
  manualmente.

---

## 8. Problemas?

```console
$ sudo scripts/diagnostics.sh    # gera packages/docker-diagnostics.txt
$ sudo /etc/rc.d/rc.docker status
$ tail -n 50 /var/log/docker.log
```

O relatório de diagnóstico inclui: kernel, Slackware, log do daemon,
processos, cgroups v1/v2, mounts, iptables (sem alterá-las), sysctl,
módulos carregados, `docker info/version` e o manifest do build
(`packages/docker-diagnostics.txt`).