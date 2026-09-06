#!/usr/bin/env bash
# 01 - Ajustes de host para uso como servidor (opcional).
#
# Faz o notebook NÃO suspender ao fechar a tampa e bloqueia sleep/hibernação.
# Pule esta etapa em um desktop ou mini-PC que já fica sempre ligado.
#
# Uso:  sudo ./scripts/01-host-tuning.sh
source "$(dirname "$0")/lib.sh"
need_root

step "Configurando systemd-logind para ignorar a tampa e ociosidade"
install -d -m 0755 /etc/systemd/logind.conf.d
tee /etc/systemd/logind.conf.d/homeserver.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
ok "/etc/systemd/logind.conf.d/homeserver.conf gravado"

step "Mascarando alvos de suspensão e hibernação"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

step "Reiniciando systemd-logind"
systemctl restart systemd-logind || warn "Falha ao reiniciar logind; efeito completo só após reboot."

ok "Ajustes aplicados. Confira com: systemctl status sleep.target (deve estar 'masked')."
