#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
SSH_USER=""
SSH_HOST=""
SSH_DISPLAY_HOST=""
SSH_PORT=""
PORT_SET=0
PUBLIC_KEY=""
PUBLIC_KEY_SET=0
KEY_NAME=""
KEY_NAME_SET=0
NON_INTERACTIVE=0
ASSUME_YES=0
DRY_RUN=0
TEMP_DIR=""

usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [opciones]

Instala una clave pública en un servidor mediante ssh-copy-id.
Sin parámetros, muestra un menú y solicita los datos faltantes.

Opciones:
  --user USUARIO          Sobrescribe el usuario de ~/.ssh/config
  --host ALIAS             Alias SSH; sin este parámetro puedes elegir uno
  --port PUERTO           Sobrescribe el puerto configurado
  --key ARCHIVO.pub       Clave pública existente
  --key-name NOMBRE       Crea ~/.ssh/NOMBRE como clave Ed25519
  --non-interactive       No solicita datos; falla si falta alguno
  --yes                   Omite la confirmación antes de conectar
  --dry-run               Muestra la operación sin conectarse
  -h, --help              Muestra esta ayuda

--key y --key-name son mutuamente excluyentes. La creación de claves
requiere una terminal para poder solicitar la frase de contraseña.

El menú interactivo obtiene los alias Host de ~/.ssh/config.

Ejemplos:
  $SCRIPT_NAME
  $SCRIPT_NAME --user admin --host 192.0.2.10 --key ~/.ssh/id_ed25519.pub --dry-run
  $SCRIPT_NAME --user admin --host servidor.example --key-name servidor-dev --yes
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

require_value() {
  local option="$1"
  if (($# < 2)) || [[ -z "$2" || "$2" == --* ]]; then
    die "falta el valor de $option"
  fi
}

parse_arguments() {
  while (($#)); do
    case "$1" in
      --user)
        require_value "$1" "${2-}"
        SSH_USER="$2"
        shift 2
        ;;
      --host)
        require_value "$1" "${2-}"
        SSH_HOST="$2"
        shift 2
        ;;
      --port)
        require_value "$1" "${2-}"
        SSH_PORT="$2"
        PORT_SET=1
        shift 2
        ;;
      --key)
        require_value "$1" "${2-}"
        PUBLIC_KEY="$2"
        PUBLIC_KEY_SET=1
        shift 2
        ;;
      --key-name)
        require_value "$1" "${2-}"
        KEY_NAME="$2"
        KEY_NAME_SET=1
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --yes)
        ASSUME_YES=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        (($# == 0)) || die "no se aceptan argumentos posicionales"
        ;;
      *)
        die "opción desconocida: $1 (usa --help)"
        ;;
    esac
  done
}

can_prompt() {
  ((NON_INTERACTIVE == 0)) && [[ -t 0 && -t 1 ]]
}

prompt_value() {
  local variable_name="$1"
  local prompt_text="$2"
  local answer
  if ! read -r -p "$prompt_text" answer; then
    die "no se pudo leer la entrada interactiva"
  fi
  printf -v "$variable_name" '%s' "$answer"
}

expand_home() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

