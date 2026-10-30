package panel

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"
)

type Script struct {
	Name        string
	Description string
	Warning     string
	NeedsSudo   bool
	Source      string
}

var scripts = []Script{
	{
		Name:        "add-worktree.sh",
		Description: "Crea un worktree de Git y prepara una rama para una nueva funcionalidad.",
		Warning:     "Copia archivos .env al worktree; verifica permisos y destino.",
	},
	{
		Name:        "backup-pc-work.sh",
		Description: "Respalda rutas de trabajo y configuraciones seleccionadas del PC.",
		Warning:     "El respaldo puede incluir archivos privados. Cierra las aplicaciones que los modifican.",
	},
	{
		Name:        "backup-server.sh",
		Description: "Respalda proyectos y configuraciones personales del home del servidor.",
		Warning:     "Puede incluir claves y credenciales; guarda el archivo en un destino cifrado.",
	},
	{
		Name:        "harden-ubuntu26.sh",
		Description: "Configura OpenSSH, UFW, Fail2ban y actualizaciones desatendidas en Ubuntu 26.",
		Warning:     "Antes de confirmar el endurecimiento SSH, prueba una segunda sesión con llave.",
		NeedsSudo:   true,
	},
	{
		Name:        "ubuntu-maintenance.sh",
		Description: "Muestra un inventario y ofrece mantenimiento interactivo de herramientas en Ubuntu.",
		Warning:     "Las actualizaciones pueden cambiar versiones y la limpieza elimina cachés.",
	},
}

func Scripts() []Script {
	return append([]Script(nil), scripts...)
}

func FindScript(name string) (Script, bool) {
	for _, script := range scripts {
		if script.Name == name {
			return script, true
		}
	}
	return Script{}, false
}

func ResolveProjectRoot(explicit, workingDirectory string) (string, error) {
	if explicit != "" {
		root, err := filepath.Abs(explicit)
		if err != nil {
			return "", fmt.Errorf("resolve project directory: %w", err)
		}
		if !isProjectRoot(root) {
			return "", fmt.Errorf("no se encontraron los scripts del proyecto en %s", root)
		}
		return root, nil
	}

	current, err := filepath.Abs(workingDirectory)
	if err != nil {
		return "", fmt.Errorf("resolve current directory: %w", err)
	}

	for dir := current; ; dir = filepath.Dir(dir) {
		if isProjectRoot(dir) {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
	}

	return "", fmt.Errorf("no se encontró el repositorio; ejecuta la CLI desde el proyecto o indica --project-dir")
}

func isProjectRoot(root string) bool {
	for _, script := range scripts {
		info, err := os.Stat(filepath.Join(root, "scripts", script.Name))
		if err != nil || !info.Mode().IsRegular() {
			return false
		}
	}
	return true
}

func ReadScript(root, name string) (string, error) {
	script, ok := FindScript(name)
	if !ok {
		return "", fmt.Errorf("script no registrado: %s", name)
	}

	content, err := os.ReadFile(filepath.Join(root, "scripts", script.Name))
	if err != nil {
		return "", fmt.Errorf("leer %s: %w", script.Name, err)
	}
	return EscapeTerminalControls(string(content)), nil
}

func EscapeTerminalControls(value string) string {
	var escaped strings.Builder
	value = strings.ToValidUTF8(value, "\uFFFD")
	for _, character := range value {
		switch {
		case character == '\n', character == '\t':
			escaped.WriteRune(character)
		case unicode.IsControl(character):
			if character <= 0xff {
				fmt.Fprintf(&escaped, "\\x%02x", character)
			} else {
				fmt.Fprintf(&escaped, "\\u%04x", character)
			}
		default:
			escaped.WriteRune(character)
		}
	}
	return escaped.String()
}

func ValidateScriptArgs(script Script, args []string) error {
	switch script.Name {
	case "add-worktree.sh":
		if len(args) < 1 || len(args) > 2 {
			return fmt.Errorf("uso: run %s <nombre-rama> [rama-base]", script.Name)
		}
	case "backup-pc-work.sh", "backup-server.sh":
		if len(args) > 2 {
			return fmt.Errorf("%s acepta como máximo origen y destino", script.Name)
		}
	case "harden-ubuntu26.sh":
		if len(args) > 1 {
			return fmt.Errorf("uso: run %s [puerto-ssh]", script.Name)
		}
		if len(args) == 1 {
			port, err := strconv.ParseUint(args[0], 10, 16)
			if err != nil || port == 0 {
				return fmt.Errorf("puerto SSH inválido: debe ser un número entre 1 y 65535")
			}
		}
	case "ubuntu-maintenance.sh":
		if len(args) != 0 {
			return fmt.Errorf("%s no acepta argumentos", script.Name)
		}
	default:
		return fmt.Errorf("script no registrado: %s", script.Name)
	}
	return nil
}
