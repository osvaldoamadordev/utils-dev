# Respaldar archivos de trabajo del PC

[`backup-pc-work.sh`](../../scripts/backup-pc-work.sh) crea un archivo
comprimido con las rutas de trabajo y configuración seleccionadas en el
script. Omite cachés, dependencias instaladas y archivos regenerables.

## Uso

Consulta primero la ayuda:

```bash
bash scripts/backup-pc-work.sh --help
```

Sin argumentos, respalda las rutas existentes bajo `$HOME` en
`$HOME/backups-manuales`:

```bash
bash scripts/backup-pc-work.sh
```

También puedes indicar otro origen y, opcionalmente, un destino:

```bash
bash scripts/backup-pc-work.sh /home/usuario /ruta/segura
```

Si indicas solo el origen, el destino continúa siendo
`$HOME/backups-manuales`. Revisa la lista de rutas configuradas en el script
antes de ejecutarlo para confirmar qué datos se incluirán. El archivo se
verifica antes de terminar; el script no sobrescribe respaldos existentes ni
elimina archivos parciales.

Para revisar o restaurar el archivo, sigue las instrucciones de
[respaldo del servidor](backup-server.md#revisar-o-restaurar), usando la ruta
del respaldo generado.

## Precauciones

Cierra las aplicaciones que modifiquen los archivos incluidos durante el
respaldo. `--one-file-system` omite montajes de otros sistemas de archivos.
La restauración de propietarios, ACL y atributos extendidos requiere
privilegios de administrador; restaura primero en un directorio vacío y revisa
su contenido.
