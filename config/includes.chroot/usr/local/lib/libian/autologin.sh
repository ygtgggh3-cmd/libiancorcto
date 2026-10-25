#!/bin/sh
# Configura el inicio automático de LightDM para el primer usuario real
# (uid >= 1000). Funciona en el Live ("user") y en el sistema instalado.
# Para desactivarlo:  sudo mkdir -p /etc/libian && sudo touch /etc/libian/no-autologin
set -eu
CONF="${LIBIAN_AUTOLOGIN_CONF:-/etc/lightdm/lightdm.conf.d/60-libian-autologin.conf}"

if [ -e /etc/libian/no-autologin ]; then
    rm -f "$CONF"
    exit 0
fi

user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $3 ":" $1}' \
       | sort -n | head -n 1 | cut -d: -f2)

if [ -z "${user:-}" ]; then
    rm -f "$CONF"
    exit 0
fi

mkdir -p "$(dirname "$CONF")"
cat > "$CONF" <<CONFEOF
[Seat:*]
autologin-user=$user
autologin-user-timeout=0
autologin-session=libian-tv
CONFEOF
