# Crear un worktree de Git

[`add-worktree.sh`](../../scripts/add-worktree.sh) crea un worktree bajo
`worktrees/<feature>` en el repositorio principal y prepara una rama con el
nombre de la feature. La rama se basa en la rama actual por defecto; también
puedes indicar una rama base. Si existe `origin/<feature>`, el script crea
una rama local que sigue esa rama remota.

## Uso

Desde cualquier ubicación dentro del repositorio principal —no desde un
worktree existente— ejecuta:

```bash
bash /ruta/al/repositorio/scripts/add-worktree.sh feature-name
```

Para elegir la rama base:

```bash
bash /ruta/al/repositorio/scripts/add-worktree.sh feature-name develop
```

Por ejemplo, desde la raíz del repositorio:

```bash
bash scripts/add-worktree.sh 001-crm-prospectos
bash scripts/add-worktree.sh 002-api develop
```

El nombre debe comenzar con una letra o un número y solo puede contener
letras, números, guiones y guiones bajos. La rama base debe existir localmente
o como `origin/<rama>`. Consulta la sintaxis con:

```bash
bash scripts/add-worktree.sh --help
```

Al finalizar, cambia al directorio `worktrees/<feature>` que muestra el
resumen. Si el directorio `worktrees/` no estaba excluido de Git, el script
añade esa exclusión a `.git/info/exclude`.

## Archivos de entorno y precauciones

El script copia archivos `.env` y `.env.*` locales que Git no haya creado ya
en el worktree, conserva sus metadatos y establece permisos `600`. Omite
enlaces simbólicos y archivos de destino existentes. Estos archivos pueden
contener credenciales; revisa quién puede acceder al worktree y no los
compartas.

Los cambios sin commit del repositorio principal no se trasladan al worktree,
salvo esos archivos de entorno. El script no elimina ni sobrescribe el
directorio de destino si ya existe.
