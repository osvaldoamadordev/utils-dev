#!/usr/bin/env bash
# Ubuntu Server maintenance. No remote operation or unattended mode.
set -u
umask 077

help() {
    printf '%s\n' 'Uso: ubuntu-maintenance.sh [--help | --dry-run]' \
        'Sin opciones: inventario y menú interactivo; cada acción requiere s o y.' \
        '--dry-run: muestra el plan sin ejecutar gestores ni consultar Docker.' \
        'Ejecutar como usuario normal en Ubuntu; sudo solo para APT.'
}
has() { command -v "$1" >/dev/null 2>&1; }
inventory() {
    local tool path resolved
    printf '\nInventario (detección por PATH, sin ejecutar gestores):\n'
    for tool in apt-get brew node npm pnpm corepack bun docker; do
        if has "$tool"; then
            path=$(command -v "$tool")
            resolved=$(readlink -f "$path" 2>/dev/null) || resolved=$path
            printf '  %s: %s\n' "$tool" "$resolved"
        else
            printf '  %s: ausente\n' "$tool"
        fi
    done
}
preview() {
    inventory
    printf '%s\n' \
        'Plan disponible; nada se ejecuta en esta vista:' \
        '  APT: sudo apt-get -o APT::Update::Error-Mode=any update → upgrade (sin -y); clean.' \
        '  Brew: update → upgrade; cleanup --prune=all.' \
        '  npm: sin autoactualización; cache clean --force.' \
        '  pnpm: store prune; Corepack install --global pnpm@latest desde /tmp.' \
        '  Bun independiente: upgrade; pm cache prune solo si lo anuncia su ayuda.' \
        '  Corepack: cache clean opcional; requiere descargas posteriores.' \
        '  Docker local: builder prune --filter until=168h; confirmación nativa.' \
        'Las actualizaciones pueden cambiar versiones mayores; revisa respaldos y ventanas de mantenimiento.'
}
if (( $# > 1 )); then help >&2; exit 2; fi
case "${1:-}" in
    --help|-h) help; exit 0 ;;
    --dry-run) preview; exit 0 ;;
    '') ;;
    *) help >&2; exit 2 ;;
esac
if [[ $(uname -s) != Linux ]] ||
   [[ $(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null) != ubuntu ]]; then
    printf 'Solo Ubuntu Server permite ejecución interactiva. Usa --dry-run.\n' >&2
    exit 2
fi
if [[ $(id -u) == 0 ]]; then
    printf 'No ejecutar todo el script como root; usa tu usuario normal.\n' >&2
    exit 2
