#!/usr/bin/env bash

# =============================================================================
# wt — Crea un worktree en worktrees/<feature> del proyecto actual
#
# Uso:
#   wt <feature-name> [base-branch]
#
# Ejemplos:
#   wt 001-crm-prospectos          # usa la rama actual como base
#   wt 001-crm-prospectos develop
#
# Copia los archivos .env y .env.* del repositorio al nuevo worktree.
# =============================================================================

set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  BOLD=''
  RESET=''
fi

info()    { printf '%b\n' "${BLUE}ℹ${RESET}  $*"; }
success() { printf '%b\n' "${GREEN}✓${RESET}  $*"; }
warn()    { printf '%b\n' "${YELLOW}⚠${RESET}  $*"; }
error()   { printf '%b\n' "${RED}✗${RESET}  $*" >&2; }
step()    { printf '\n%b\n' "${BOLD}${CYAN}▶ $*${RESET}"; }
die()     { error "$*"; exit 1; }

usage() {
  printf '%b\n' \
    "${BOLD}Uso:${RESET}     wt <feature-name> [base-branch]" \
    "${BOLD}Ejemplo:${RESET} wt 001-crm-prospectos          # base: rama actual" \
    "${BOLD}Ejemplo:${RESET} wt 001-crm-prospectos develop"
}

# ─── Validaciones ─────────────────────────────────────────────────────────────
validate_args() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    error "Debes indicar la feature y, opcionalmente, la rama base."
    printf '\n'
    usage
    printf '\n'
    exit 2
  fi

  [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] \
    || die "El nombre debe comenzar con una letra o número y solo puede contener letras, números, - y _."

  git check-ref-format --branch "$1" >/dev/null 2>&1 \
    || die "El nombre de branch no es válido: $1"
}

validate_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "No estás dentro de un repositorio Git."
}

resolve_repo_context() {
  REPO_ROOT=$(git rev-parse --show-toplevel)

  local git_dir_raw
  local common_dir_raw

  git_dir_raw=$(git -C "$REPO_ROOT" rev-parse --git-dir)
  common_dir_raw=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)

  GIT_DIR=$(cd "$REPO_ROOT" && cd "$git_dir_raw" && pwd -P)
  GIT_COMMON_DIR=$(cd "$REPO_ROOT" && cd "$common_dir_raw" && pwd -P)
}

validate_not_already_worktree() {
  [[ $GIT_DIR == "$GIT_COMMON_DIR" ]] \
    || die "Ya estás dentro de un worktree. Ejecuta wt desde el repositorio principal."
}

