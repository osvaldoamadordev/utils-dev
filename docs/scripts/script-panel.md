# CLI Go para consultar y ejecutar scripts

La CLI en [`cmd/script-panel/`](../../cmd/script-panel/) usa Cobra para los
comandos y Bubble Tea para el selector interactivo con vista previa. Los
scripts Bash siguen siendo las utilidades que ejecuta; la interfaz y el
orquestador son Go.

## Uso

Requiere Go 1.24.2 o posterior. Desde la raíz del repositorio:

```bash
go run ./cmd/script-panel
```

Filtra por nombre o descripción, navega con las flechas y selecciona con
`Enter`. Revisa la descripción, la precaución y el código antes de confirmar.
Los argumentos se solicitan según el script seleccionado; los scripts de
respaldo usan los valores predeterminados si dejas las rutas vacías.

El lanzador `./scripts/script-panel.sh` sigue disponible por compatibilidad y
traduce `--list` / `--preview` a los subcomandos nuevos.

## Subcomandos

```bash
go run ./cmd/script-panel list
go run ./cmd/script-panel preview backup-server.sh
go run ./cmd/script-panel run add-worktree.sh nueva-funcionalidad
go run ./cmd/script-panel run backup-server.sh /home/usuario /ruta/segura
go run ./cmd/script-panel run harden-ubuntu26.sh 22
```

`run` siempre requiere una terminal y solicita confirmación. El nombre del
script debe pertenecer a la lista permitida; los argumentos se pasan como
valores separados, nunca como comandos de shell. El panel no se puede ejecutar
como `root`; `harden-ubuntu26.sh` es el único que solicita `sudo`.

Antes de confirmar el endurecimiento de SSH, prueba una segunda conexión con
llave y revisa [su guía](./harden-ubuntu26.md). Consulta las demás guías de
este directorio para conocer requisitos y precauciones.
