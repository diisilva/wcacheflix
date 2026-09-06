# wcacheflix

Servidor de mídia **Jellyfin** em Docker sobre **Ubuntu**, para rodar num
notebook, mini-PC ou desktop reaproveitado. Mídia em disco dedicado, subida
automática no boot via systemd e acesso remoto seguro com **Tailscale** — sem
abrir nenhuma porta no roteador.

O projeto é **reprodutível**: os mesmos scripts e arquivos recriam o servidor em
outro Ubuntu, em outra casa e em outra rede. Onde aparecer `SEU_USUARIO`,
`SEU_DISCO` ou um IP de exemplo, troque pelos valores da sua máquina.

- 📘 **Passo a passo completo:** [`TUTORIAL.md`](TUTORIAL.md)
- 🧩 **Scripts de apoio:** [`scripts/`](scripts/) (idempotentes)
- 🐳 **Container:** [`compose.yaml`](compose.yaml) · **Serviço:** [`systemd/wcacheflix.service`](systemd/wcacheflix.service)

---

## O que você obtém

| Recurso | Como é entregue |
|---|---|
| Jellyfin em container, rodando como o seu usuário | `compose.yaml` com `user: ${PUID}:${PGID}` |
| Mídia protegida | `/srv/wcacheflix/media` entra no container **somente leitura** |
| Boot resiliente | `wcacheflix.service` só sobe depois que o disco monta (`RequiresMountsFor`) |
| Disco de mídia não trava o boot | montagem por **UUID** com `nofail` no `/etc/fstab` |
| Transcodificação por GPU (opcional) | `/dev/dri/renderD128` + VA-API |
| Acesso remoto sem expor porta | **Tailscale** (veja abaixo) |
| Log do container limitado | `json-file`, `max-size=10m`, `max-file=3` |

---

## Início rápido

Na máquina servidor (Ubuntu 22.04+, com `sudo`):

```bash
git clone https://github.com/diisilva/wcacheflix.git
cd wcacheflix
chmod +x scripts/*.sh scripts/*.py

sudo ./scripts/01-host-tuning.sh          # opcional: notebook não suspende ao fechar a tampa
sudo ./scripts/02-install-docker.sh       # Docker CE (repositório oficial) + grupo docker
#   -> saia e entre da sessão, ou reinicie

sudo ./scripts/03-prepare-storage.py --disk /dev/disk/by-id/ata-SEU_DISCO           # dry-run
sudo ./scripts/03-prepare-storage.py --disk /dev/disk/by-id/ata-SEU_DISCO --apply   # DESTRUTIVO
sudo ./scripts/04-create-layout.sh        # /opt/wcacheflix e /srv/wcacheflix/{config,cache,media/...}
./scripts/05-generate-env.sh              # gera .env e copia o compose (sem sudo)

sudo ./scripts/06-install-service.sh
( cd /opt/wcacheflix && docker compose pull )
sudo systemctl start wcacheflix.service

sudo ./scripts/07-install-tailscale.sh    # acesso remoto (veja seção abaixo)
sudo ./scripts/08-setup-firewall.sh       # UFW: SSH sempre; use --lan-8096 p/ liberar 8096 na LAN

./scripts/99-healthcheck.sh               # verificação final
```

Acesso na rede local: `http://<IP-do-servidor>:8096` (descubra com `hostname -I`).

O detalhamento de cada etapa, a configuração do Jellyfin (bibliotecas,
aceleração de hardware) e o padrão de nomes de filmes/séries estão no
[`TUTORIAL.md`](TUTORIAL.md).

---

## Tailscale — para que serve e como configurar

### Função

O Jellyfin escuta na porta **8096**, em HTTP e sem autenticação forte na borda.
Publicar isso na Internet (port forwarding no roteador) é arriscado. O Tailscale
resolve isso criando uma **rede privada virtual em malha (mesh VPN)** entre os
**seus** aparelhos:

- cada aparelho que entra na sua conta ganha um IP fixo `100.x.y.z` (faixa
  **CGNAT 100.64.0.0/10**) que só existe dentro da sua *tailnet*;
- o tráfego é **cifrado ponta a ponta** (WireGuard) e vai direto de um aparelho
  ao outro sempre que possível;
- **nenhuma porta é aberta** no roteador; o servidor faz apenas conexões de
  saída para o coordenador do Tailscale;
- só aparelhos autenticados na sua conta enxergam o servidor.

Resultado: de qualquer lugar, `http://100.x.y.z:8096` chega no Jellyfin como se
você estivesse em casa, sem o Jellyfin ficar exposto publicamente.

