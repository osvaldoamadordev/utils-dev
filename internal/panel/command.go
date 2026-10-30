package panel

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
	"text/tabwriter"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

func NewRootCommand() *cobra.Command {
	var projectDirectory string

	root := &cobra.Command{
		Use:           "script-panel",
		Short:         "Explora y ejecuta los scripts del repositorio",
		Long:          "Busca scripts con vista previa del código, consulta su uso y ejecútalos solo después de confirmar.",
		SilenceUsage:  true,
		SilenceErrors: true,
		Args:          cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if err := ensureNotRoot(); err != nil {
				return err
			}
			root, err := resolveRoot(projectDirectory)
			if err != nil {
				return err
			}
			return runTUI(root)
		},
	}
	root.PersistentFlags().StringVar(&projectDirectory, "project-dir", "", "directorio del repositorio (por defecto, busca desde el directorio actual)")

	root.AddCommand(newListCommand(), newPreviewCommand(), newRunCommand(&projectDirectory))
	return root
}

func newListCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "Lista los scripts disponibles",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			writer := tabwriter.NewWriter(cmd.OutOrStdout(), 0, 4, 2, ' ', 0)
			fmt.Fprintln(writer, "SCRIPT\tDESCRIPCIÓN\tPRECAUCIÓN")
			for _, script := range Scripts() {
				fmt.Fprintf(writer, "%s\t%s\t%s\n", script.Name, script.Description, script.Warning)
			}
			return writer.Flush()
		},
	}
}

func newPreviewCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "preview <script>",
		Short: "Muestra el código de un script permitido",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			root, err := resolveRootFromCommand(cmd)
			if err != nil {
				return err
			}
			content, err := ReadScript(root, args[0])
			if err != nil {
				return err
			}
			_, err = io.WriteString(cmd.OutOrStdout(), content)
			return err
		},
	}
}

func newRunCommand(projectDirectory *string) *cobra.Command {
	return &cobra.Command{
		Use:   "run <script> [argumentos...]",
		Short: "Ejecuta un script registrado después de confirmar",
		Long: "Los argumentos se pasan directamente al script seleccionado, sin interpretarlos como comandos. " +
			"El comando siempre pide confirmación y rechaza la ejecución si no hay una terminal interactiva.",
		Example: "  script-panel run add-worktree.sh nueva-funcionalidad\n" +
			"  script-panel run backup-server.sh /home/usuario /ruta/segura\n" +
			"  script-panel run harden-ubuntu26.sh 22",
		Args: cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := ensureNotRoot(); err != nil {
				return err
			}
			if !stdinIsTerminal() {
				return fmt.Errorf("run requiere una terminal para confirmar la ejecución")
			}
			script, ok := FindScript(args[0])
			if !ok {
				return fmt.Errorf("script no registrado: %s", args[0])
			}
			scriptArgs := args[1:]
			if err := ValidateScriptArgs(script, scriptArgs); err != nil {
				return err
			}

			root, err := resolveRoot(*projectDirectory)
			if err != nil {
				return err
			}
			return confirmAndRun(cmd.InOrStdin(), cmd.OutOrStdout(), root, script, scriptArgs, RunScript)
		},
	}
}

func confirmAndRun(
	input io.Reader,
	output io.Writer,
	root string,
	script Script,
	args []string,
	execute func(string, Script, []string) error,
) error {
	fmt.Fprintf(output, "\nScript seleccionado: %s\n", script.Name)
	fmt.Fprintf(output, "Descripción: %s\n", script.Description)
	fmt.Fprintf(output, "Precaución: %s\n", script.Warning)
	fmt.Fprint(output, "¿Ejecutar este script? [s/N] ")

	reader := bufio.NewReader(input)
	answer, err := reader.ReadString('\n')
	if err != nil && len(answer) == 0 {
		return fmt.Errorf("no se pudo leer la confirmación: %w", err)
	}
	switch strings.ToLower(strings.TrimSpace(answer)) {
	case "s", "si", "y":
		return execute(root, script, args)
	default:
		fmt.Fprintln(output, "Ejecución cancelada.")
		return nil
	}
}

func runTUI(root string) error {
	loaded := make([]Script, 0, len(scripts))
	for _, script := range Scripts() {
		content, err := ReadScript(root, script.Name)
		if err != nil {
			return err
		}
		script.Source = content
		loaded = append(loaded, script)
	}

	model := newTUIModel(root, loaded)
	program := tea.NewProgram(model, tea.WithAltScreen())
	finalModel, err := program.Run()
	if err != nil {
		return fmt.Errorf("iniciar panel interactivo: %w", err)
	}
	result, ok := finalModel.(*tuiModel)
	if !ok {
		return fmt.Errorf("el panel terminó con un estado inesperado")
	}
	return result.runErr
}

func resolveRoot(explicit string) (string, error) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("leer directorio actual: %w", err)
	}
	return ResolveProjectRoot(explicit, workingDirectory)
}

func resolveRootFromCommand(cmd *cobra.Command) (string, error) {
	directory, err := cmd.Flags().GetString("project-dir")
	if err == nil && directory == "" {
		directory, err = cmd.InheritedFlags().GetString("project-dir")
	}
	if err != nil {
		return "", fmt.Errorf("leer --project-dir: %w", err)
	}
	return resolveRoot(directory)
}

func ensureNotRoot() error {
	if os.Geteuid() == 0 {
		return fmt.Errorf("no ejecutes el panel como root; solo harden-ubuntu26.sh solicita sudo")
	}
	return nil
}

func stdinIsTerminal() bool {
	info, err := os.Stdin.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}
