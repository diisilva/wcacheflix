# wcacheflix — Tutorial completo

Servidor de mídia **Jellyfin** em Docker sobre **Ubuntu**, pensado para rodar
num notebook, mini-PC ou desktop reaproveitado, com armazenamento em um disco
dedicado e acesso remoto seguro via Tailscale.

Este tutorial é **genérico e reprodutível**: funciona em outro Ubuntu, em outra
casa e em outra rede. Onde aparecer `SEU_USUARIO`, `SEU_DISCO` ou um IP de
exemplo, troque pelos valores da sua máquina.

> Todos os comandos `sudo` são para você executar no seu terminal. Os scripts de
> apoio ficam em [`scripts/`](scripts/) e são idempotentes (podem ser rodados de
> novo sem estragar nada).

---

## Índice

1. [Visão geral e arquitetura](#1-visão-geral-e-arquitetura)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Preparação do host (opcional, para notebooks)](#3-preparação-do-host-opcional-para-notebooks)
4. [Instalar o Docker](#4-instalar-o-docker)
5. [Preparar o disco de mídia](#5-preparar-o-disco-de-mídia)
6. [Estrutura de pastas](#6-estrutura-de-pastas)
7. [Configuração: `.env` e `compose.yaml`](#7-configuração-env-e-composeyaml)
8. [Serviço systemd e primeiro start](#8-serviço-systemd-e-primeiro-start)
9. [Primeiro acesso ao Jellyfin](#9-primeiro-acesso-ao-jellyfin)
10. [Bibliotecas de mídia](#10-bibliotecas-de-mídia)
11. [Aceleração de hardware (Intel / AMD VA-API)](#11-aceleração-de-hardware-intel--amd-va-api)
12. [Acesso remoto com Tailscale](#12-acesso-remoto-com-tailscale)
13. [Firewall](#13-firewall)
14. [Boot automático e teste de reboot](#14-boot-automático-e-teste-de-reboot)
15. [Adicionar filmes e séries](#15-adicionar-filmes-e-séries)
16. [Operação e manutenção](#16-operação-e-manutenção)
17. [Diagnóstico rápido](#17-diagnóstico-rápido)
18. [Estrutura do repositório](#18-estrutura-do-repositório)
19. [Referências](#19-referências)

---

## 1. Visão geral e arquitetura

```text
SSD do sistema (uso geral, preservado)
├── Ubuntu + seus aplicativos
├── Docker Engine e imagens
└── /opt/wcacheflix/{compose.yaml,.env}   <- só configuração

Disco dedicado à mídia (1 partição EXT4)
└── /srv/wcacheflix
    ├── config      configuração do Jellyfin
    ├── cache       cache e transcodes
    └── media
        ├── Filmes
        └── Series

Container "wcacheflix" (imagem jellyfin/jellyfin)
├── /config  <- /srv/wcacheflix/config
├── /cache   <- /srv/wcacheflix/cache
├── /media   <- /srv/wcacheflix/media   (somente leitura)
└── GPU via /dev/dri/renderD128 (opcional)

Acesso
├── LAN:    http://<host>.local:8096  ou  http://<IP-LAN>:8096
└── Remoto: http://<IP-tailscale>:8096   (sem abrir porta no roteador)
```

**Decisões principais**

| Decisão | Motivo |
|---|---|
| Mídia em disco separado, montado por **UUID** com `nofail` | O IP/dispositivo pode mudar; o boot não trava se o disco faltar. |
| `/media` entra no container **somente leitura** | O Jellyfin nunca modifica seus arquivos. |
| `network_mode: host` | Simplicidade; a porta 8096 é publicada direto no host. |
| Subida via **systemd** com `RequiresMountsFor=/srv/wcacheflix` | Se o disco não montar, o Jellyfin não sobe — evita gravar no SSD por engano. |
| Acesso remoto por **Tailscale**, não port forwarding | Não expõe o Jellyfin à Internet pública. |
| Nome fixo do projeto: `wcacheflix` | Projeto Compose, container e unidade systemd usam o mesmo nome. |

---

## 2. Pré-requisitos

- Ubuntu 22.04 ou mais novo (Debian/Mint/Pop!\_OS costumam funcionar).
- Acesso `sudo`.
- Um **disco inteiro dedicado** à mídia (será apagado). Não precisa ser grande;
  pode ser HDD.
- Rede local com o servidor e os clientes (TV, celular, PC).
- Conta gratuita no [Tailscale](https://tailscale.com) para acesso remoto (opcional).
- GPU Intel/AMD com `/dev/dri/renderD128` para transcodificação acelerada (opcional).

Clone o repositório na máquina servidor:

```bash
git clone https://github.com/diisilva/wcacheflix.git
cd wcacheflix
chmod +x scripts/*.sh scripts/*.py
```

---

## 3. Preparação do host (opcional, para notebooks)

Se o servidor for um **notebook**, impeça que ele suspenda ao fechar a tampa:

```bash
sudo ./scripts/01-host-tuning.sh
```

Isso grava `/etc/systemd/logind.conf.d/homeserver.conf` e mascara
`sleep.target suspend.target hibernate.target hybrid-sleep.target`.

Confira depois de reiniciar:

```bash
systemctl status sleep.target   # deve aparecer "masked"
```

Ajuste também a **BIOS/UEFI**: se existir a opção *"AC Power Recovery" / "Restore
on AC/Power Loss"*, deixe em **Ligar**, para o servidor voltar sozinho após queda
de energia.

---

## 4. Instalar o Docker

```bash
sudo ./scripts/02-install-docker.sh
```

O script usa o **repositório oficial da Docker**, habilita o serviço e adiciona
seu usuário ao grupo `docker`. **Saia e entre da sessão** (ou reinicie) para usar
`docker` sem `sudo`.

Valide:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

---

## 5. Preparar o disco de mídia

> ⚠️ **Operação destrutiva.** O disco escolhido é apagado por completo.

Identifique o disco com um caminho **estável**:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS
ls -l /dev/disk/by-id/    # use um id 'ata-...' ou 'nvme-...' (sem o sufixo -partN)
```

Primeiro em **dry-run** (não altera nada):

```bash
sudo ./scripts/03-prepare-storage.py --disk /dev/disk/by-id/ata-SEU_DISCO
```

Confira o plano e então **aplique**:

```bash
sudo ./scripts/03-prepare-storage.py --disk /dev/disk/by-id/ata-SEU_DISCO --apply
```

O script:

1. recusa discos que contenham `/`, `/boot`, `/boot/efi`, swap, LVM/RAID/cripto
   ou partições montadas;
2. cria **uma** partição EXT4 (`-m 0`, sem reserva de root) ocupando o disco;
3. faz backup de `/etc/fstab` em `/etc/fstab.backup` e adiciona a linha:
   `UUID=<...> /srv/wcacheflix ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2`
4. monta em `/srv/wcacheflix` e valida.

<details>
<summary>Alternativa: separar uma partição extra para dados pessoais</summary>

O script cria uma única partição. Se quiser dividir o disco (ex.: 300 GB para
mídia + resto para uso pessoal fora do container), particione manualmente com
`parted`, formate as duas como EXT4, e adicione **duas** linhas ao `/etc/fstab`
(uma para `/srv/wcacheflix`, outra para `/srv/dados`), ambas com `nofail`. Só
`/srv/wcacheflix` é usado pelo container.
</details>

---

## 6. Estrutura de pastas

```bash
sudo ./scripts/04-create-layout.sh
```

Cria `/opt/wcacheflix` e `/srv/wcacheflix/{config,cache,media/Filmes,media/Series}`
e passa a posse ao seu usuário.

---

## 7. Configuração: `.env` e `compose.yaml`

```bash
./scripts/05-generate-env.sh      # sem sudo
```

Gera `/opt/wcacheflix/.env` com:

```ini
PUID=1000          # id -u
PGID=1000          # id -g
RENDER_GID=110     # stat -c '%g' /dev/dri/renderD128
```

e copia o `compose.yaml` do repositório para `/opt/wcacheflix/`, validando com
`docker compose config`.

**Sem GPU compatível:** o script deixa `RENDER_GID` vazio e avisa. Nesse caso,
edite `/opt/wcacheflix/compose.yaml` e remova o bloco:

```yaml
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
```

---

## 8. Serviço systemd e primeiro start

```bash
sudo ./scripts/06-install-service.sh
( cd /opt/wcacheflix && docker compose pull )
sudo systemctl start wcacheflix.service
```

Verifique:

```bash
systemctl status wcacheflix.service --no-pager
docker compose -f /opt/wcacheflix/compose.yaml ps
./scripts/99-healthcheck.sh
```

O container deve aparecer como **Up (healthy)** e a porta **8096** escutando.

---

## 9. Primeiro acesso ao Jellyfin

No navegador, na mesma rede:

```text
http://<IP-DO-SERVIDOR>:8096
```

Descubra o IP com `hostname -I`. Muitos Ubuntus também respondem por
`http://<hostname>.local:8096` (mDNS/Avahi).

No assistente inicial:

1. idioma **Português (Brasil)**;
2. crie o **usuário administrador** com senha forte;
3. pode adicionar as bibliotecas agora ou na etapa seguinte;
4. mantenha as opções de acesso remoto no padrão.

---

## 10. Bibliotecas de mídia

**Painel → Bibliotecas → Adicionar biblioteca.**

| Biblioteca | Tipo de conteúdo | Pasta |
|---|---|---|
| Filmes | Filmes | `/media/Filmes` |
| Séries | Programas de TV | `/media/Series` |

Os caminhos são os **de dentro do container** (`/media/...`), que apontam para
`/srv/wcacheflix/media/...` no host.

Recomendações: manter *"Baixar metadados"* ligado e deixar *"Salvar imagens de
capa na pasta de mídia"* **desligado** (a pasta entra somente leitura; o Jellyfin
guarda tudo em `/config`).

---

## 11. Aceleração de hardware (Intel / AMD VA-API)

Só faz sentido com `/dev/dri/renderD128` presente e o bloco `devices` no compose.

1. **Painel → Reprodução → Transcodificação.**
2. Aceleração de hardware: **VA-API**.
3. Dispositivo VA-API: `/dev/dri/renderD128`.
4. Habilite decodificação/codificação só dos codecs que a sua GPU suporta.
5. Salvar.

Confirme o suporte dentro do container:

```bash
docker exec -it wcacheflix /usr/lib/jellyfin-ffmpeg/vainfo
```

Para **ver a GPU trabalhando**, instale as ferramentas e monitore enquanto
força uma transcodificação (no player, escolha uma qualidade menor que a do
arquivo):

```bash
sudo apt install -y intel-gpu-tools
sudo intel_gpu_top
```

As engines **Render/3D** e **Video** devem sair de 0%. Nos logs do Jellyfin
devem aparecer `-hwaccel vaapi`, `h264_vaapi`/`hevc_vaapi` e filtros `scale_vaapi`.

> GPU integrada é modesta: serve para 1–2 transcodificações simultâneas. O ideal
> é o cliente fazer **Direct Play** (sem transcodificar) sempre que possível.

---

## 12. Acesso remoto com Tailscale

```bash
sudo ./scripts/07-install-tailscale.sh
sudo tailscale up          # abra o link exibido e autentique
tailscale ip -4            # ex.: 100.x.y.z
```

Instale o Tailscale também no aparelho que vai acessar de fora (celular, PC) e
entre na **mesma conta**. Depois:

```text
http://100.x.y.z:8096
```

**Não** faça port forwarding da porta 8096 no roteador.

Uma Smart TV normalmente não roda Tailscale — dentro de casa ela acessa pelo IP
local; para assistir fora de casa, use um aparelho intermediário com Tailscale.

---

## 13. Firewall

```bash
# só SSH liberado (acesso ao Jellyfin fica pela Tailnet):
sudo ./scripts/08-setup-firewall.sh

# OU também liberar a porta do Jellyfin na rede local:
sudo ./scripts/08-setup-firewall.sh --lan-8096
```

O script libera **OpenSSH antes** de ativar o UFW, para você não perder o acesso.

---

## 14. Boot automático e teste de reboot

Habilitados nas etapas anteriores:

```bash
sudo systemctl enable docker ssh tailscaled wcacheflix.service
```

Sequência esperada no boot:

```text
liga → Ubuntu → monta /srv/wcacheflix → docker → wcacheflix.service → Jellyfin → Tailscale
```

**Teste real:** `sudo reboot`, e depois de subir:

```bash
./scripts/99-healthcheck.sh
```

Tudo verde = servidor se recupera sozinho.

---

## 15. Adicionar filmes e séries

O Jellyfin identifica os títulos pelo **nome do arquivo/pasta**. Use a estrutura
abaixo dentro de `/srv/wcacheflix/media`.

**Filmes** — um arquivo (ou uma pasta) por filme, com o ano:

```text
media/Filmes/
├── Duna (2021).mkv
└── O Poderoso Chefão (1972)/
    └── O Poderoso Chefão (1972).mkv
```

**Séries** — pasta da série, subpasta por temporada, episódios `SxxEyy`:

```text
media/Series/
└── Nome da Série (ano)/
    └── Season 01/
        ├── Nome da Série S01E01.mkv
        ├── Nome da Série S01E01.pt-BR.srt
        └── Nome da Série S01E02.mkv
```

Regras práticas:

- use `S01E01`, `S01E02`… (dois dígitos); nunca só `101`;
- o ano na pasta ajuda a desambiguar remakes (ex.: *Dark Matter (2015)* vs *(2024)*);
- **legendas externas** compartilham o nome-base do vídeo e levam o idioma antes
  da extensão: `... S01E01.pt-BR.srt`. Converta legendas em Latin-1/Windows-1252
  para **UTF-8** (acentos aparecem como `N�o` quando estão na codificação errada);
- formatos comuns funcionam: MKV, MP4, AVI, TS; RMVB funciona mas quase sempre
  exige transcodificação;
- **não** deixe `.rar`/`.zip`/`.7z` dentro das pastas de biblioteca — extraia antes;
- depois de copiar, rode **Painel → Bibliotecas → Verificar todas as bibliotecas**.

> Fluxos automatizados de cópia/organização em massa (via scripts Python) são
> mantidos **localmente**, fora deste repositório público — veja `docs/` nesta
> máquina.

---

## 16. Operação e manutenção

**Logs do Jellyfin**

```bash
docker compose -f /opt/wcacheflix/compose.yaml logs -f --tail=100 wcacheflix
```

**Atualizar o Jellyfin**

```bash
cd /opt/wcacheflix
docker compose pull
sudo systemctl restart wcacheflix.service
docker image prune -f
```

**Parar / iniciar**

```bash
sudo systemctl stop wcacheflix.service
sudo systemctl start wcacheflix.service
```

**Backup da configuração** (mídia não precisa de backup; é reponível):

```bash
sudo systemctl stop wcacheflix.service
sudo tar czf ~/wcacheflix-config-$(date +%F).tar.gz -C /srv/wcacheflix config
sudo systemctl start wcacheflix.service
```

**Restaurar**

```bash
sudo systemctl stop wcacheflix.service
sudo tar xzf ~/wcacheflix-config-AAAA-MM-DD.tar.gz -C /srv/wcacheflix
sudo chown -R "$USER":"$USER" /srv/wcacheflix/config
sudo systemctl start wcacheflix.service
```

**Espaço em disco e saúde do HD**

```bash
df -hT /srv/wcacheflix
sudo apt install -y smartmontools
sudo smartctl -H /dev/disk/by-id/ata-SEU_DISCO
```

---

## 17. Diagnóstico rápido

| Sintoma | O que checar |
|---|---|
| Jellyfin não abre | `systemctl status wcacheflix.service`; `docker compose -f /opt/wcacheflix/compose.yaml ps`; `docker compose ... logs` |
| Porta 8096 fechada | `ss -lnt \| grep 8096`; firewall: `sudo ufw status` |
| Biblioteca vazia | caminho é `/media/...` (do container)? permissões de leitura? `Verificar biblioteca` |
| Disco não montou | `findmnt /srv/wcacheflix`; `sudo mount -a`; conferir `UUID` no `/etc/fstab` vs `blkid` |
| Serviço subiu sem o disco | `RequiresMountsFor` no unit; ver `journalctl -u wcacheflix.service` |
| GPU não aparece no container | bloco `devices` no compose? `RENDER_GID` certo no `.env`? `docker exec wcacheflix ls -l /dev/dri` |
| Transcodificação só na CPU | VA-API + `/dev/dri/renderD128` no painel; `vainfo` no container; `intel_gpu_top` durante a reprodução |
| Tailscale não conecta | `systemctl status tailscaled`; `sudo tailscale up`; `tailscale status` |
| SSH não funciona | `systemctl status ssh`; `sudo ufw allow OpenSSH` |

Comando único de verificação:

```bash
./scripts/99-healthcheck.sh
```

---

## 18. Estrutura do repositório

```text
wcacheflix/
├── README.md
├── TUTORIAL.md                 este arquivo
├── compose.yaml                definição do container Jellyfin
├── .env.example                modelo do /opt/wcacheflix/.env
├── systemd/
│   └── wcacheflix.service      unidade systemd (subida no boot, depende da montagem)
├── scripts/
│   ├── lib.sh                  funções comuns
│   ├── 01-host-tuning.sh       notebook não suspende ao fechar a tampa (opcional)
│   ├── 02-install-docker.sh    Docker CE pelo repositório oficial
│   ├── 03-prepare-storage.py   particiona/formata/monta o disco de mídia (destrutivo, dry-run por padrão)
│   ├── 04-create-layout.sh     cria /opt/wcacheflix e /srv/wcacheflix/{config,cache,media/...}
│   ├── 05-generate-env.sh      gera o .env e copia o compose
│   ├── 06-install-service.sh   instala e habilita wcacheflix.service
│   ├── 07-install-tailscale.sh acesso remoto
│   ├── 08-setup-firewall.sh    UFW (SSH sempre; 8096 opcional)
│   └── 99-healthcheck.sh       verificação de saúde (não altera nada)
└── docs/                       LOCAL, fora do git (.gitignore) — roteiros e scripts
                                Python de cópia/organização de mídia desta máquina
```

---

## 19. Referências

- Jellyfin — Instalação com Docker: <https://jellyfin.org/docs/general/installation/container>
- Jellyfin — Hardware Acceleration (Intel): <https://jellyfin.org/docs/general/administration/hardware-acceleration/intel>
- Docker Engine — Ubuntu: <https://docs.docker.com/engine/install/ubuntu/>
- Tailscale — Linux: <https://tailscale.com/kb/1031/install-linux>
- systemd — `RequiresMountsFor`: <https://www.freedesktop.org/software/systemd/man/systemd.unit.html>
