package panel

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

func TestConfirmAndRun(t *testing.T) {
	script, _ := FindScript("backup-server.sh")
	executionFailure := errors.New("script failed")
	tests := []struct {
		name       string
		answer     string
		wantCalled bool
		runErr     error
		wantErr    error
	}{
		{name: "default cancels", answer: "\n"},
		{name: "affirmative runs", answer: "s\n", wantCalled: true},
		{name: "english affirmative runs", answer: "Y\n", wantCalled: true},
		{name: "reports execution failure", answer: "s\n", wantCalled: true, runErr: executionFailure, wantErr: executionFailure},
		{name: "unexpected answer cancels", answer: "maybe\n"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var output bytes.Buffer
			called := false
			err := confirmAndRun(strings.NewReader(test.answer), &output, "/repo", script, nil,
				func(root string, gotScript Script, args []string) error {
					called = true
					if root != "/repo" || gotScript.Name != script.Name || len(args) != 0 {
						t.Fatalf("execute received root %q, script %q, args %#v", root, gotScript.Name, args)
					}
					return test.runErr
				})
			if !errors.Is(err, test.wantErr) {
				t.Fatalf("confirmAndRun() error = %v, want %v", err, test.wantErr)
			}
			if called != test.wantCalled {
				t.Fatalf("execute called = %t, want %t", called, test.wantCalled)
			}
			if !test.wantCalled && !strings.Contains(output.String(), "Ejecución cancelada.") {
				t.Fatalf("cancel output = %q", output.String())
			}
		})
	}
}

func TestCobraListAndPreview(t *testing.T) {
	rootDirectory := fakeProject(t)
	tests := []struct {
		name      string
		args      []string
		wantText  string
		wantError bool
	}{
		{
			name:     "lists scripts",
			args:     []string{"list"},
			wantText: "add-worktree.sh",
		},
		{
			name:     "previews allowlisted script",
			args:     []string{"--project-dir", rootDirectory, "preview", "backup-server.sh"},
			wantText: "#!/usr/bin/env bash",
		},
		{
			name:      "rejects unknown preview",
			args:      []string{"--project-dir", rootDirectory, "preview", "../README.md"},
			wantError: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			command := NewRootCommand()
			var output bytes.Buffer
			command.SetOut(&output)
			command.SetErr(&output)
			command.SetArgs(test.args)
			err := command.Execute()
			if (err != nil) != test.wantError {
				t.Fatalf("Execute() error = %v, want error %t", err, test.wantError)
			}
			if !test.wantError && !strings.Contains(output.String(), test.wantText) {
				t.Fatalf("command output %q does not contain %q", output.String(), test.wantText)
			}
		})
	}
}
