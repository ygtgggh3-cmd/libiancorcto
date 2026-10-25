#!/usr/bin/env bash
# Prueba de arranque con QEMU (3 GB de RAM, como la PC objetivo):
#  A) Arranque BIOS normal desde la ISO (bootloader): captura de pantalla no negra.
#  B) Arranque directo de kernel+initrd de la ISO con consola serie: se espera que la
#     interfaz libian-tv escriba "LIBIAN-TV-READY" en el journal (=> LightDM, autologin,
#     sesión libian-tv y GTK funcionaron).
# Uso: smoke-test.sh archivo.iso directorio_salida [segundos_timeout]
set -uo pipefail
ISO="$(readlink -f "${1:?iso}")"
OUT="$(mkdir -p "${2:?salida}" && readlink -f "$2")"
TIMEOUT="${3:-900}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
rc=0

if [ -w /dev/kvm ]; then ACCEL=(-enable-kvm -cpu host); echo "KVM disponible"; else ACCEL=(-cpu max); echo "Sin KVM (emulación lenta)"; fi

shot() {  # $1 = socket, $2 = png
    python3 - "$1" "$OUT/tmp.ppm" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.5)
s.send(("screendump %s\n" % sys.argv[2]).encode()); time.sleep(2); s.close()
PY
    convert "$OUT/tmp.ppm" "$2" 2>/dev/null && rm -f "$OUT/tmp.ppm"
}
quit_vm() { python3 - "$1" <<'PY' 2>/dev/null
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.send(b"quit\n"); time.sleep(1)
PY
}

echo "== A) Arranque BIOS desde la ISO =="
qemu-system-x86_64 "${ACCEL[@]}" -m 3072 -smp 2 -cdrom "$ISO" -boot d -vga std -display none \
    -monitor "unix:$OUT/monA.sock,server,nowait" -serial none -no-reboot &
QPID=$!
sleep 75
shot "$OUT/monA.sock" "$OUT/bios-bootmenu.png"
quit_vm "$OUT/monA.sock"; sleep 2; kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
if [ -s "$OUT/bios-bootmenu.png" ]; then
    mean=$(convert "$OUT/bios-bootmenu.png" -colorspace Gray -format '%[fx:mean]' info:)
    if awk -v m="$mean" 'BEGIN{exit !(m>0.01)}'; then
        echo "OK: el bootloader BIOS muestra imagen (brillo medio $mean)"
        echo "- OK arranque BIOS: el bootloader muestra imagen" >> "$SUMMARY"
    else
        echo "FALLO: pantalla negra en arranque BIOS"; echo "- FALLO arranque BIOS: pantalla negra" >> "$SUMMARY"; rc=1
    fi
else
    echo "FALLO: no se obtuvo captura BIOS"; echo "- FALLO sin captura BIOS" >> "$SUMMARY"; rc=1
fi

echo "== B) Arranque del sistema live (serie) =="
mkdir -p "$OUT/x"
bsdtar -xf "$ISO" -C "$OUT/x" 'live/vmlinuz*' 'live/initrd.img*'
KERNEL=$(ls "$OUT"/x/live/vmlinuz* | head -n1); INITRD=$(ls "$OUT"/x/live/initrd.img* | head -n1)
qemu-system-x86_64 "${ACCEL[@]}" -m 3072 -smp 2 -cdrom "$ISO" -kernel "$KERNEL" -initrd "$INITRD" \
    -append "boot=live components locales=es_PE.UTF-8 keyboard-layouts=latam timezone=America/Lima console=ttyS0,115200 systemd.journald.forward_to_console=1 systemd.journald.max_level_console=info" \
    -vga std -display none -serial "file:$OUT/serial.log" \
    -monitor "unix:$OUT/monB.sock,server,nowait" -no-reboot &
QPID=$!
ready=0; waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
    if grep -q 'LIBIAN-TV-READY' "$OUT/serial.log" 2>/dev/null; then ready=1; break; fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 10; waited=$((waited+10))
done
sleep 5
shot "$OUT/monB.sock" "$OUT/live-desktop.png"
quit_vm "$OUT/monB.sock"; sleep 2; kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
rm -rf "$OUT/x"
if [ "$ready" -eq 1 ]; then
    echo "OK: la interfaz LIBIAN TV arrancó (marca LIBIAN-TV-READY tras ${waited}s)"
    echo "- OK arranque live: la interfaz LIBIAN TV arrancó sola en ${waited}s" >> "$SUMMARY"
else
    echo "FALLO: no apareció LIBIAN-TV-READY en ${TIMEOUT}s"
    echo "- FALLO arranque live: no apareció LIBIAN-TV-READY en ${TIMEOUT}s (ver serial.log)" >> "$SUMMARY"
    tail -n 60 "$OUT/serial.log" 2>/dev/null || true
    rc=1
fi
exit "$rc"