ssh_config_hosts() {
  local config_file="$HOME/.ssh/config"
  local line
  local directive
  local patterns
  local pattern
  local existing
  local -a pattern_list=()
  local hosts=()

  [[ -f "$config_file" ]] || die "no existe $config_file; configura alias Host o indica --host"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    read -r directive patterns <<< "$line"
    [[ "${directive,,}" == "host" ]] || continue
    read -r -a pattern_list <<< "$patterns"
    for pattern in "${pattern_list[@]}"; do
      case "$pattern" in
        -*|*'*'*|*'?'*|*'['*|*']'*) continue ;;
      esac
      [[ "$pattern" =~ ^[A-Za-z0-9._:%-]+$ && "$pattern" != -* ]] || continue
      for existing in "${hosts[@]}"; do
        [[ "$existing" == "$pattern" ]] && continue 2
      done
      hosts+=("$pattern")
    done
  done < "$config_file"

  if ((${#hosts[@]} == 0)); then
    die "no se encontraron alias Host utilizables en $config_file"
  fi
  printf '%s\0' "${hosts[@]}"
}

choose_ssh_host() {
  local hosts=()
  local host
  local choice
  local index

  [[ -f "$HOME/.ssh/config" ]] \
    || die "no existe $HOME/.ssh/config; configura alias Host o indica --host"
  while IFS= read -r -d '' host; do
    hosts+=("$host")
  done < <(ssh_config_hosts)
  ((${#hosts[@]})) || die "no se encontraron alias Host utilizables en $HOME/.ssh/config"

  printf '\nServidores de ~/.ssh/config:\n'
  for index in "${!hosts[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${hosts[$index]}"
  done

  while true; do
    prompt_value choice "Selecciona un servidor: "
    for index in "${!hosts[@]}"; do
      if [[ "$choice" == "$((index + 1))" ]]; then
        SSH_HOST="${hosts[$index]}"
        return
      fi
    done
    printf 'Opción inválida. Elige un número del menú.\n' >&2
  done
}

resolve_ssh_destination() {
  local resolved
  local resolved_user
  local resolved_host
  local resolved_port

  [[ "$SSH_HOST" =~ ^[A-Za-z0-9._:%-]+$ && "$SSH_HOST" != -* ]] \
    || die "alias SSH inválido; no uses espacios, @ ni opciones SSH"
  command -v ssh >/dev/null 2>&1 || die "no se encontró ssh"
  if ! resolved="$(ssh -G "$SSH_HOST" 2>&1)"; then
    die "no se pudo resolver el alias SSH '$SSH_HOST': $resolved"
  fi
  resolved_user="$(awk '$1 == "user" { print $2; exit }' <<< "$resolved")"
  resolved_host="$(awk '$1 == "hostname" { print $2; exit }' <<< "$resolved")"
  resolved_port="$(awk '$1 == "port" { print $2; exit }' <<< "$resolved")"

  SSH_USER="${SSH_USER:-$resolved_user}"
  SSH_DISPLAY_HOST="$resolved_host"
  if ((PORT_SET == 0)); then
    SSH_PORT="$resolved_port"
  fi
}

key_fingerprints() {
  ssh-keygen -lf "$1" 2>/dev/null |
    awk '{printf "  %s %s\n", $2, $NF}'
}

is_valid_public_key() {
  [[ "$1" == *.pub && -f "$1" ]] && ssh-keygen -lf "$1" >/dev/null 2>&1
}

valid_existing_keys() {
  local candidate
  local had_nullglob=0
  local candidates=()

  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  for candidate in "$HOME"/.ssh/*.pub; do
    if is_valid_public_key "$candidate"; then
      candidates+=("$candidate")
    fi
  done
  ((had_nullglob)) || shopt -u nullglob

  if ((${#candidates[@]})); then
    printf '%s\0' "${candidates[@]}"
  fi
}

generate_key() {
  [[ -n "${HOME:-}" ]] || die "no se pudo determinar HOME"
  local ssh_directory="$HOME/.ssh"
  local private_path="$ssh_directory/$KEY_NAME"
  local public_path="$private_path.pub"
  local staged_private
  local staged_public

  [[ "$KEY_NAME" =~ ^[A-Za-z0-9._-]+$ && "$KEY_NAME" != "." && "$KEY_NAME" != ".." && "$KEY_NAME" != *.pub ]] \
    || die "nombre de clave inválido; usa letras, números, punto, guion o guion bajo, sin extensión .pub"
  [[ ! -e "$private_path" && ! -L "$private_path" && ! -e "$public_path" && ! -L "$public_path" ]] \
    || die "no se sobrescribirá una clave existente: $private_path o $public_path"
  [[ -t 0 && -t 1 ]] || die "crear una clave requiere una terminal para solicitar su frase de contraseña"

  umask 077
  mkdir -p -- "$ssh_directory"
  TEMP_DIR="$(mktemp -d "$ssh_directory/.install-ssh-key.XXXXXX")"
  chmod 700 "$TEMP_DIR"
  staged_private="$TEMP_DIR/$KEY_NAME"
  staged_public="$staged_private.pub"

  printf 'Creando una clave Ed25519 protegida por la frase de contraseña que elijas...\n'
  ssh-keygen -q -t ed25519 -f "$staged_private" -C "$KEY_NAME" \
    || die "no se pudo crear la clave Ed25519"
  [[ -f "$staged_private" && -f "$staged_public" ]] \
    || die "ssh-keygen no generó el par de claves esperado"

  if ! ln -- "$staged_private" "$private_path"; then
    die "no se sobrescribirá una clave existente: $private_path"
  fi
  if ! ln -- "$staged_public" "$public_path"; then
    if [[ "$private_path" -ef "$staged_private" ]]; then
      rm -f -- "$private_path"
    fi
    die "no se sobrescribirá una clave existente: $public_path"
  fi
  PUBLIC_KEY="$public_path"
  printf 'Clave privada creada en %q\n' "$private_path"
}

choose_key() {
  local candidates=()
  local candidate
  local choice
  local index
  local create_index

  while IFS= read -r -d '' candidate; do
    candidates+=("$candidate")
  done < <(valid_existing_keys)

  printf '\nClaves públicas válidas encontradas:\n'
  for index in "${!candidates[@]}"; do
    candidate="${candidates[$index]}"
    printf '  %d) Usar %q\n' "$((index + 1))" "$candidate"
    key_fingerprints "$candidate"
  done
  create_index=$((${#candidates[@]} + 1))
  printf '  %d) Crear una clave Ed25519 nueva\n' "$create_index"

  while true; do
    prompt_value choice "Selecciona una opción: "
    for index in "${!candidates[@]}"; do
      if [[ "$choice" == "$((index + 1))" ]]; then
        PUBLIC_KEY="${candidates[$index]}"
        return
      fi
    done
    if [[ "$choice" == "$create_index" ]]; then
      prompt_value KEY_NAME "Nombre de la nueva clave [id_ed25519]: "
      KEY_NAME="${KEY_NAME:-id_ed25519}"
      generate_key
      return
    fi
    printf 'Opción inválida. Elige un número del menú.\n' >&2
  done
}

validate_destination() {
  [[ "$SSH_USER" =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]] \
    || die "usuario SSH inválido"
  [[ "$SSH_HOST" =~ ^[A-Za-z0-9._:%-]+$ && "$SSH_HOST" != -* ]] \
    || die "host inválido; no uses espacios, @ ni opciones SSH"
  [[ "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] || die "puerto inválido: debe estar entre 1 y 65535"
  local numeric_port=$((10#$SSH_PORT))
  ((numeric_port >= 1 && numeric_port <= 65535)) \
    || die "puerto inválido: debe estar entre 1 y 65535"
  SSH_PORT="$numeric_port"
  [[ "$SSH_DISPLAY_HOST" =~ ^[A-Za-z0-9._:%-]+$ && "$SSH_DISPLAY_HOST" != -* ]] \
    || die "el HostName efectivo de SSH no es válido"
}

main() {
  local destination
  local fingerprint
  local answer

  parse_arguments "$@"

  command -v ssh-keygen >/dev/null 2>&1 || die "no se encontró ssh-keygen"
  [[ -n "${HOME:-}" ]] || die "no se pudo determinar HOME"
  ((PUBLIC_KEY_SET == 0 || KEY_NAME_SET == 0)) \
    || die "usa --key o --key-name, no ambos"

  if [[ -z "$SSH_HOST" ]]; then
    if can_prompt; then
      choose_ssh_host
    else
      die "falta el host; indica --host o selecciona uno desde una terminal. Usa --help"
    fi
  fi

  resolve_ssh_destination
  validate_destination

  if ((PUBLIC_KEY_SET)); then
    [[ -n "${HOME:-}" ]] || die "no se pudo determinar HOME"
    PUBLIC_KEY="$(expand_home "$PUBLIC_KEY")"
  elif ((KEY_NAME_SET)); then
    generate_key
  elif can_prompt; then
    choose_key
  else
    die "falta la clave pública; indica --key ARCHIVO.pub o selecciona una clave en modo interactivo"
  fi

  is_valid_public_key "$PUBLIC_KEY" \
    || die "la clave debe ser un archivo .pub válido reconocido por ssh-keygen"
  fingerprint="$(key_fingerprints "$PUBLIC_KEY")"
  [[ -n "$fingerprint" ]] || die "ssh-keygen no pudo obtener la huella de la clave"

  destination="$SSH_USER@$SSH_HOST"
  printf '\nAlias SSH: %s\n' "$SSH_HOST"
  printf 'Destino SSH: %s@%s (puerto %s)\n' "$SSH_USER" "$SSH_DISPLAY_HOST" "$SSH_PORT"
  printf 'Huella de la clave pública:\n%s\n' "$fingerprint"
  if ((PORT_SET)); then
    printf 'Operación: ssh-copy-id -i %q -p %q %q\n' "$PUBLIC_KEY" "$SSH_PORT" "$destination"
  else
    printf 'Operación: ssh-copy-id -i %q %q\n' "$PUBLIC_KEY" "$destination"
  fi

  if ((DRY_RUN)); then
    printf 'Simulación: no se realizó ninguna conexión.\n'
    return 0
  fi

  command -v ssh-copy-id >/dev/null 2>&1 || die "no se encontró ssh-copy-id"
  if ((ASSUME_YES == 0)); then
    ((NON_INTERACTIVE == 0)) && [[ -t 0 && -t 1 ]] \
      || die "la confirmación requiere una terminal; añade --yes para continuar sin ella"
    if ! read -r -p "¿Instalar esta clave en el servidor? [s/N] " answer; then
      die "no se pudo leer la confirmación"
    fi
    case "$answer" in
      s|S|si|Si|SI|sí|Sí|SÍ|y|Y|yes|YES) ;;
      *) printf 'Operación cancelada.\n'; return 0 ;;
    esac
  fi

  if ((PORT_SET)); then
    ssh-copy-id -i "$PUBLIC_KEY" -p "$SSH_PORT" "$destination"
  else
    ssh-copy-id -i "$PUBLIC_KEY" "$destination"
  fi
}

main "$@"