```text
Internet
   │            (NÃO: port forwarding 8096 -> Jellyfin exposto)
   ▼
Tailscale (WireGuard, cifrado, só seus aparelhos)
   ▼
Servidor  ──►  Jellyfin :8096
```

### Configurar

1. Crie uma conta gratuita em <https://tailscale.com> (Google/GitHub/Microsoft/e-mail).
2. No servidor:

   ```bash
   sudo ./scripts/07-install-tailscale.sh
   sudo tailscale up
   ```

   O comando imprime um link `https://login.tailscale.com/a/...`. Abra no
   navegador, faça login e o servidor entra na sua *tailnet*.
3. Descubra o IP do servidor na tailnet:

   ```bash
   tailscale ip -4        # ex.: 100.124.48.16
   ```
4. Instale o Tailscale **no aparelho que vai acessar de fora** (celular, notebook)
   e faça login **na mesma conta**. Apps oficiais: Android, iOS, Windows, macOS,
   Linux.
5. Nesse aparelho, abra `http://100.124.48.16:8096`.

Opcional, mas recomendado:

- **MagicDNS** (no painel do Tailscale, *DNS → Enable MagicDNS*): passa a
  funcionar `http://nome-do-servidor:8096` em vez do IP numérico.
- **Desativar expiração de chave** do servidor (no painel, na máquina, *Disable
  key expiry*): evita que o servidor precise reautenticar a cada ~6 meses. Sem
  isso, use um comando único de manutenção: `sudo tailscale up` de novo.
- **Smart TV**: TVs geralmente não rodam Tailscale. Dentro de casa a TV usa o IP
  **local** do servidor. Para assistir na TV **fora de casa**, use um *subnet
  router* (`sudo tailscale up --advertise-routes=192.168.0.0/24` no servidor +
  aprovar a rota no painel) ou um roteador de viagem com Tailscale.

### Quando der problema

| Sintoma | Verificação / correção |
|---|---|
| `tailscale` não conecta | `systemctl status tailscaled` (deve estar *active*); se não, `sudo systemctl enable --now tailscaled` |
| `Logged out` / pede login | `sudo tailscale up` de novo e reautentique o link |
| `NeedsLogin` após meses | expiração de chave: reautentique e depois desative *key expiry* no painel |
| IP `100.x` não responde | `tailscale status` nos dois aparelhos — ambos devem aparecer *online* e na mesma conta |
| Conecta mas Jellyfin não abre | teste no próprio servidor: `curl -I http://localhost:8096`; confira o container: `./scripts/99-healthcheck.sh` |
| Lento / cai a conexão | `tailscale netcheck` (diagnóstico de NAT/UDP); redes muito restritivas forçam *relay* (DERP), que é mais lento porém funciona |
| Firewall bloqueando | o UFW **não** precisa liberar 8096 para o acesso via Tailscale (a interface `tailscale0` é confiável); só libere 8096 se quiser acesso pela LAN |
| Vários aparelhos, quer restringir | use **ACLs** no painel do Tailscale para limitar quem alcança o servidor na porta 8096 |
| Ver estado geral | `tailscale status`, `tailscale ip -4`, `tailscale netcheck`, `journalctl -u tailscaled -e` |

> **Nunca** compense um problema de Tailscale abrindo a porta 8096 no roteador.
> Se o acesso remoto precisar ser resolvido, é dentro do Tailscale.

---

## Estrutura do repositório

```text
wcacheflix/
├── README.md                  este arquivo
├── TUTORIAL.md                passo a passo completo, com índice
├── compose.yaml               container Jellyfin (lê /opt/wcacheflix/.env)
├── .env.example               modelo do .env
├── systemd/wcacheflix.service unidade systemd (boot depende da montagem)
├── scripts/                   apoio, idempotentes e com dry-run onde é destrutivo
│   ├── lib.sh
│   ├── 01-host-tuning.sh
│   ├── 02-install-docker.sh
│   ├── 03-prepare-storage.py
│   ├── 04-create-layout.sh
│   ├── 05-generate-env.sh
│   ├── 06-install-service.sh
│   ├── 07-install-tailscale.sh
│   ├── 08-setup-firewall.sh
│   └── 99-healthcheck.sh
└── docs/                      LOCAL (no .gitignore) — roteiros e scripts Python
                               de cópia/organização de mídia; não fazem parte
                               do projeto reprodutível
```

## Requisitos

- Ubuntu 22.04+ com `sudo` (Debian/Mint/Pop!\_OS costumam funcionar).
- Um disco **inteiro dedicado** à mídia (será apagado).
- Opcional: GPU Intel/AMD com `/dev/dri/renderD128` para transcodificação acelerada.
- Opcional: conta gratuita no Tailscale para acesso remoto.
