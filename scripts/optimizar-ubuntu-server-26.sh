#!/usr/bin/env bash
# Optimización de sistema para Ubuntu Server 26.04 LTS (entorno de desarrollo).
# Aplica de forma permanente: sysctl, límites de descriptores,
# noatime en fstab, fstrim.timer y daemon.json de Docker.
# Es repetible: ejecutarlo varias veces no duplica configuración.
#
# Uso: sudo ./optimizar-ubuntu-server-26.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo: sudo $0" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"

log() { printf '\n==> %s\n' "$*"; }

# 1. sysctl ------------------------------------------------------------------
log "sysctl: /etc/sysctl.d/99-server-performance.conf"
cat > /etc/sysctl.d/99-server-performance.conf <<'EOF'
# Swap: preferir RAM
vm.swappiness=10

# Observadores de archivos (TypeScript, Vite, Angular, Webpack, VS Code)
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF

# No bajar inotify si el kernel ya trae un valor mayor
current_watches="$(sysctl -n fs.inotify.max_user_watches)"
if (( current_watches > 524288 )); then
  sed -i '/^fs.inotify.max_user_watches=/d' /etc/sysctl.d/99-server-performance.conf
  echo "max_user_watches actual ($current_watches) es mayor a 524288: se conserva el del kernel."
fi
sysctl --system >/dev/null
sysctl vm.swappiness fs.inotify.max_user_watches fs.inotify.max_user_instances

# 2. Límites de descriptores -------------------------------------------------
log "limits: /etc/security/limits.d/99-dev-limits.conf"
cat > /etc/security/limits.d/99-dev-limits.conf <<'EOF'
* soft nofile 65536
* hard nofile 524288
root soft nofile 65536
root hard nofile 524288
EOF

# 3. fstab: noatime en ext4 --------------------------------------------------
log "fstab: noatime en líneas ext4 con opciones 'defaults'"
cp /etc/fstab "/etc/fstab.bak-$STAMP"
sed -i -E '/\sext4\s/ s/\sdefaults(\s)/ defaults,noatime\1/' /etc/fstab
diff "/etc/fstab.bak-$STAMP" /etc/fstab || true

if findmnt --verify; then
  while read -r mp; do
    mount -o remount,noatime "$mp" && echo "remount noatime: $mp"
  done < <(awk '$3=="ext4" && $4 ~ /noatime/ {print $2}' /etc/fstab)
else
  echo "findmnt --verify reportó problemas. Se restaura el fstab original." >&2
  cp "/etc/fstab.bak-$STAMP" /etc/fstab
  exit 1
fi

# 4. TRIM periódico ----------------------------------------------------------
log "fstrim.timer"
systemctl enable --now fstrim.timer || echo "No se pudo activar fstrim.timer." >&2

# 5. Docker daemon.json ------------------------------------------------------
log "Docker: /etc/docker/daemon.json"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker no instalado: omitido."
elif ! command -v jq >/dev/null 2>&1; then
  echo "Falta jq (sudo apt install jq). daemon.json omitido para no sobrescribir tu configuración." >&2
else
  mkdir -p /etc/docker
  [[ -f /etc/docker/daemon.json ]] && cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak-$STAMP"
  existing='{}'
  [[ -s /etc/docker/daemon.json ]] && existing="$(cat /etc/docker/daemon.json)"
  wanted='{
    "builder": { "gc": { "enabled": true, "defaultKeepStorage": "20GB" } },
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "3" }
  }'
  jq -n --argjson a "$existing" --argjson b "$wanted" '$a * $b' > /etc/docker/daemon.json.new
  mv /etc/docker/daemon.json.new /etc/docker/daemon.json
  echo "daemon.json fusionado. Para aplicar: sudo systemctl restart docker (detiene contenedores sin restart policy)."
fi

log "Listo. Reinicia el servidor y verifica:"
cat <<'EOF'
  sysctl vm.swappiness fs.inotify.max_user_watches fs.inotify.max_user_instances
  findmnt -o TARGET,OPTIONS | grep noatime
  ulimit -Sn; ulimit -Hn
  docker info | grep -i "logging driver"
EOF
