#!/usr/bin/env bash
# 08 - Firewall UFW: libera SSH sempre; a porta 8096 do Jellyfin é opcional.
#
# Uso:
#   sudo ./scripts/08-setup-firewall.sh              # só SSH (acesso ao Jellyfin via Tailscale)
#   sudo ./scripts/08-setup-firewall.sh --lan-8096   # também libera 8096/tcp para a rede local
source "$(dirname "$0")/lib.sh"
need_root

OPEN_8096=0
[ "${1:-}" = "--lan-8096" ] && OPEN_8096=1

command -v ufw >/dev/null 2>&1 || { step "Instalando ufw"; apt-get update && apt-get install -y ufw; }

step "Liberando SSH (antes de ativar, para não perder acesso)"
ufw allow OpenSSH

if [ "$OPEN_8096" -eq 1 ]; then
  step "Liberando 8096/tcp (Jellyfin na LAN)"
  ufw allow 8096/tcp
else
  warn "8096/tcp NÃO liberada. Acesse o Jellyfin pela Tailnet, ou rode de novo com --lan-8096."
fi

step "Ativando o firewall"
ufw --force enable
ufw status verbose
