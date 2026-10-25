#!/usr/bin/env bash
# Comprobaciones previas a compilar (se ejecuta DENTRO de un contenedor debian:trixie):
#  1) Las direcciones de los repositorios de trixie (principal, updates, seguridad) responden.
#  2) Todos los paquetes de las listas existen en trixie.
#     - libian.list.chroot (núcleo): si falta alguno, FALLA.
#     - libian-extra.list.chroot (opcional): se quitan los que no existen y se avisa.
set -euo pipefail
cd "$(dirname "$0")/.."
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
LISTS=config/package-lists
CORE=$LISTS/libian.list.chroot
EXTRA=$LISTS/libian-extra.list.chroot

MAIN="http://deb.debian.org/debian"
SEC="http://security.debian.org/debian-security"

echo "== 1/2 Repositorios de Debian trixie =="
status=0
for url in "$MAIN/dists/trixie/Release" \
           "$MAIN/dists/trixie-updates/Release" \
           "$SEC/dists/trixie-security/Release"; do
    expected=$(basename "$(dirname "$url")")   # trixie | trixie-updates | trixie-security
    if curl -fsSL --retry 3 --max-time 60 -o /tmp/Release "$url"; then
        suite=$(sed -n 's/^Suite: //p' /tmp/Release | head -n1)
        code=$(sed -n 's/^Codename: //p' /tmp/Release | head -n1)
        comps=$(sed -n 's/^Components: //p' /tmp/Release | head -n1)
        echo "OK   $url  (Suite=$suite Codename=$code Components=$comps)"
        echo "- OK \`$url\` (Codename \`$code\`, componentes: $comps)" >> "$SUMMARY"
        if [ "$code" != "$expected" ]; then
            echo "ERROR: $url: se esperaba Codename=$expected y es $code"; status=1
        fi
    else
        echo "ERROR: no responde $url"
        echo "- ERROR no responde \`$url\`" >> "$SUMMARY"
        status=1
    fi
done
[ "$status" -eq 0 ] || { echo "Repositorios incorrectos o inaccesibles."; exit 1; }

echo "== 2/2 Paquetes de las listas =="
rm -f /etc/apt/sources.list.d/*.sources /etc/apt/sources.list
cat > /etc/apt/sources.list.d/libian-check.sources <<EOT
Types: deb
URIs: $MAIN
Suites: trixie trixie-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: $SEC
Suites: trixie-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOT
apt-get update -qq

pkgs() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }
exists() { apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]'; }

missing_core=()
while read -r p; do
    exists "$p" || missing_core+=("$p")
done < <(pkgs "$CORE")
if [ "${#missing_core[@]}" -gt 0 ]; then
    echo "ERROR: paquetes del núcleo que NO existen en trixie: ${missing_core[*]}"
    echo "- ERROR paquetes del núcleo inexistentes en trixie: \`${missing_core[*]}\`" >> "$SUMMARY"
    exit 1
fi

removed=()
while read -r p; do
    if ! exists "$p"; then
        removed+=("$p")
        sed -i -E "/^[[:space:]]*${p//./\\.}[[:space:]]*(#.*)?$/d" "$EXTRA"
    fi
done < <(pkgs "$EXTRA")
if [ "${#removed[@]}" -gt 0 ]; then
    echo "AVISO: paquetes opcionales omitidos (no existen en trixie): ${removed[*]}"
    echo "- AVISO paquetes opcionales omitidos: \`${removed[*]}\`" >> "$SUMMARY"
fi
echo "Paquetes verificados: núcleo $(pkgs "$CORE" | wc -l), opcionales $(pkgs "$EXTRA" | wc -l)."
echo "- Paquetes verificados en trixie: núcleo $(pkgs "$CORE" | wc -l), opcionales $(pkgs "$EXTRA" | wc -l)" >> "$SUMMARY"
