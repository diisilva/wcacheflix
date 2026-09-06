#!/usr/bin/env bash
# 06 - Instala e habilita a unidade systemd wcacheflix.service.
#
# A unidade sobe o Compose no boot e só depois que /srv/wcacheflix estiver
# montado (RequiresMountsFor), evitando gravar mídia no SSD por engano.
#
# Uso:  sudo ./scripts/06-install-service.sh
source "$(dirname "$0")/lib.sh"
need_root

UNIT_SRC="$REPO_ROOT/systemd/wcacheflix.service"
UNIT_DST="/etc/systemd/system/wcacheflix.service"

[ -f "$UNIT_SRC" ]                       || die "não achei $UNIT_SRC"
[ -f /opt/wcacheflix/compose.yaml ]      || die "/opt/wcacheflix/compose.yaml ausente. Rode o 05-generate-env.sh."
[ -f /opt/wcacheflix/.env ]             || die "/opt/wcacheflix/.env ausente. Rode o 05-generate-env.sh."
mountpoint -q /srv/wcacheflix           || die "/srv/wcacheflix não está montado."
command -v docker >/dev/null            || die "Docker não instalado. Rode o 02-install-docker.sh."

step "Instalando $UNIT_DST"
install -m 0644 -o root -g root "$UNIT_SRC" "$UNIT_DST"

step "Validando e habilitando"
systemd-analyze verify "$UNIT_DST"
systemctl daemon-reload
systemctl enable wcacheflix.service

ok "Unidade habilitada. Suba agora com:  sudo systemctl start wcacheflix.service"
echo "Baixe a imagem antes, se ainda não tiver:  ( cd /opt/wcacheflix && docker compose pull )"
