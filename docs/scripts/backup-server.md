# Respaldar el home del servidor

[`backup-server.sh`](../../scripts/backup-server.sh) crea un archivo
comprimido con proyectos y configuraciones personales seleccionadas del home.
Omite cachés, dependencias instaladas, sesiones y otros datos regenerables.

## Uso

Consulta primero la ayuda:

```bash
bash scripts/backup-server.sh --help
```

Sin argumentos, respalda `$HOME` en `$HOME/backups-servidor`:

```bash
bash scripts/backup-server.sh
```

También puedes indicar un origen y, opcionalmente, un destino:

```bash
bash scripts/backup-server.sh /home/usuario /ruta/segura
```

Si indicas solo el origen, el destino continúa siendo
`$HOME/backups-servidor`. El script informa la ruta del archivo creado y
verifica el archivo comprimido antes de terminar. No sobrescribe respaldos
existentes ni elimina archivos parciales.

## Revisar o restaurar

Para listar el contenido, usa la ruta del archivo que imprimió el script:

```bash
tar -tzf /ruta/al/respaldo.tgz | less
```

Restaura primero en un directorio vacío y revisa su contenido antes de
integrarlo al sistema. Restaurar propietarios requiere privilegios:

```bash
sudo mkdir -p /ruta/restauracion
sudo tar --extract --gzip --file /ruta/al/respaldo.tgz \
  --directory /ruta/restauracion --same-owner --acls --xattrs
```

## Precauciones

El respaldo puede incluir claves SSH, credenciales y configuraciones privadas.
El archivo se crea con permisos `600`; guárdalo en un destino cifrado y
confiable. Cierra las aplicaciones que modifiquen los archivos incluidos
mientras se ejecuta el respaldo. `Projects` puede ocupar bastante espacio y
los montajes de otros sistemas de archivos no se incluyen.
