#!/usr/bin/env bash
# 99 - Verificação rápida do wcacheflix. Não altera nada.
#
# Uso (sem sudo):  ./scripts/99-healthcheck.sh
source "$(dirname "$0")/lib.sh"

fail_count=0
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else warn "$1 — FALHOU"; fail_count=$((fail_count+1)); fi; }

step "Sistema"
check "Docker responde"                 "docker info"
check "/srv/wcacheflix montado"          "mountpoint -q /srv/wcacheflix"
check "unidade wcacheflix habilitada"    "systemctl is-enabled wcacheflix.service"
check "unidade wcacheflix ativa"         "systemctl is-active wcacheflix.service"

step "Container"
check "container 'wcacheflix' em execução" "docker ps --filter name=^/wcacheflix$ --filter status=running --format '{{.Names}}' | grep -qx wcacheflix"
check "porta 8096 escutando"             "ss -lnt | grep -q ':8096'"
check "HTTP 200/302 em 127.0.0.1:8096"   "curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8096 | grep -qE '200|302'"

step "GPU no container (se aplicável)"
if [ -e /dev/dri/renderD128 ]; then
  check "/dev/dri/renderD128 visível no container" "docker exec wcacheflix test -e /dev/dri/renderD128"
  check "vainfo dentro do container"       "docker exec wcacheflix /usr/lib/jellyfin-ffmpeg/vainfo"
else
  info "sem /dev/dri/renderD128 no host — pulando checagem de GPU"
fi

step "Espaço"
df -hT /srv/wcacheflix | sed 's/^/  /'

echo
[ "$fail_count" -eq 0 ] && ok "Tudo certo." || die "$fail_count verificação(ões) falharam."
