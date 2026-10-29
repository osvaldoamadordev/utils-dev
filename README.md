# Utilidades para desarrolladores en Linux

Este repositorio reúne scripts, utilidades y curiosidades para desarrolladores que usan herramientas Linux, especialmente en equipos Ubuntu administrados por SSH. Busca ser una colección práctica, fácil de consultar y ampliar.

## Contenido

- [`scripts/ubuntu-maintenance.sh`](scripts/ubuntu-maintenance.sh): inventario, actualización y limpieza interactiva de herramientas en Ubuntu Server.

## Uso

Conéctate al servidor por SSH, cambia al directorio del repositorio y consulta primero la ayuda o la vista previa de la utilidad:

```bash
ssh usuario@servidor
cd ruta/al/repositorio
bash scripts/ubuntu-maintenance.sh --help
bash scripts/ubuntu-maintenance.sh --dry-run
```

Para abrir el menú interactivo:

```bash
bash scripts/ubuntu-maintenance.sh
```

## Notas de seguridad

- El script de mantenimiento está pensado para una sesión interactiva en Ubuntu; no lo ejecutes como `root`.
- Las acciones requieren confirmación. Revisa cada operación antes de aceptarla.
- Las actualizaciones pueden cambiar versiones de los paquetes y algunas limpiezas pueden requerir descargas posteriores.
- Consulta el propio script antes de usarlo en un servidor importante.

## Añadir contenido

Organiza nuevas herramientas en directorios según su propósito. Al añadir una, documenta aquí qué hace, sus requisitos, cómo usarla y cualquier efecto que pueda tener en el sistema.