# ─── Configuración ────────────────────────────────────────────────────────────
resolve_config() {
  FEATURE_NAME=$1
  BRANCH_NAME=$FEATURE_NAME

  if [[ $# -eq 2 ]]; then
    BASE_BRANCH=$2
  elif ! BASE_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD); then
    die "El repositorio está en detached HEAD. Indica explícitamente una rama base:
  wt ${FEATURE_NAME} <base-branch>"
  fi

  WORKTREES_DIR="${REPO_ROOT}/worktrees"
  WORKTREE_DIR="${WORKTREES_DIR}/${FEATURE_NAME}"
}

resolve_base_ref() {
  if git -C "$REPO_ROOT" rev-parse --verify "${BASE_BRANCH}^{commit}" >/dev/null 2>&1; then
    BASE_REF=$BASE_BRANCH
  elif git -C "$REPO_ROOT" rev-parse --verify "origin/${BASE_BRANCH}^{commit}" >/dev/null 2>&1; then
    BASE_REF="origin/${BASE_BRANCH}"
  else
    die "La rama base '${BASE_BRANCH}' no existe localmente ni en origin."
  fi
}

# ─── Directorio y exclusión de Git ────────────────────────────────────────────
ensure_worktrees_dir() {
  if [[ ! -d $WORKTREES_DIR ]]; then
    mkdir -p "$WORKTREES_DIR"
    info "Directorio worktrees/ creado"
  fi
}

ensure_worktrees_ignored() {
  local probe="${WORKTREES_DIR}/.wt-ignore-check"

  if ! git -C "$REPO_ROOT" check-ignore -q "$probe" 2>/dev/null; then
    local exclude_file="${GIT_COMMON_DIR}/info/exclude"
    mkdir -p "$(dirname "$exclude_file")"
    printf '\n/worktrees/\n' >> "$exclude_file"
    info "worktrees/ agregado a .git/info/exclude"
  fi
}

validate_destination() {
  if [[ -e $WORKTREE_DIR || -L $WORKTREE_DIR ]]; then
    die "El destino ya existe: $WORKTREE_DIR"
  fi

  local registered_path=''
  local record

  while IFS= read -r -d '' record; do
    if [[ $record == worktree\ * ]]; then
      registered_path=${record#worktree }
      if [[ $registered_path == "$WORKTREE_DIR" ]]; then
        die "El destino todavía está registrado en Git: $WORKTREE_DIR

Ejecuta 'git worktree prune' si el directorio ya no existe."
      fi
    fi
  done < <(git -C "$REPO_ROOT" worktree list --porcelain -z)
}

# ─── Verificar disponibilidad del branch ─────────────────────────────────────
find_branch_worktree() {
  local current_path=''
  local record

  while IFS= read -r -d '' record; do
    case $record in
      worktree\ *)
        current_path=${record#worktree }
        ;;
      "branch refs/heads/${BRANCH_NAME}")
        printf '%s\n' "$current_path"
        return 0
        ;;
    esac
  done < <(git -C "$REPO_ROOT" worktree list --porcelain -z)

  return 1
}

verify_branch_available() {
  step "Verificando branch"

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    local used_by=''
    used_by=$(find_branch_worktree || true)

    if [[ -n $used_by ]]; then
      if [[ $used_by == "$REPO_ROOT" ]]; then
        die "El branch '${BRANCH_NAME}' está activo en el repositorio principal.

Cámbiate primero a otra rama y vuelve a ejecutar:
  wt ${FEATURE_NAME} ${BASE_BRANCH}"
      fi

      die "El branch '${BRANCH_NAME}' ya está en uso en:
  ${used_by}"
    fi

    success "Branch local encontrado → ${BRANCH_NAME}"
  elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/${BRANCH_NAME}"; then
    success "Branch remoto encontrado → origin/${BRANCH_NAME}"
  else
    info "Branch '${BRANCH_NAME}' no existe — se creará desde ${BASE_REF}"
  fi
}

# ─── Crear worktree ───────────────────────────────────────────────────────────
create_worktree() {
  step "Creando worktree"
  info "Directorio → worktrees/${FEATURE_NAME}"
  info "Branch     → ${BRANCH_NAME}"

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    git -C "$REPO_ROOT" worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
  elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/${BRANCH_NAME}"; then
    git -C "$REPO_ROOT" worktree add --track -b "$BRANCH_NAME" \
      "$WORKTREE_DIR" "origin/${BRANCH_NAME}"
  else
    git -C "$REPO_ROOT" worktree add -b "$BRANCH_NAME" \
      "$WORKTREE_DIR" "$BASE_REF"
  fi

  success "Worktree listo"
}

# ─── Copiar archivos .env ─────────────────────────────────────────────────────
copy_env_files() {
  step "Copiando archivos de entorno"

  local source_file
  local relative_path
  local target_file
  local copied=0
  local skipped=0

  while IFS= read -r -d '' source_file; do
    relative_path=${source_file#"${REPO_ROOT}/"}
    target_file="${WORKTREE_DIR}/${relative_path}"

    if [[ -L $source_file ]]; then
      warn "Se omitió el enlace simbólico → ${relative_path}"
      skipped=$((skipped + 1))
      continue
    fi

    # Un archivo con seguimiento ya fue creado por Git; no debe sobrescribirse.
    if [[ -e $target_file || -L $target_file ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    mkdir -p "$(dirname "$target_file")"
    cp -p "$source_file" "$target_file"
    chmod 600 "$target_file"
    copied=$((copied + 1))
    success "Copiado → ${relative_path}"
  done < <(
    find "$REPO_ROOT" \
      \( -name .git -o -path "$WORKTREES_DIR" -o -name node_modules \) -prune -o \
      -type f \( -name .env -o -name '.env.*' \) -print0
  )

  if [[ $copied -eq 0 ]]; then
    info "No había archivos .env locales pendientes de copiar"
  else
    success "Archivos .env copiados → ${copied}"
  fi

  if [[ $skipped -gt 0 ]]; then
    info "Archivos existentes o enlaces omitidos → ${skipped}"
  fi
}

# ─── Advertencias del checkout principal ─────────────────────────────────────
warn_if_dirty() {
  if [[ -n $(git -C "$REPO_ROOT" status --porcelain --untracked-files=no) ]]; then
    warn "El repositorio principal tiene cambios sin commit."
    warn "Esos cambios no se copiarán; únicamente se copiarán los archivos .env."
  fi
}

# ─── Resumen ──────────────────────────────────────────────────────────────────
print_summary() {
  printf '\n%b\n' "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗"
  printf '%b\n'   "║         ✅  Worktree listo                       ║"
  printf '%b\n'   "╚══════════════════════════════════════════════════╝${RESET}"
  printf '\n'
  printf '  %b %s\n' "${BOLD}Feature:${RESET}   " "$FEATURE_NAME"
  printf '  %b %s\n' "${BOLD}Branch:${RESET}    " "$BRANCH_NAME"
  printf '  %b %s\n' "${BOLD}Base:${RESET}      " "$BASE_REF"
  printf '  %b %s\n' "${BOLD}Directorio:${RESET}" "$WORKTREE_DIR"
  printf '\n'
  printf '  %bcd %q%b\n' "$CYAN" "$WORKTREE_DIR" "$RESET"
  printf '  %bclaude%b\n' "$CYAN" "$RESET"
  printf '\n'
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  command -v git >/dev/null 2>&1 || die "Git no está instalado."

  if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
  fi

  validate_args "$@"
  validate_git_repo
  resolve_repo_context
  validate_not_already_worktree
  resolve_config "$@"
  resolve_base_ref

  ensure_worktrees_dir
  ensure_worktrees_ignored
  validate_destination
  verify_branch_available
  warn_if_dirty
  create_worktree
  copy_env_files
  print_summary
}

main "$@"
