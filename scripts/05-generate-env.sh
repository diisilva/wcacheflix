#!/usr/bin/env bash
# 05 - Gera /opt/wcacheflix/.env e copia o compose.yaml do repositório.
#
# PUID/PGID  = seu usuário/grupo.
# RENDER_GID = grupo de /dev/dri/renderD128 (aceleração de hardware).
#              Se não houver GPU compatível, RENDER_GID fica vazio e você deve
#              remover o bloco "devices" de /opt/wcacheflix/compose.yaml.
#
# Uso (sem sudo):  ./scripts/05-generate-env.sh
source "$(dirname "$0")/lib.sh"
need_no_root
[ -d /opt/wcacheflix ] || die "/opt/wcacheflix não existe. Rode antes o 04-create-layout.sh."
[ -w /opt/wcacheflix ] || die "/opt/wcacheflix não é gravável pelo seu usuário. Rode o 04-create-layout.sh."

PUID="$(id -u)"
PGID="$(id -g)"
if [ -e /dev/dri/renderD128 ]; then
  RENDER_GID="$(stat -c '%g' /dev/dri/renderD128)"
  ok "GPU encontrada: /dev/dri/renderD128 (grupo $RENDER_GID)"
else
  RENDER_GID=""
  warn "/dev/dri/renderD128 não existe — sem aceleração de hardware."
  warn "Remova o bloco 'devices:' de /opt/wcacheflix/compose.yaml antes de subir."
fi

step "Gravando /opt/wcacheflix/.env"
cat > /opt/wcacheflix/.env <<EOF
PUID=$PUID
PGID=$PGID
RENDER_GID=$RENDER_GID
EOF
cat /opt/wcacheflix/.env

step "Copiando compose.yaml para /opt/wcacheflix"
cp -v "$REPO_ROOT/compose.yaml" /opt/wcacheflix/compose.yaml

step "Validando com 'docker compose config'"
( cd /opt/wcacheflix && docker compose config >/dev/null ) \
  && ok "compose.yaml válido" \
  || die "docker compose config falhou; revise /opt/wcacheflix/compose.yaml"
