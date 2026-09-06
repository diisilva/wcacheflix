#!/usr/bin/env bash
# 07 - Instala o Tailscale (acesso remoto seguro, sem abrir porta no roteador).
#
# Uso:  sudo ./scripts/07-install-tailscale.sh
# Depois rode, como seu usuário:  sudo tailscale up   e abra o link no navegador.
source "$(dirname "$0")/lib.sh"
need_root
need_ubuntu
. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-jammy}}"

if command -v tailscale >/dev/null 2>&1; then
  ok "Tailscale já instalado: $(tailscale version | head -1)"
else
  step "Adicionando repositório oficial do Tailscale ($CODENAME)"
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.noarmor.gpg" \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.tailscale-keyring.list" \
    -o /etc/apt/sources.list.d/tailscale.list
  step "Instalando"
  apt-get update
  apt-get install -y tailscale
fi

step "Habilitando tailscaled"
systemctl enable --now tailscaled

ok "Instalado. Agora autentique este aparelho:"
echo "    sudo tailscale up"
echo "Depois: 'tailscale ip -4' mostra o IP para acessar http://<IP-tailscale>:8096"
echo "NÃO faça port forwarding da porta 8096 no roteador."