fi
LOG=$(mktemp "${TMPDIR:-/tmp}/ubuntu-maintenance.XXXXXXXX") || exit 1
ok=0 failed=0 skipped=0 declined=0
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$LOG"; }
skip() { skipped=$((skipped + 1)); say "OMITIDA: $*"; }
confirm() {
    local reply
    printf '%s [s/N]: ' "$1"
    if ! IFS= read -r reply; then reply=''; fi
    case "$reply" in
        s|S|y|Y) return 0 ;;
        *) declined=$((declined + 1)); say "RECHAZADA: $1"; return 1 ;;
    esac
}
run() {
    local label=$1 status
    shift
    # Keep stdin connected for apt/docker native confirmation. Log only labels,
    # not tool output, env, repository URLs, or authentication material.
    say "EJECUTANDO: $label"
    "$@"
    status=$?
    if (( status == 0 )); then
        ok=$((ok + 1)); say "OK: $label"
    else
        failed=$((failed + 1)); say "FALLÓ: $label (código $status)"
    fi
    return "$status"
}
privileged() {
    if ! has sudo; then skip 'APT requiere sudo'; return 1; fi
    if [[ $2 == update ]]; then
        run "$1" sudo apt-get -o APT::Update::Error-Mode=any update
    else
        run "$1" sudo apt-get "$2"
    fi
}
# Self-update only a recognizably standalone Bun; npm/Node/pnpm ownership is
# often shared between Homebrew, NVM and Corepack, so npm is never self-updated.
standalone_bun() {
    local path
    path=$(readlink -f "$(command -v bun)" 2>/dev/null) || path=$(command -v bun)
    [[ $path == "$HOME/.bun/bin/bun" ]]
}
corepack_manages_pnpm() {
    local path
    has pnpm || return 1
    path=$(readlink -f "$(command -v pnpm)" 2>/dev/null) || return 1
    [[ $path == */corepack/dist/pnpm.js || $path == */corepack/dist/pnpm.cjs ]]
}
corepack_latest() { (cd /tmp && COREPACK_ENABLE_AUTO_PIN=0 corepack install --global pnpm@latest); }
pnpm_prune() { (cd /tmp && COREPACK_ENABLE_AUTO_PIN=0 pnpm store prune); }
updates() {
    if has apt-get; then
        if confirm 'APT: refrescar índices'; then
            if privileged 'APT update' update; then
                if confirm 'APT: instalar actualizaciones (revisar también confirmación de APT)'; then
                    privileged 'APT upgrade' upgrade || :
                fi
            else skip 'APT upgrade: falló update'; fi
        fi
    else skip 'APT ausente'; fi
    if has brew; then
        if confirm 'Brew: actualizar metadatos'; then
            if run 'Brew update' brew update; then
                if confirm 'Brew: actualizar fórmulas instaladas; puede cambiar versiones mayores'; then
                    run 'Brew upgrade' brew upgrade || :
                fi
            else skip 'Brew upgrade: falló update'; fi
        fi
    else skip 'Brew ausente'; fi
    skip 'npm/Node: actualización automática omitida (origen administrado o ambiguo; no se modifica NVM/PATH)'
    if has bun; then
        if standalone_bun; then
            if confirm 'Bun independiente: upgrade; puede cambiar versión mayor'; then
                run 'Bun upgrade' bun upgrade || :
            fi
        else skip 'Bun: origen administrado/ambiguo; actualizar con su gestor de instalación'; fi
    else skip 'Bun ausente'; fi
    if has corepack && corepack_manages_pnpm; then
        if confirm 'Corepack: cambiar pnpm predeterminado a latest, posiblemente otro major; no modifica pins de proyectos'; then
            run 'Corepack pnpm global desde /tmp' corepack_latest || :
        fi
    else skip 'pnpm no pertenece al Corepack activo o Corepack ausente; sin autoactualización'; fi
}
clean_action() {
    local tool=$1 label=$2
    shift 2
    if has "$tool"; then
        if confirm "$label"; then run "$label" "$@" || :; fi
    else skip "$tool ausente"; fi
}
docker_overrides_safe() {
    # Refuse even named context/buildx overrides before invoking Docker at all.
    [[ -z ${DOCKER_HOST:-} && -z ${DOCKER_CONTEXT:-} &&
       -z ${DOCKER_TLS_VERIFY:-} && -z ${DOCKER_CERT_PATH:-} &&
       -z ${BUILDKIT_HOST:-} && -z ${BUILDX_BUILDER:-} &&
       -z ${BUILDX_CONFIG:-} ]]
}
local_docker_endpoint() {
    local context endpoint
    docker_overrides_safe || return 1
    context=$(docker context show 2>/dev/null) || return 1
    [[ -n $context && $context != *$'\n'* ]] || return 1
    endpoint=$(docker context inspect "$context" --format '{{.Endpoints.docker.Host}}' 2>/dev/null) || return 1
    [[ $endpoint == unix:///* && $endpoint != unix:/// &&
       $endpoint != *$'\n'* && $endpoint != *$'\r'* ]] || return 1
    printf '%s' "$endpoint"
}
docker_clean() {
    local endpoint checked
    if ! has docker; then skip 'Docker ausente'; return; fi
    endpoint=$(local_docker_endpoint) || { skip 'Docker: configuración remota o endpoint local no verificable'; return; }
    if confirm 'Docker local: borrar caché de construcción sin uso anterior a 168h; conservar confirmación nativa'; then
        checked=$(local_docker_endpoint) || { skip 'Docker: cambió configuración; limpieza cancelada'; return; }
        if [[ $checked != "$endpoint" ]]; then skip 'Docker: cambió endpoint; limpieza cancelada'; return; fi
        # Explicit host prevents a later context change redirecting the action.
        run 'Docker builder prune local, hasta 168h' docker --host "$endpoint" builder prune --filter until=168h || :
    fi
}
cleanup() {
    if has apt-get; then
        if confirm 'APT: eliminar archivos de paquetes descargados (clean)'; then privileged 'APT clean' clean || :; fi
    else skip 'APT ausente'; fi
    clean_action brew 'Brew: cleanup --prune=all (borra cachés y versiones antiguas)' brew cleanup --prune=all
    clean_action npm 'npm: cache clean --force (requerirá nuevas descargas)' npm cache clean --force
    clean_action pnpm 'pnpm: store prune (objetos no referenciados; próximas instalaciones pueden descargar)' pnpm_prune
    if has bun; then
        # Ask before even querying help, so a fully declined session has no tool calls.
        if confirm 'Bun: detectar soporte de cache prune y limpiar descargas antiguas'; then
            local bun_help
            if bun_help=$(bun pm cache --help 2>/dev/null) && [[ $bun_help == *prune* ]]; then
                run 'Bun pm cache prune' bun pm cache prune || :
            else skip 'Bun: cache prune no soportado; no se borra el almacén completo'; fi
        fi
    else skip 'Bun ausente'; fi
    clean_action corepack 'Corepack: cache clean; elimina gestores descargados y afecta uso sin conexión' corepack cache clean
    docker_clean
}
say "Registro privado de estados: $LOG"
preview
while :; do
    printf '\n[i] inventario [p] vista previa [u] actualizar [c] limpiar [q] salir: '
    IFS= read -r choice || break
    case "$choice" in
        i) inventory ;;
        p) preview ;;
        u) updates ;;
        c) cleanup ;;
        q) break ;;
        *) printf 'Opción no válida.\n' ;;
    esac
done
say "Resumen: correctas=$ok fallidas=$failed omitidas=$skipped rechazadas=$declined"
say "Registro: $LOG (solo estados; salida detallada de herramientas en terminal)"
(( failed == 0 ))
