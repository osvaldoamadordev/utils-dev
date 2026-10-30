#!/usr/bin/env bash
set -Eeuo pipefail

SSH_PORT="${1:-22}"
CONFIRM_SSH_HARDENING="${CONFIRM_SSH_HARDENING:-NO}"
LOCK_FILE="/run/lock/harden-ubuntu26.lock"

if [[ "$EUID" -ne 0 ]]; then
  echo "Ejecutá el script con sudo."
  exit 1
fi

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
  echo "Puerto SSH inválido: $SSH_PORT"
  exit 1
fi

exec 9>"$LOCK_FILE"
flock -n 9 || {
  echo "Ya hay otra ejecución en curso."
  exit 1
}

WRITE_CHANGED=0

write_if_changed() {
  local target="$1"
  local mode="$2"
  local temp
  local backup="${target}.bak"

  WRITE_CHANGED=0
  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" ]]; then
    echo "ERROR: $target es un enlace simbólico."
    exit 1
  fi

  temp="$(mktemp "$(dirname "$target")/.harden.XXXXXX")"

  cat > "$temp"
  chown root:root "$temp"
  chmod "$mode" "$temp"

  if [[ -f "$target" ]] && cmp -s "$temp" "$target"; then
    rm -f "$temp"
    echo "OMITIDO: $target ya está configurado."
    return 0
  fi

  if [[ -f "$target" && ! -e "$backup" ]]; then
    cp -a "$target" "$backup"
    chown root:root "$backup"
    echo "RESPALDO: $backup"
  fi

  mv -f "$temp" "$target"
  WRITE_CHANGED=1
  echo "ACTUALIZADO: $target"
}

ensure_ufw_ssh() {
  if [[ "$SSH_PORT" == "22" ]]; then
    if ufw status | grep -q "OpenSSH"; then
      echo "OMITIDO: regla OpenSSH ya existe."
    else
      ufw allow OpenSSH
    fi
  else
    if ufw status | grep -qE "^${SSH_PORT}/tcp"; then
      echo "OMITIDO: regla SSH ${SSH_PORT}/tcp ya existe."
    else
      ufw allow "${SSH_PORT}/tcp"
    fi
  fi
}

apt-get update
apt-get install -y \
  openssh-server \
  ufw \
  fail2ban \
  unattended-upgrades

ufw default deny incoming
ufw default allow outgoing
ensure_ufw_ssh

if ! ufw status | grep -q "^Status: active"; then
  ufw --force enable
else
  echo "OMITIDO: UFW ya está activo."
fi

write_if_changed /etc/fail2ban/jail.d/99-sshd-hardening.local 0644 <<EOF
[DEFAULT]
banaction = ufw
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${SSH_PORT}
backend = systemd
EOF

if (( WRITE_CHANGED )); then
  fail2ban-client -t
  systemctl restart fail2ban
else
  echo "OMITIDO: configuración Fail2ban sin cambios."
fi

write_if_changed /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

for timer in apt-daily.timer apt-daily-upgrade.timer; do
  if systemctl cat "$timer" >/dev/null 2>&1; then
    if systemctl is-enabled --quiet "$timer" && systemctl is-active --quiet "$timer"; then
      echo "OMITIDO: $timer ya está activo."
    else
      systemctl enable --now "$timer"
    fi
  fi
done

ssh_hardening_applied() {
  local effective
  effective="$(/usr/sbin/sshd -T 2>/dev/null)" || return 1

  for expected in \
    "pubkeyauthentication yes" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "permitrootlogin no"
  do
    grep -qxF "$expected" <<<"$effective" || return 1
  done
}

if ssh_hardening_applied; then
  echo "OMITIDO: SSH ya está endurecido."
elif [[ "$CONFIRM_SSH_HARDENING" == "YES" ]]; then
  write_if_changed /etc/ssh/sshd_config.d/00-hardening.conf 0644 <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF

  if ! /usr/sbin/sshd -t; then
    echo "ERROR: configuración SSH inválida. No se recargó SSH."
    exit 1
  fi

  if ! ssh_hardening_applied; then
    echo "ERROR: la configuración efectiva de SSH no coincide."
    exit 1
  fi

  systemctl reload ssh
  echo "SSH endurecido y recargado."
else
  echo "SSH todavía no fue endurecido."
  echo "Primero probá una segunda conexión con llave SSH."
  echo "Luego ejecutá:"
  echo "sudo CONFIRM_SSH_HARDENING=YES $0 $SSH_PORT"
fi

echo
echo "=== Estado final ==="
ufw status verbose
fail2ban-client status sshd
/usr/sbin/sshd -T | grep -E \
  '^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|permitrootlogin) '