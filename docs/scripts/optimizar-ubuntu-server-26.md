# Optimizar Ubuntu Server 26

[`optimizar-ubuntu-server-26.sh`](../../scripts/optimizar-ubuntu-server-26.sh)
aplica ajustes permanentes para un servidor Ubuntu 26.04 de desarrollo:

- `vm.swappiness` y límites de observadores de archivos mediante `sysctl`.
- Límites de descriptores para nuevas sesiones de login.
- `noatime` en las entradas ext4 de `/etc/fstab` que usan `defaults`.
- Activación de `fstrim.timer`.
- Ajustes de recolección de caché de BuildKit y rotación de logs en Docker,
  cuando Docker y `jq` están instalados.

El script **no** modifica el alias de Docker, la configuración del cliente SSH,
pnpm ni los ajustes de VS Code descritos más abajo. Tampoco reinicia Docker:
el mensaje final indica cómo aplicarle la configuración cuando sea conveniente.

## Uso desde el CLI

Desde la raíz del repositorio:

```bash
go run ./cmd/script-panel preview optimizar-ubuntu-server-26.sh
go run ./cmd/script-panel run optimizar-ubuntu-server-26.sh
```

El CLI presenta una confirmación antes de solicitar `sudo`. También se puede
ejecutar directamente:

```bash
sudo ./scripts/optimizar-ubuntu-server-26.sh
```

No acepta argumentos. Revísalo antes de ejecutarlo y úsalo únicamente en un
servidor Ubuntu compatible. Se requiere `jq` para actualizar la configuración
de Docker; si falta, el script conserva `daemon.json` sin cambios.

## Precauciones

- Cambia archivos de `/etc` y activa un temporizador de systemd. Reinicia el
  servidor al terminar para verificar los ajustes persistentes.
- Antes de modificar `/etc/fstab`, crea una copia con marca de tiempo; valida
  el archivo con `findmnt --verify` y restaura la copia si la validación falla.
  Las entradas ext4 que pasan la validación se vuelven a montar con `noatime`.
- El archivo de sysctl establece `max_user_watches` en `524288`, salvo que el
  valor activo del kernel ya sea mayor. Los límites de `limits.d` aplican a
  nuevas sesiones de login, no a servicios de systemd.
- Si Docker está instalado, se crea una copia de `daemon.json` existente antes
  de escribir. Revisa la configuración resultante; reiniciar Docker detiene
  contenedores sin política de reinicio.
- Mantén acceso alternativo al servidor mientras verificas los cambios y
  conserva las copias de seguridad hasta confirmar que todo funciona.

## Otros ajustes de la guía

Estos ajustes son manuales y no los aplica el script:

- `docker-clean` en `~/.bashrc` o `~/.zshrc`; edita el archivo como usuario
  normal, no con `sudo`.
- Configuración de SSH del cliente, por ejemplo `ControlMaster` y
  `ControlPersist`.
- Exclusiones de archivos de build y `node_modules` en los ajustes remotos de
  VS Code.
- Revisión de la ubicación del store de pnpm para mantenerlo en el mismo
  sistema de archivos que los proyectos.

Adapta cualquier ajuste manual a la configuración real de tu equipo y verifica
su efecto antes de cerrar tu sesión o reiniciar el servidor.
