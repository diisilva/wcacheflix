#!/usr/bin/env bash
# 02 - Instala Docker Engine + Compose pelo repositório oficial da Docker
#      e adiciona o seu usuário ao grupo 'docker'.
#
# Uso:  sudo ./scripts/02-install-docker.sh
source "$(dirname "$0")/lib.sh"
need_root
need_ubuntu

TARGET_USER="${SUDO_USER:-$USER}"
[ "$TARGET_USER" != "root" ] || die "Rode com 'sudo' a partir do seu usuário normal (não como root puro)."

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  ok "Docker e Compose já instalados: $(docker --version)"
else
  step "Removendo pacotes conflitantes (se houver)"
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" >/dev/null 2>&1 || true
  done

  step "Adicionando repositório oficial da Docker"
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  step "Instalando Docker Engine"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
fi

step "Habilitando o serviço docker"
systemctl enable --now docker

step "Adicionando '$TARGET_USER' ao grupo 'docker'"
usermod -aG docker "$TARGET_USER"

ok "Docker pronto: $(docker --version)"
warn "Saia e entre da sessão (ou reinicie) para usar 'docker' sem sudo."
