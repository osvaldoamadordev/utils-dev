# Mantener Ubuntu Server

[`ubuntu-maintenance.sh`](../../scripts/ubuntu-maintenance.sh) muestra el
inventario de herramientas disponibles y ofrece un menú interactivo para
actualizar o limpiar gestores de paquetes y cachés. No tiene modo automático:
cada acción requiere confirmación. Ejecútalo como usuario normal en Ubuntu
Server; el script usa `sudo` solo para las operaciones de APT.

## Uso

Desde la raíz del repositorio, consulta la ayuda y el plan sin ejecutar acciones:

```bash
bash scripts/ubuntu-maintenance.sh --help
bash scripts/ubuntu-maintenance.sh --dry-run
```

Para abrir el menú:

```bash
bash scripts/ubuntu-maintenance.sh
```

En el menú, `i` muestra el inventario, `p` vuelve a mostrar el plan, `u`
presenta las actualizaciones, `c` presenta las limpiezas y `q` sale. Lee cada
confirmación antes de responder; APT y Docker también pueden pedir su propia
confirmación.

## Precauciones

- No ejecutes el script como `root` ni con `sudo`.
- Las actualizaciones pueden cambiar versiones mayores. Revisa respaldos y
  programa una ventana de mantenimiento.
- Las limpiezas eliminan cachés o versiones sin uso; algunas operaciones
  requerirán descargas posteriores.
- El script crea un registro temporal privado con los estados de las acciones.
  La salida detallada de las herramientas permanece en la terminal.
