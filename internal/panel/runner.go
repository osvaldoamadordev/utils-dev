package panel

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func CommandFor(root string, script Script, args []string) (*exec.Cmd, error) {
	canonical, ok := FindScript(script.Name)
	if !ok {
		return nil, fmt.Errorf("script no registrado: %s", script.Name)
	}
	script = canonical

	if err := ValidateScriptArgs(script, args); err != nil {
		return nil, err
	}

	scriptPath := filepath.Join(root, "scripts", script.Name)
	commandArgs := []string{scriptPath}
	commandName := "bash"
	if script.NeedsSudo {
		commandName = "sudo"
		commandArgs = []string{"--", "bash", scriptPath}
	}
	commandArgs = append(commandArgs, args...)

	command := exec.Command(commandName, commandArgs...)
	command.Dir = root
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command, nil
}

func RunScript(root string, script Script, args []string) error {
	if os.Geteuid() == 0 {
		return fmt.Errorf("no ejecutes el panel como root; usa sudo solo para harden-ubuntu26.sh")
	}
	command, err := CommandFor(root, script, args)
	if err != nil {
		return err
	}
	if err := command.Run(); err != nil {
		return fmt.Errorf("%s terminó con error: %w", script.Name, err)
	}
	return nil
}
