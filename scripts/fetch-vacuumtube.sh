#!/usr/bin/env bash
# Descarga el .deb de VacuumTube (envoltorio de YouTube Leanback/TV, MIT,
# https://github.com/shy1132/VacuumTube) a config/packages.chroot/. live-build lo instala
# en la ISO. Intenta, en orden:
#   1) enlaces directos «latest/download/…»
#   2) la API de GitHub (última versión y, si no, las 15 últimas incluidas pre-versiones)
# Si todo falla, la compilación continúa SIN VacuumTube (el menú usa Firefox para YouTube) y
# lo avisa con el motivo; con REQUIRE_VACUUMTUBE=1 falla.
set -uo pipefail
cd "$(dirname "$0")/.."
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
DEST=config/packages.chroot
REPO=shy1132/VacuumTube
mkdir -p "$DEST"
rm -f "$DEST"/*.deb
TMP=$(mktemp -d)
reasons=()

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

validate() {  # $1 = archivo .deb ; devuelve 0 si es un paquete amd64 válido
    local arch pkg
    arch=$(dpkg-deb -f "$1" Architecture 2>/dev/null || true)
    pkg=$(dpkg-deb -f "$1" Package 2>/dev/null || true)
    [ -n "$pkg" ] && { [ "$arch" = "amd64" ] || [ "$arch" = "all" ]; }
}

accept() {  # $1 = archivo, $2 = origen
    local pkg ver
    pkg=$(dpkg-deb -f "$1" Package); ver=$(dpkg-deb -f "$1" Version)
    mv "$1" "$DEST/${pkg}_${ver}_amd64.deb"
    echo "Depends: $(dpkg-deb -f "$DEST/${pkg}_${ver}_amd64.deb" Depends 2>/dev/null)"
    echo "VacuumTube OK: $pkg $ver desde $2 ($(stat -c %s "$DEST/${pkg}_${ver}_amd64.deb") bytes, sha256 $(sha256sum "$DEST/${pkg}_${ver}_amd64.deb" | cut -d' ' -f1))"
    echo "- OK VacuumTube incluido: paquete \`$pkg\` $ver ($2)" >> "$SUMMARY"
    exit 0
}

download() {  # $1 = url ; deja el archivo en $TMP/dl.deb
    local code
    code=$(curl -sSL --retry 3 --max-time 600 -o "$TMP/dl.deb" -w '%{http_code}' "$1" 2>"$TMP/err") || true
    if [ "$code" = "200" ] && validate "$TMP/dl.deb"; then return 0; fi
    reasons+=("$1 -> HTTP $code $(head -c 120 "$TMP/err" | tr '\n' ' ')")
    return 1
}

# 1) enlaces directos
for name in VacuumTube-amd64.deb VacuumTube-x86_64.deb vacuumtube_amd64.deb; do
    url="https://github.com/$REPO/releases/latest/download/$name"
    echo "Probando $url"
    if download "$url"; then accept "$TMP/dl.deb" "$url"; fi
done

# 2) API de GitHub
for api in "https://api.github.com/repos/$REPO/releases/latest" \
           "https://api.github.com/repos/$REPO/releases?per_page=15"; do
    code=$(curl -sS --retry 3 --max-time 60 "${auth[@]}" -H 'Accept: application/vnd.github+json' \
           -o "$TMP/api.json" -w '%{http_code}' "$api" 2>"$TMP/err") || true
    if [ "$code" != "200" ]; then
        reasons+=("$api -> HTTP $code $(head -c 150 "$TMP/api.json" "$TMP/err" 2>/dev/null | tr '\n' ' ')")
        continue
    fi
    url=$(python3 - "$TMP/api.json" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
rels = d if isinstance(d, list) else [d]
for rel in rels:
    debs = [a for a in rel.get("assets", []) if a["name"].lower().endswith(".deb")]
    pref = [a for a in debs if re.search(r"(amd64|x86_64|x64)", a["name"], re.I)] or debs
    if pref:
        print(pref[0]["browser_download_url"])
        break
PY
) || true
    if [ -z "$url" ]; then
        reasons+=("$api -> sin paquete .deb en las versiones")
        continue
    fi
    echo "Probando (API) $url"
    if download "$url"; then accept "$TMP/dl.deb" "$url"; fi
done

msg="${reasons[*]}"
echo "::warning::VacuumTube NO se instaló. Intentos: ${msg:0:900}"
echo "- AVISO VacuumTube NO instalado. Intentos: \`${msg:0:900}\`" >> "$SUMMARY"
[ "${REQUIRE_VACUUMTUBE:-0}" = "1" ] && exit 1
exit 0
