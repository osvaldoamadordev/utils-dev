# Instalar una clave SSH en un servidor

[`install-ssh-key.sh`](../../scripts/install-ssh-key.sh) instala una clave
pública en `authorized_keys` usando `ssh-copy-id`. No cambia la configuración
del servidor y conserva la verificación de identidad del host de OpenSSH.

## Requisitos

- Bash
- `ssh-keygen`
- `ssh-copy-id` (no se necesita para `--dry-run`)
- Una clave pública válida o una terminal para seleccionar/generar una clave

## Uso interactivo

Desde la raíz del repositorio:

```bash
./scripts/install-ssh-key.sh
```

El menú permite elegir una clave `.pub` que `ssh-keygen` valide o crear una
nueva clave Ed25519. El host se elige de los alias `Host` definidos en
`~/.ssh/config`; OpenSSH resuelve el usuario, `HostName` y puerto efectivos de
ese alias. Si necesitas reemplazar el usuario o puerto de la configuración,
usa `--user` o `--port`. Al generar una clave, `ssh-keygen` solicita una frase
de contraseña; se recomienda configurarla.

Antes de conectar, el script muestra el destino, la huella de la clave y la
operación propuesta. Comprueba cuidadosamente el host y acepta su huella solo
si coincide con la que esperas. Después, `ssh-copy-id` puede solicitar la
contraseña o frase de contraseña necesaria para autenticarse.

## Opciones

```text
--user USUARIO          Sobrescribir el usuario SSH configurado
--host ALIAS             Alias SSH; sin este parámetro puedes elegir uno
--port PUERTO           Sobrescribir el puerto configurado
--key ARCHIVO.pub       Usar una clave pública existente
--key-name NOMBRE       Crear ~/.ssh/NOMBRE como clave Ed25519
--non-interactive       No preguntar datos faltantes
--yes                   Omitir la confirmación del destino y la huella
--dry-run               Mostrar la operación sin conectarse
```

`--key` y `--key-name` no se pueden usar juntos. El nombre de clave solo
permite letras, números, punto, guion y guion bajo. Si ya existe el archivo
privado o público con ese nombre, la creación falla sin sobrescribirlo.
Generar una clave requiere una terminal para introducir su frase de
contraseña; en modo no interactivo, proporciona una clave existente con
`--key`.

Los parámetros proporcionados tienen prioridad. En modo interactivo, si falta
`--host`, aparece un menú con los alias concretos `Host` encontrados en
`~/.ssh/config`; las entradas con comodines no se ofrecen. `--non-interactive`
falla si falta `--host` o una clave. Si no se indican `--user` ni `--port`, se
usan los valores efectivos de OpenSSH (incluidos sus valores predeterminados).
`--host` también acepta un nombre de host directo.

## Ejemplos

Revisar el plan sin conexión:

```bash
./scripts/install-ssh-key.sh \
  --host mi-servidor \
  --key ~/.ssh/id_ed25519.pub \
  --dry-run
```

El alias `mi-servidor` debe estar definido como `Host mi-servidor` en
`~/.ssh/config`; se respeta su `HostName`, usuario y puerto.

Instalar una clave ya existente sin preguntas del script:

```bash
./scripts/install-ssh-key.sh \
  --host mi-servidor \
  --key ~/.ssh/id_ed25519.pub \
  --non-interactive \
  --yes
```

`--yes` solo omite la confirmación local; no desactiva la verificación de
identidad del servidor. No lo uses hasta comprobar el destino y la huella.
`--dry-run` nunca se conecta y no requiere `--yes`.
