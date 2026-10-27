#!/usr/bin/env bash
# Verifica que la ISO sea válida y contenga lo imprescindible. Falla (exit 1) si no.
set -euo pipefail
ISO="${1:?uso: verify-iso.sh archivo.iso}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
errors=0
ok()   { echo "OK    $*"; echo "- OK $*" >> "$SUMMARY"; }
warn() { echo "AVISO $*"; echo "- AVISO $*" >> "$SUMMARY"; echo "::warning::$*" 2>/dev/null || true; }
bad()  { echo "ERROR $*"; echo "- ERROR $*" >> "$SUMMARY"; echo "::error::$*" 2>/dev/null || true; errors=$((errors+1)); }

[ -s "$ISO" ] || { bad "la ISO no existe o está vacía: $ISO"; exit 1; }
size=$(stat -c %s "$ISO")
if [ "$size" -ge $((400*1024*1024)) ]; then ok "tamaño $(numfmt --to=iec "$size")"; else bad "ISO demasiado pequeña: $size bytes"; fi

file -b "$ISO" | grep -qi 'ISO 9660' && ok "formato ISO 9660 ($(file -b "$ISO" | cut -c1-80))" || bad "no es ISO 9660"
sig=$(dd if="$ISO" bs=1 skip=510 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$sig" = "55aa" ] && ok "MBR híbrido (firma 55AA): se puede grabar en USB" || bad "falta firma MBR 55AA (no es iso-hybrid)"

et=$(xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null || true)
echo "$et" | grep -qi 'BIOS' && ok "arranque BIOS (El Torito)" || bad "sin entrada de arranque BIOS"
echo "$et" | grep -qi 'UEFI' && ok "arranque UEFI (El Torito)" || warn "sin entrada de arranque UEFI"

bsdtar -tf "$ISO" | sed "s#^\./##" > "$WORK/files.txt"
for pat in '^live/filesystem\.squashfs$' '^live/vmlinuz' '^live/initrd\.img' '^isolinux/isolinux\.bin$' '^boot/grub/grub\.cfg$'; do
    grep -Eq "$pat" "$WORK/files.txt" && ok "ISO contiene ${pat//\\/}" || bad "ISO NO contiene ${pat//\\/}"
done

echo "Extrayendo filesystem.squashfs para inspeccionarlo…"
bsdtar -xf "$ISO" -C "$WORK" live/filesystem.squashfs
unsquashfs -l "$WORK/live/filesystem.squashfs" > "$WORK/sq.txt"
for f in usr/local/bin/libian-tv usr/local/bin/libian-tv-session usr/share/xsessions/libian-tv.desktop \
         etc/lightdm/lightdm.conf.d/50-libian.conf etc/systemd/system/libian-autologin.service \
         usr/sbin/lightdm usr/bin/firefox-esr usr/bin/vlc usr/bin/mpv usr/bin/thunar \
         usr/bin/xfce4-terminal usr/bin/xfwm4 usr/bin/calamares usr/bin/python3; do
    grep -Fxq "squashfs-root/$f" "$WORK/sq.txt" && ok "sistema contiene /$f" || bad "sistema NO contiene /$f"
done
if grep -Eiq '^squashfs-root/opt/[^/]*vacuum[^/]*/' "$WORK/sq.txt" || grep -Eiq 'squashfs-root/usr/share/applications/.*vacuum.*\.desktop' "$WORK/sq.txt"; then
    ok "VacuumTube (YouTube TV) incluido"
else
    warn "VacuumTube NO está en la imagen: el menú usará Firefox para YouTube"
fi
for f in usr/local/bin/libian-tv-close etc/libian/xbindkeysrc usr/bin/xdotool usr/bin/xbindkeys usr/bin/nmcli usr/bin/wpctl usr/bin/wmctrl usr/bin/xinput usr/bin/pactl usr/local/bin/libian-tv-menu usr/local/bin/libian-tv-return etc/xdg/autostart/libian-tv-return.desktop; do
    grep -Fxq "squashfs-root/$f" "$WORK/sq.txt" && ok "sistema contiene /$f" || bad "sistema NO contiene /$f"
done
grep -Eq '^squashfs-root/lib/modules/[^/]+/kernel$|^squashfs-root/usr/lib/modules/[^/]+/kernel$' "$WORK/sq.txt" \
    && ok "módulos del kernel presentes" || bad "sin módulos del kernel"

unsquashfs -d "$WORK/root" "$WORK/live/filesystem.squashfs" etc/apt etc/os-release >/dev/null 2>&1 || true
apt_text=$(cat "$WORK"/root/etc/apt/sources.list "$WORK"/root/etc/apt/sources.list.d/* 2>/dev/null || true)
echo "--- /etc/apt dentro de la ISO ---"; echo "$apt_text" | head -40
if echo "$apt_text" | grep -q 'trixie'; then ok "sources de apt usan trixie"; else warn "no se encontró 'trixie' en /etc/apt de la imagen"; fi
if echo "$apt_text" | grep -q 'trixie-security'; then ok "repositorio de seguridad trixie-security configurado en la imagen"; else warn "trixie-security NO aparece en /etc/apt de la imagen"; fi
if echo "$apt_text" | grep -q 'security.debian.org/debian-security'; then ok "URL de seguridad correcta (security.debian.org/debian-security)"; else warn "URL de seguridad no encontrada tal cual en /etc/apt"; fi
if echo "$apt_text" | grep -q 'trixie-updates'; then ok "trixie-updates configurado en la imagen"; else warn "trixie-updates no aparece en /etc/apt de la imagen"; fi
grep -h '^PRETTY_NAME' "$WORK/root/etc/os-release" 2>/dev/null | sed 's/^/- /' >> "$SUMMARY" || true

if [ "$errors" -gt 0 ]; then echo "VERIFICACIÓN FALLIDA: $errors error(es)"; exit 1; fi
echo "VERIFICACIÓN ESTRUCTURAL OK (esto NO demuestra que arranque: ver smoke-test.sh)"
