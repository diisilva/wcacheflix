#!/usr/bin/env bash
# 04 - Cria a estrutura de pastas do wcacheflix e passa a posse ao seu usuário.
#
#   /opt/wcacheflix            -> arquivos do Compose (no SSD)
#   /srv/wcacheflix/config     -> configuração do Jellyfin
#   /srv/wcacheflix/cache      -> cache/transcodes do Jellyfin
#   /srv/wcacheflix/media/Filmes
#   /srv/wcacheflix/media/Series
#
# Uso:  sudo ./scripts/04-create-layout.sh
source "$(dirname "$0")/lib.sh"
need_root

TARGET_USER="${SUDO_USER:-$USER}"
[ "$TARGET_USER" != "root" ] || die "Rode com 'sudo' a partir do seu usuário normal."

MOUNT="${WCX_MOUNT:-/srv/wcacheflix}"
mountpoint -q "$MOUNT" || die "$MOUNT não está montado. Rode antes o 03-prepare-storage.py."

step "Criando diretórios"
install -d -m 0755 /opt/wcacheflix
for d in config cache media media/Filmes media/Series; do
  install -d -m 0755 "$MOUNT/$d"
done

step "Ajustando posse para '$TARGET_USER'"
chown -R "$TARGET_USER":"$TARGET_USER" /opt/wcacheflix "$MOUNT"

ok "Estrutura pronta:"
find "$MOUNT" -maxdepth 2 -type d -printf '  %p\n' | sort
echo "  /opt/wcacheflix"
