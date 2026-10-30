package panel

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveProjectRoot(t *testing.T) {
	root := fakeProject(t)
	tests := []struct {
		name        string
		explicit    string
		workingDir  string
		wantRoot    string
		wantErrPart string
	}{
		{
			name:       "finds repository from nested directory",
			workingDir: filepath.Join(root, "docs"),
			wantRoot:   root,
		},
		{
			name:       "accepts explicit repository root",
			explicit:   root,
			workingDir: t.TempDir(),
			wantRoot:   root,
		},
		{
			name:        "rejects directory without scripts",
			explicit:    t.TempDir(),
			workingDir:  root,
			wantErrPart: "no se encontraron",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := ResolveProjectRoot(test.explicit, test.workingDir)
			if test.wantErrPart != "" {
				if err == nil || !strings.Contains(err.Error(), test.wantErrPart) {
					t.Fatalf("ResolveProjectRoot() error = %v, want text %q", err, test.wantErrPart)
				}
				return
			}
			if err != nil {
				t.Fatalf("ResolveProjectRoot() error = %v", err)
			}
			if got != test.wantRoot {
				t.Fatalf("ResolveProjectRoot() = %q, want %q", got, test.wantRoot)
			}
		})
	}
}

func TestReadScriptAllowlist(t *testing.T) {
	root := fakeProject(t)
	got, err := ReadScript(root, "backup-server.sh")
	if err != nil {
		t.Fatalf("ReadScript() error = %v", err)
	}
	if got != "#!/usr/bin/env bash\n" {
		t.Fatalf("ReadScript() = %q", got)
	}

	if _, err := ReadScript(root, "../README.md"); err == nil {
		t.Fatal("ReadScript() accepted an unregistered path")
	}
}

func TestEscapeTerminalControls(t *testing.T) {
	got := EscapeTerminalControls("safe\ttext\n\x1b[31mred\x1b[0m")
	want := "safe\ttext\n\\x1b[31mred\\x1b[0m"
	if got != want {
		t.Fatalf("EscapeTerminalControls() = %q, want %q", got, want)
	}
}

func fakeProject(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	scriptDirectory := filepath.Join(root, "scripts")
	if err := os.Mkdir(scriptDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	for _, script := range Scripts() {
		if err := os.WriteFile(filepath.Join(scriptDirectory, script.Name), []byte("#!/usr/bin/env bash\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return root
}
