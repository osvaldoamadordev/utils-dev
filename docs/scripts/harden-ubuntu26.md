# Endurecer Ubuntu 26

[`harden-ubuntu26.sh`](../../scripts/harden-ubuntu26.sh) instala y configura
OpenSSH Server, UFW, Fail2ban y actualizaciones desatendidas. Configura el
firewall para denegar conexiones entrantes por defecto y permite SSH en el
puerto indicado. También prepara una configuración SSH que desactiva el acceso
por contraseña y el inicio de sesión directo de `root`.

> **Riesgo de bloqueo:** no confirmes el endurecimiento de SSH hasta comprobar
> que puedes abrir una segunda sesión SSH usando una llave. Conserva abierta la
> sesión actual mientras haces la prueba. Si usas un puerto distinto de 22,
> asegúrate también de que ese puerto esté permitido en los firewalls externos
> o reglas de red de tu proveedor.

## Preparar y ejecutar

Desde la raíz del repositorio:

```bash
cd scripts
chmod 700 harden-ubuntu26.sh
bash -n harden-ubuntu26.sh
sudo ./harden-ubuntu26.sh 22
```

La primera ejecución configura las protecciones del sistema, pero no desactiva
el acceso SSH por contraseña. El argumento `22` es el puerto SSH; reemplázalo
si el servidor escucha en otro puerto válido.

Después de probar una segunda conexión con llave:

```bash
sudo CONFIRM_SSH_HARDENING=YES ./harden-ubuntu26.sh 22
```

El script valida la sintaxis de SSH y verifica la configuración efectiva antes
de recargar el servicio. Revisa el estado final que imprime y confirma que
puedes volver a conectarte.

## Instalarlo para ejecutarlo desde cualquier ubicación

Para proteger también el propio script:

```bash
sudo install -o root -g root -m 0700 \
  harden-ubuntu26.sh \
  /usr/local/sbin/harden-ubuntu26
```

Luego podés ejecutarlo desde cualquier ubicación:

```bash
sudo /usr/local/sbin/harden-ubuntu26 22
```

Para confirmar el endurecimiento de SSH con la copia instalada, primero prueba
la segunda conexión con llave y después ejecuta:

```bash
sudo CONFIRM_SSH_HARDENING=YES /usr/local/sbin/harden-ubuntu26 22
```

## Respaldo y mantenimiento

Cuando cambia una configuración administrada por el script, este conserva una
copia `.bak` si aún no existe, compara el contenido antes de escribir y aplica
propiedad `root:root` a los archivos de configuración (modo `0644`). La
instalación del ejecutable en `/usr/local/sbin` usa modo `0700`. No uses
`chattr +i`: impediría actualizaciones legítimas de las configuraciones. El
respaldo `.bak`, la propiedad `root:root`, los permisos del ejecutable y la
comparación previa ofrecen protección sin volver rígido el mantenimiento.

Cada ejecución instala o comprueba paquetes y configura UFW, Fail2ban y los
temporizadores de actualizaciones automáticas. Revisa el script antes de
usarlo en un servidor importante y asegúrate de contar con acceso alternativo
al servidor ante cualquier problema de red.
