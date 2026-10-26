#!/usr/bin/env bash
# Descarga el .deb más reciente de VacuumTube (envoltorio de YouTube Leanback/TV, MIT,
# https://github.com/shy1132/VacuumTube) a config/packages.chroot/. live-build lo instala
# en la ISO. Si no se puede descargar, la compilación continúa SIN VacuumTube (el menú
# usa entonces Firefox para YouTube) y queda avisado; con REQUIRE_VACUUMTUBE=1 falla.
set -uo pipefail
cd "$(dirname "$0")/.."
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
DEST=config/packages.chroot
mkdir -p "$DEST"
rm -f "$DEST"/*.deb

soft_fail() {
    echo "::warning::VacuumTube no se instaló: $1"
    echo "- AVISO VacuumTube NO instalado: $1" >> "$SUMMARY"
    [ "${REQUIRE_VACUUMTUBE:-0}" = "1" ] && exit 1
    exit 0
}

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
json=$(curl -fsSL --retry 3 --max-time 60 "${auth[@]}" \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/shy1132/VacuumTube/releases/latest") \
    || soft_fail "no se pudo consultar la última versión en GitHub"

read -r tag url name < <(python3 -c '
import json, re, sys
d = json.load(sys.stdin)
debs = [a for a in d.get("assets", []) if a["name"].lower().endswith(".deb")]
pref = [a for a in debs if re.search(r"(amd64|x86_64|x64)", a["name"], re.I)] or debs
if not pref:
    sys.exit(1)
a = pref[0]
print(d.get("tag_name", "?"), a["browser_download_url"], a["name"])
' <<<"$json") || soft_fail "la última versión no trae un paquete .deb"

echo "Descargando VacuumTube $tag: $name"
curl -fL --retry 3 --max-time 600 -o "$DEST/$name" "$url" || soft_fail "falló la descarga de $url"

arch=$(dpkg-deb -f "$DEST/$name" Architecture 2>/dev/null || true)
pkg=$(dpkg-deb -f "$DEST/$name" Package 2>/dev/null || true)
ver=$(dpkg-deb -f "$DEST/$name" Version 2>/dev/null || true)
if [ -z "$pkg" ] || { [ "$arch" != "amd64" ] && [ "$arch" != "all" ]; }; then
    rm -f "$DEST/$name"
    soft_fail "el .deb descargado no es válido o no es amd64 (Package=$pkg Architecture=$arch)"
fi
echo "Depends: $(dpkg-deb -f "$DEST/$name" Depends 2>/dev/null)"
echo "VacuumTube OK: paquete $pkg $ver ($arch), $(stat -c %s "$DEST/$name") bytes, sha256 $(sha256sum "$DEST/$name" | cut -d' ' -f1)"
echo "- OK VacuumTube $tag incluido (paquete \`$pkg\` $ver, $arch)" >> "$SUMMARY"
