#!/usr/bin/env bash
# Funções compartilhadas pelos scripts de apoio do wcacheflix.
# Uso: source "$(dirname "$0")/lib.sh"

set -Eeuo pipefail

# --- saída colorida -----------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_RED=$'\e[31m'
  C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
  C_RESET=; C_BOLD=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=
fi

info()  { printf '%s[ .. ]%s %s\n'  "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()   { printf '%s[FAIL]%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }
step()  { printf '\n%s==>%s %s%s%s\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }

# --- checagens de ambiente --------------------------------------------------
need_root()    { [ "$(id -u)" -eq 0 ] || die "Rode este script com sudo."; }
need_no_root() { [ "$(id -u)" -ne 0 ] || die "NÃO rode este script com sudo; use seu usuário normal."; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando ausente: '$1'. Instale antes de continuar."
}

need_ubuntu() {
  [ -r /etc/os-release ] || die "/etc/os-release ausente; distribuição não suportada."
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian|linuxmint|pop) : ;;
    *) warn "Distribuição '${ID:-desconhecida}' não testada; siga por sua conta e risco." ;;
  esac
}

confirm() {
  local prompt="${1:-Confirmar?}"
  local answer
  read -r -p "$prompt [digite SIM para continuar]: " answer
  [ "$answer" = "SIM" ] || die "Cancelado pelo usuário."
}

# Diretório raiz do repositório (um nível acima de scripts/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
