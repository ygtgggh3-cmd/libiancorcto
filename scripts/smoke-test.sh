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
    -append "boot=live components locales=es_PE.UTF-8 keyboard-layouts=latam timezone=America/Lima console=ttyS0,115200 libian.autotest systemd.journald.forward_to_console=1 systemd.journald.max_level_console=info" \
    -vga std -display none -serial "file:$OUT/serial.log" \
    -monitor "unix:$OUT/monB.sock,server,nowait" -no-reboot &
QPID=$!
ready=0; waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
    if grep -q 'LIBIAN-TV-AUTOTEST-OK' "$OUT/serial.log" 2>/dev/null; then ready=1; break; fi
    if grep -qE 'LIBIAN-TV-AUTOTEST-FAIL|LIBIAN-TV-ERROR' "$OUT/serial.log" 2>/dev/null; then break; fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 10; waited=$((waited+10))
done
sleep 5
shot "$OUT/monB.sock" "$OUT/live-desktop.png"
quit_vm "$OUT/monB.sock"; sleep 2; kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
rm -rf "$OUT/x"
if grep -q 'LIBIAN-TV-READY' "$OUT/serial.log" 2>/dev/null; then
    echo "OK: la interfaz LIBIAN TV arrancó (LIBIAN-TV-READY)"
    echo "- OK arranque live: la interfaz LIBIAN TV arrancó sola" >> "$SUMMARY"
else
    echo "FALLO: no apareció LIBIAN-TV-READY"; echo "- FALLO arranque live: no apareció LIBIAN-TV-READY" >> "$SUMMARY"; rc=1
fi
if [ "$ready" -eq 1 ]; then
    echo "OK: autoprueba de la interfaz (todas las pantallas, Wi-Fi, teclado en pantalla, barra de cierre) en ${waited}s"
    echo "- OK autoprueba de la interfaz (menús, Wi-Fi, teclado en pantalla, barra de cierre)" >> "$SUMMARY"
else
    echo "FALLO: la autoprueba de la interfaz no terminó bien en ${TIMEOUT}s"
    echo "- FALLO autoprueba de la interfaz (ver serial.log)" >> "$SUMMARY"
    grep -E 'LIBIAN-TV' "$OUT/serial.log" 2>/dev/null | tail -n 20 | cut -c1-600 || true
    tail -n 40 "$OUT/serial.log" 2>/dev/null || true
    rc=1
fi
# Vacuumtube / sesión: líneas informativas
grep -E 'libian-tv-session' "$OUT/serial.log" 2>/dev/null | tail -n 3 || true

# Análisis de la captura: ¿se dibujó la interfaz de colores?
if [ -s "$OUT/live-desktop.png" ]; then
    python3 - "$OUT/live-desktop.png" <<'PY'
import subprocess, sys
raw = subprocess.run(["convert", sys.argv[1], "-resize", "96x60!", "-depth", "8", "txt:-"],
                     capture_output=True, text=True).stdout
px = []
for line in raw.splitlines()[1:]:
    try:
        rgb = line.split("(")[1].split(")")[0].split(",")[:3]
        px.append(tuple(int(float(v.strip().rstrip("%"))) for v in rgb))
    except (IndexError, ValueError):
        pass
n = max(len(px), 1)
bright = sum(1 for r, g, b in px if max(r, g, b) > 70) / n
red = sum(1 for r, g, b in px if r > 150 and g < 90 and b < 90) / n
green = sum(1 for r, g, b in px if g > 110 and r < 60 and b < 130) / n
blue = sum(1 for r, g, b in px if b > 170 and r < 90) / n
msg = "captura: brillante %.0f%%, rojo %.1f%%, verde %.1f%%, azul %.1f%%" % (
    bright * 100, red * 100, green * 100, blue * 100)
print(msg)
open(__import__("os").environ.get("GITHUB_STEP_SUMMARY", "/dev/null"), "a").write("- " + msg + "\n")
print("::notice::" + msg)
sys.exit(0 if bright > 0.03 else 3)
PY
    if [ $? -eq 3 ]; then echo "FALLO: la captura está casi negra (la interfaz no se dibujó)"; echo "- FALLO captura casi negra" >> "$SUMMARY"; rc=1; fi
fi
exit "$rc"
