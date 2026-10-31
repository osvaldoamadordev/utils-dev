package panel

import (
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestValidateScriptArgs(t *testing.T) {
	tests := []struct {
		name        string
		script      string
		args        []string
		wantErrPart string
	}{
		{name: "worktree branch", script: "add-worktree.sh", args: []string{"feature"}},
		{name: "worktree base", script: "add-worktree.sh", args: []string{"feature", "main"}},
		{name: "worktree requires branch", script: "add-worktree.sh", wantErrPart: "uso:"},
		{name: "backup defaults", script: "backup-server.sh"},
		{name: "backup source and destination", script: "backup-pc-work.sh", args: []string{"/home/me", "/backup"}},
		{name: "backup rejects extra paths", script: "backup-server.sh", args: []string{"a", "b", "c"}, wantErrPart: "como máximo"},
		{name: "default ssh port", script: "harden-ubuntu26.sh"},
		{name: "valid ssh port", script: "harden-ubuntu26.sh", args: []string{"65535"}},
		{name: "zero ssh port", script: "harden-ubuntu26.sh", args: []string{"0"}, wantErrPart: "puerto SSH inválido"},
		{name: "out of range ssh port", script: "harden-ubuntu26.sh", args: []string{"65536"}, wantErrPart: "puerto SSH inválido"},
		{name: "ssh key installation options", script: "install-ssh-key.sh", args: []string{"--user", "admin", "--host", "server", "--dry-run"}},
		{name: "maintenance has no args", script: "ubuntu-maintenance.sh", args: []string{"--dry-run"}, wantErrPart: "no acepta argumentos"},
		{name: "unknown script", script: "../README.md", wantErrPart: "no registrado"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			script, ok := FindScript(test.script)
			if !ok {
				script = Script{Name: test.script}
			}
			err := ValidateScriptArgs(script, test.args)
			if test.wantErrPart == "" {
				if err != nil {
					t.Fatalf("ValidateScriptArgs() error = %v", err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), test.wantErrPart) {
				t.Fatalf("ValidateScriptArgs() error = %v, want text %q", err, test.wantErrPart)
			}
		})
	}
}

func TestCommandForUsesFixedScriptAndArguments(t *testing.T) {
	root := t.TempDir()
	script, _ := FindScript("add-worktree.sh")
	command, err := CommandFor(root, script, []string{"feature", "main"})
	if err != nil {
		t.Fatalf("CommandFor() error = %v", err)
	}
	if filepath.Base(command.Path) != "bash" {
		t.Fatalf("command path = %q, want bash", command.Path)
	}
	wantArgs := []string{"bash", filepath.Join(root, "scripts", script.Name), "feature", "main"}
	if !reflect.DeepEqual(command.Args, wantArgs) {
		t.Fatalf("command args = %#v, want %#v", command.Args, wantArgs)
	}
	if command.Dir != root {
		t.Fatalf("command directory = %q, want %q", command.Dir, root)
	}
}

func TestCommandForUsesSudoOnlyForHardening(t *testing.T) {
	root := t.TempDir()
	script := Script{Name: "harden-ubuntu26.sh"}
	command, err := CommandFor(root, script, []string{"22"})
	if err != nil {
		t.Fatalf("CommandFor() error = %v", err)
	}
	if filepath.Base(command.Path) != "sudo" {
		t.Fatalf("command path = %q, want sudo", command.Path)
	}
	wantArgs := []string{"sudo", "--", "bash", filepath.Join(root, "scripts", script.Name), "22"}
	if !reflect.DeepEqual(command.Args, wantArgs) {
		t.Fatalf("command args = %#v, want %#v", command.Args, wantArgs)
	}
}

func TestCommandForRejectsNonCatalogScript(t *testing.T) {
	_, err := CommandFor(t.TempDir(), Script{Name: "../README.md"}, nil)
	if err == nil || !strings.Contains(err.Error(), "no registrado") {
		t.Fatalf("CommandFor() error = %v, want unknown-script error", err)
	}
}
