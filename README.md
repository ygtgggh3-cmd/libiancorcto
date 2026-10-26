# LIBIAN TV

Sistema Live/instalable basado en **Debian 13 "trixie" (amd64)** con XFCE, que arranca directo en una
interfaz de Smart TV (fondo oscuro, tarjetas grandes de colores). Pensado para una PC de ~2008 con 3 GB de RAM.

> **Estado honesto:** este repositorio compila la ISO en GitHub Actions. **Hasta que el flujo termine en verde y
> pruebes la ISO en una máquina virtual o PC, no hay ISO verificada.** Nadie la ha compilado todavía.

## Cómo obtener la ISO (3 pasos)
1. Crea un repositorio **público** en GitHub (en repos privados con plan gratuito, el límite de 500 MB de
   artefactos no deja subir una ISO de ~2 GB) y sube **todo el contenido** de este ZIP (incluida la carpeta `.github`).
2. Pestaña **Actions → Build LIBIAN TV ISO → Run workflow** (también corre solo con cada push a `main`).
3. Al terminar (30–90 min), descarga el artefacto **`libian-tv-iso`** (`libian-tv-amd64.iso` + `SHA256SUMS`).

El flujo **falla si algo está mal** y deja el motivo en el resumen de la ejecución:
| Paso | Qué comprueba |
|---|---|
| Validación rápida | Sintaxis de Python/shell/YAML |
| `scripts/preflight.sh` | Que `deb.debian.org/debian` (trixie, trixie-updates) y `security.debian.org/debian-security` (trixie-security) respondan y sean trixie; que **todos los paquetes existan**. Los opcionales inexistentes se omiten con aviso |
| `lb build` + hook `0900-libian-selfcheck` | Que existan sesión, lanzador, LightDM, Firefox, VLC, Calamares…, que GTK importe y que los scripts compilen |
| `scripts/verify-iso.sh` | ISO 9660 válida, MBR híbrido (USB), arranque BIOS/UEFI, kernel+initrd+squashfs, archivos clave dentro del sistema, repos `trixie`, `trixie-updates`, `trixie-security` configurados |
| `scripts/smoke-test.sh` | **Arranca la ISO en QEMU con 3 GB de RAM**: captura del menú BIOS, espera a que la interfaz escriba `LIBIAN-TV-READY` y ejecuta una **autoprueba** que recorre todas las pantallas, el Wi-Fi, el teclado en pantalla y la barra de cierre (`LIBIAN-TV-AUTOTEST-OK`). Analiza los colores de la captura. Evidencia en el artefacto `libian-tv-smoke-test` |

Si la prueba de arranque falla, la ISO igualmente se publica (es estructuralmente válida) pero el resumen avisa de que **no está confirmado que arranque**.

## Qué trae
- **Sesión propia `libian-tv`**: solo `xfwm4` (sin compositor) + la interfaz. No se ve el escritorio XFCE. Si la interfaz se cierra, se relanza; si falla 3 veces seguidas abre una terminal de rescate.
- **Inicio automático** (`libian-autologin.service`): en el Live entra solo como `user`; en el sistema instalado, con el primer usuario creado. Para desactivarlo: `sudo mkdir -p /etc/libian && sudo touch /etc/libian/no-autologin`.
- **Inicio estilo Smart TV**: barra lateral (Inicio, YouTube, Streaming, USB, Juegos, Aplicaciones, Ajustes), tarjetas grandes de colores, reloj y fecha, estado de red, uso de RAM y CPU en tiempo real, y filas «Mis aplicaciones» y «Juegos» con lo que realmente está instalado. Sin anuncios ni recomendaciones.
- **Wi-Fi integrado en el menú** (sin abrir ventanas): lista de redes con intensidad de señal, conectar, desconectar, redes guardadas y **teclado en pantalla** para la contraseña (también sirve un teclado USB). Usa NetworkManager (`nmcli`).
- **YouTube TV**: se instala **VacuumTube** (envoltorio MIT de la interfaz oficial de YouTube para TV, https://github.com/shy1132/VacuumTube) descargando su `.deb` durante la compilación. YouTube bloquea esa interfaz en navegadores normales, por eso hace falta esta app. Si no se pudiera descargar, el menú usa YouTube web en Firefox y la compilación lo avisa.
- **Cerrar el navegador y las apps**: al abrir Firefox (en pantalla completa) o YouTube TV aparece arriba a la derecha una barra con **✕ Cerrar y volver al menú** (y, en el navegador, Atrás, Adelante, Recargar y zoom). También sirven **Ctrl+Alt+Q**, la tecla *Inicio* de teclados multimedia y `Alt+F4`.
- **Menú**: YouTube · Streaming (Netflix, Prime Video, Disney+, Max, Pluto TV, Twitch, Crunchyroll) · USB · Juegos · Aplicaciones (navegador, archivos, reproductor, terminal, instalador, escritorio XFCE) · Ajustes (Wi-Fi, volumen, pantalla, teclado, reiniciar, apagar). Teclado: flechas/Enter, `Esc` o `Retroceso` = volver.
- **Navegador**: Firefox ESR con perfil propio y uBlock Origin (si está disponible). No existe hoy un navegador «para TV» maduro y empaquetado en Debian (Plasma Bigscreen/Aura no tienen paquetes ni instalador).
- **Bajo consumo de RAM**: zram (lz4), `swappiness` ajustado, sin compositor, servicios innecesarios desactivados (ModemManager, Bluetooth, temporizadores de apt), sin Kodi.
- **Instalador**: Calamares (el de las imágenes live de Debian 13), botón *Aplicaciones → Instalar LIBIAN TV*.
- Idioma `es_PE.UTF-8`, teclado `latam`, zona `America/Lima` (se cambian en `auto/config`).
- Firmware no libre (Wi-Fi Intel/Atheros/Broadcom/Realtek, Radeon, microcódigo) desde `non-free-firmware`.

## Limitaciones conocidas
- Kernel 64 bits: sirve para CPU de 2008 con soporte x86-64 (Core 2, Phenom, etc.), no para Pentium 4 de 32 bits.
- VacuumTube es un proyecto de terceros no oficial; es una app Electron y consume bastante RAM (usa su opción *Low Memory Mode* con `Ctrl+O` y filtra códecs si el video va entrecortado). No incluye aún configuración predefinida.
- Netflix/Prime/Disney+/Max usan DRM (Widevine): Firefox ESR debe poder descargarlo; no está probado aquí. YouTube a 1080p en una CPU de 2008 puede ir justo; usa 480p/720p o `mpv <url>` con `yt-dlp`.
- La instalación en disco está pensada para **BIOS/MBR** (PC de 2008). En UEFI puede requerir ajustes. Prueba el instalador primero en una VM.
- Si instalas a disco, el instalador puede **borrar datos**: revisa el disco elegido.

## Compilar en tu PC (opcional)
```bash
sudo docker run --rm --privileged -v "$PWD":/work -w /work debian:trixie bash scripts/build.sh
```
La ISO queda en `output/libian-tv-amd64.iso`.

## Estructura
`auto/config` (opciones de live-build y repositorios) · `config/package-lists/` (paquetes) · `config/hooks/live/` (configuración y autocomprobación) · `config/includes.chroot/` (lanzador, sesión, LightDM, zram) · `scripts/` (preflight, build, verify, smoke test) · `.github/workflows/build.yml`.
