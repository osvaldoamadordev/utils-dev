#!/usr/bin/env bash

set -Eeuo pipefail

VERSION='2026-10-30.1'

mostrar_ayuda() {
  cat <<EOF
Uso: ${0##*/} [DIRECTORIO_ORIGEN] [DIRECTORIO_DESTINO]

Sin argumentos, respalda desde \$HOME hacia \$HOME/backups-manuales.
Si se proporciona solo el origen, el destino predeterminado sigue siendo
\$HOME/backups-manuales.

El respaldo incluye las rutas configuradas en el script. Se omiten cachés,
dependencias instaladas y archivos regenerables conocidos. --one-file-system
omite montajes de otros sistemas de archivos. Los archivos que cambien durante
la ejecución pueden quedar en un estado inconsistente; cierre las aplicaciones
que los modifican antes de respaldar.

La restauración de propietarios requiere privilegios de administrador.
EOF
}

if (( $# == 1 )) && [[ "$1" == '--help' || "$1" == '-h' ]]; then
  mostrar_ayuda
  exit 0
fi

if (( $# > 2 )); then
  printf 'Error: se aceptan como máximo dos argumentos.\n\n' >&2
  mostrar_ayuda >&2
  exit 2
fi

if (( $# > 0 )) && [[ "$1" == -* ]]; then
  printf 'Error: opción desconocida: %s\n\n' "$1" >&2
  mostrar_ayuda >&2
  exit 2
fi

umask 077

ORIGEN="${1:-$HOME}"
DESTINO="${2:-$HOME/backups-manuales}"
MARCA_TIEMPO="$(date '+%Y%m%d_%H%M%S')"
HOST_ORIGINAL="$(hostname -s)"
HOST_SEGURO="$(printf '%s' "$HOST_ORIGINAL" | tr -cs '[:alnum:]._-' '_')"
ARCHIVO="bk_pc-work_${MARCA_TIEMPO}_${HOST_SEGURO}.tgz"

if [[ ! -d "$ORIGEN" ]]; then
  printf 'Error: el directorio de origen no existe: %s\n' "$ORIGEN" >&2
  exit 1
fi

mkdir -p -- "$DESTINO"
ORIGEN="$(cd -- "$ORIGEN" && pwd -P)"
DESTINO="$(cd -- "$DESTINO" && pwd -P)"
SALIDA="$DESTINO/$ARCHIVO"
TEMPORAL="$DESTINO/.${ARCHIVO}.parcial"

# Seguridad: este script nunca elimina archivos y tampoco sobrescribe respaldos.
# Si una ejecución se interrumpe, el archivo .parcial se conserva para revisión.
if [[ -e "$SALIDA" || -e "$TEMPORAL" ]]; then
  printf 'Error: ya existe el archivo de salida o su archivo parcial:\n  %s\n  %s\n' \
    "$SALIDA" "$TEMPORAL" >&2
  exit 1
fi

# Rutas solicitadas. Las inexistentes se informan y se omiten.
RUTAS_SOLICITADAS=(
  '._Caranty'
  '.agents'
  '.bash_myalias'
  '.claude'
  '.cloudflared'
  '.codegraph'
  '.codex'
  '.config'
  '.gemini'
  '.github'
  '.oh-my-zsh'
  '.opencode'
  '.rest-client'
  '.ssh'
  '.tmux'
  '.zshrc'
  'Caranty'
  'Projects'
  'install-tmux'
  'technical-tests'
  'scripts-dev'
)

RUTAS_EXISTENTES=()
for ruta in "${RUTAS_SOLICITADAS[@]}"; do
  if [[ -e "$ORIGEN/$ruta" || -L "$ORIGEN/$ruta" ]]; then
    RUTAS_EXISTENTES+=("$ruta")
  else
    printf 'Aviso: no existe; se omite: %s/%s\n' "$ORIGEN" "$ruta" >&2
  fi
done

if (( ${#RUTAS_EXISTENTES[@]} == 0 )); then
  printf 'Error: ninguna de las rutas solicitadas existe en %s\n' "$ORIGEN" >&2
  exit 1
fi

# Dependencias, cachés, entornos y resultados regenerables.
EXCLUSIONES=(
  '--exclude=node_modules'
  '--exclude=vendor'
  '--exclude=.venv'
  '--exclude=venv'
  '--exclude=__pycache__'
  '--exclude=.pytest_cache'
  '--exclude=.mypy_cache'
  '--exclude=.ruff_cache'
  '--exclude=.tox'
  '--exclude=.nox'
  '--exclude=.gradle'
  '--exclude=.cache'
  '--exclude=.azurite'
  '--exclude=.parcel-cache'
  '--exclude=.turbo'
  '--exclude=.next'
  '--exclude=.nuxt'
  '--exclude=.svelte-kit'
  '--exclude=coverage'
  '--exclude=.nyc_output'
  '--exclude=dist'
  '--exclude=build'
  '--exclude=out'
  '--exclude=target'
  '--exclude=bin'
  '--exclude=obj'
  '--exclude=Pods'
  '--exclude=DerivedData'
  '--exclude=*.pyc'
  '--exclude=*.pyo'
  '--exclude=*.class'
  '--exclude=*.o'
  '--exclude=*.obj'
  '--exclude=*.sock'
  '--exclude=*.socket'
  '--exclude=*.pid'
  '--exclude=*.deb'
  '--exclude=*.rpm'
  '--exclude=*.AppImage'
  '--exclude=*.iso'
  '--exclude=*.dmg'
  '--exclude=*.pkg'
  '--exclude=Projects.tgz'
  '--exclude=bk_pc-work_*.tgz'
  '--exclude=bk_*.tgz'
  '--exclude=respaldo_*.tgz'
  "--exclude=$ARCHIVO"
  "--exclude=.${ARCHIVO}.parcial"
  '--exclude=*.log'
  '--exclude=.DS_Store'
)

printf 'Script de respaldo: versión %s\n' "$VERSION"
printf 'Creando respaldo de %s\n' "$ORIGEN"
printf 'Destino: %s\n' "$SALIDA"
printf 'Aviso: --one-file-system omitirá montajes de otros sistemas de archivos.\n' >&2
printf 'Aviso: cierre aplicaciones que modifiquen los archivos incluidos durante el respaldo.\n' >&2

tar \
  --create \
  --gzip \
  --file "$TEMPORAL" \
  --directory "$ORIGEN" \
  --one-file-system \
  --atime-preserve=system \
  --numeric-owner \
  --acls \
  --xattrs \
  "${EXCLUSIONES[@]}" \
  -- \
  "${RUTAS_EXISTENTES[@]}"

# Verifica que gzip y la tabla de contenidos del tar sean legibles.
gzip --test "$TEMPORAL"
tar --list --gzip --file "$TEMPORAL" >/dev/null

mv --no-clobber -- "$TEMPORAL" "$SALIDA"
if [[ -e "$TEMPORAL" ]]; then
  printf 'Error: apareció un archivo con el nombre de salida; no se sobrescribió.\n' >&2
  printf 'El respaldo parcial se conservó en: %s\n' "$TEMPORAL" >&2
  exit 1
fi
chmod 600 "$SALIDA"

printf '\nRespaldo completado y verificado:\n%s\n' "$SALIDA"
du -h -- "$SALIDA"
printf '\nPara revisar su contenido:\n  tar -tzf %q | less\n' "$SALIDA"
printf 'Para restaurarlo conservando propietarios, ACL y atributos extendidos:\n'
printf '  sudo mkdir -p /ruta/restauracion && sudo tar --extract --gzip --file %q --directory /ruta/restauracion --same-owner --acls --xattrs\n' "$SALIDA"
