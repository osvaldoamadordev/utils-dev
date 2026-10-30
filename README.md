# Utilidades para desarrolladores en Linux

Este repositorio reúne scripts, utilidades y curiosidades para desarrolladores que usan herramientas Linux, especialmente en equipos Ubuntu administrados por SSH. Busca ser una colección práctica, fácil de consultar y ampliar.

## Contenido

- [`scripts/add-worktree.sh`](scripts/add-worktree.sh): crea worktrees de Git para trabajar en ramas de funcionalidad.
- [`scripts/backup-pc-work.sh`](scripts/backup-pc-work.sh): respalda rutas de trabajo y configuraciones seleccionadas del PC.
- [`scripts/harden-ubuntu26.sh`](scripts/harden-ubuntu26.sh): configura medidas básicas de seguridad para Ubuntu 26 y SSH.
- [`scripts/ubuntu-maintenance.sh`](scripts/ubuntu-maintenance.sh): inventario, actualización y limpieza interactiva de herramientas en Ubuntu Server.
- [`scripts/backup-server.sh`](scripts/backup-server.sh): respaldo de proyectos y configuraciones personales del servidor.
- [`cmd/script-panel/`](cmd/script-panel/): CLI en Go con Cobra para consultar, previsualizar y ejecutar scripts.

Las instrucciones de uso, requisitos y precauciones de cada utilidad están en [`docs/scripts/`](docs/scripts/README.md).

## Uso

Conéctate al servidor por SSH, cambia al directorio del repositorio y consulta primero la ayuda o la vista previa de la utilidad:

```bash
ssh usuario@servidor
cd ruta/al/repositorio
./scripts/script-panel.sh
./scripts/ubuntu-maintenance.sh --help
./scripts/ubuntu-maintenance.sh --dry-run
```

El panel usa Go 1.24.2 o posterior, Cobra y Bubble Tea. Desde la raíz del
repositorio, ejecútalo con:

```bash
go run ./cmd/script-panel
```

Filtra escribiendo, navega con las flechas y revisa el código en la vista
previa. También puedes usar los subcomandos `list`, `preview` y `run`; este
último siempre pide confirmación. La ruta anterior
`./scripts/script-panel.sh` se conserva como lanzador compatible.

Ejecuta el panel como usuario normal, nunca con `sudo`. Solo el endurecimiento
de Ubuntu solicita `sudo`; revisa su guía y prueba una segunda sesión SSH con
llave antes de confirmar.

Para abrir el menú interactivo:

```bash
./scripts/ubuntu-maintenance.sh
```

Para revisar y crear un respaldo del home del servidor:

```bash
./scripts/backup-server.sh --help
./scripts/backup-server.sh
```

El respaldo predeterminado se guarda en `$HOME/backups-servidor`. También puedes indicar origen y destino como argumentos. El script excluye cachés, dependencias instaladas y sesiones regenerables; `Projects` puede hacer que el archivo sea grande.

## Notas de seguridad

- El script de mantenimiento está pensado para una sesión interactiva en Ubuntu; no lo ejecutes como `root`.
- El respaldo puede incluir claves SSH y credenciales de configuración. Limita el acceso al archivo y guárdalo en un destino cifrado y confiable.
- Las acciones requieren confirmación. Revisa cada operación antes de aceptarla.
- Las actualizaciones pueden cambiar versiones de los paquetes y algunas limpiezas pueden requerir descargas posteriores.
- Consulta el propio script antes de usarlo en un servidor importante.

## Añadir contenido

Organiza nuevas herramientas en directorios según su propósito. Al añadir un
script, incluye su descripción en este índice y agrega su guía de uso,
requisitos y precauciones en [`docs/scripts/`](docs/scripts/README.md).