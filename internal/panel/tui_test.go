package panel

import (
	"os"
	"strings"
	"testing"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
)

func TestTUIBrowseSelectionStartsArgumentFlow(t *testing.T) {
	model := newTUIModel("/repo", Scripts())

	updated, command := model.Update(tea.KeyMsg{Type: tea.KeyEnter})
	got := updated.(*tuiModel)
	if command == nil {
		t.Fatal("opening the argument prompt did not start the text-input cursor")
	}
	if got.screen != argumentsScreen {
		t.Fatalf("screen after selecting worktree = %v, want arguments screen", got.screen)
	}
	if got.selected.Name != "add-worktree.sh" {
		t.Fatalf("selected script = %q, want add-worktree.sh", got.selected.Name)
	}
	if got.fields[0].label != "Nombre de la nueva rama" {
		t.Fatalf("first argument prompt = %q", got.fields[0].label)
	}
}

func TestTUIBackupDestinationUsesHomeWhenOriginIsBlank(t *testing.T) {
	script, _ := FindScript("backup-server.sh")
	model := newTUIModel("/repo", Scripts())
	model.selected = script
	model.fields = makeFields(script)
	model.fields[0].value = ""
	model.fields[1].value = "/backups"

	if err := model.finishArguments(); err != nil {
		t.Fatalf("finishArguments() error = %v", err)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	if len(model.args) != 2 || model.args[0] != home || model.args[1] != "/backups" {
		t.Fatalf("backup args = %#v, want home and destination", model.args)
	}
}

func TestTUIConfirmCancellationReturnsToBrowser(t *testing.T) {
	model := newTUIModel("/repo", Scripts())
	model.selected, _ = FindScript("ubuntu-maintenance.sh")
	model.beginArguments()
	if model.screen != confirmScreen {
		t.Fatalf("screen = %v, want confirmation screen", model.screen)
	}

	updated, command := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("n")})
	got := updated.(*tuiModel)
	if command != nil {
		t.Fatal("cancellation unexpectedly scheduled a command")
	}
	if got.screen != browseScreen {
		t.Fatalf("screen after cancellation = %v, want browser", got.screen)
	}
	if got.message != "Ejecución cancelada." {
		t.Fatalf("cancellation message = %q", got.message)
	}
}

func TestTUIKeepsQAsFilterInput(t *testing.T) {
	model := newTUIModel("/repo", Scripts())
	model.list.SetFilterState(list.Filtering)

	updated, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("q")})
	got := updated.(*tuiModel)
	if got.screen != browseScreen {
		t.Fatalf("screen = %v, want browser", got.screen)
	}
	if got.list.FilterState() != list.Filtering {
		t.Fatal("q ended filtering instead of being entered into the filter")
	}
}

func TestTUIEnterAcceptsFilterBeforeSelecting(t *testing.T) {
	model := newTUIModel("/repo", Scripts())
	model.list.SetFilterText("backup-server")
	model.list.SetFilterState(list.Filtering)

	updated, _ := model.Update(tea.KeyMsg{Type: tea.KeyEnter})
	got := updated.(*tuiModel)
	if got.screen != browseScreen {
		t.Fatalf("screen after accepting filter = %v, want browser", got.screen)
	}
	if got.list.FilterState() != list.FilterApplied {
		t.Fatalf("filter state = %v, want accepted filter", got.list.FilterState())
	}

	updated, _ = got.Update(tea.KeyMsg{Type: tea.KeyEnter})
	got = updated.(*tuiModel)
	if got.screen != argumentsScreen {
		t.Fatalf("screen after selecting filtered script = %v, want arguments", got.screen)
	}
	if got.selected.Name != "backup-server.sh" {
		t.Fatalf("selected script = %q, want backup-server.sh", got.selected.Name)
	}
}

func TestTUIPreviewCanScrollAndResetsWhenSelectionChanges(t *testing.T) {
	scripts := Scripts()
	for index := range scripts {
		scripts[index].Source = strings.Repeat("line\n", 40)
	}
	model := newTUIModel("/repo", scripts)
	model.height = 30

	updated, _ := model.Update(tea.KeyMsg{Type: tea.KeyCtrlD})
	got := updated.(*tuiModel)
	if got.previewOffset == 0 {
		t.Fatal("Ctrl+D did not scroll the source preview")
	}

	updated, _ = got.Update(tea.KeyMsg{Type: tea.KeyDown})
	got = updated.(*tuiModel)
	if got.selected.Name != "backup-pc-work.sh" {
		t.Fatalf("selected script = %q, want backup-pc-work.sh", got.selected.Name)
	}
	if got.previewOffset != 0 {
		t.Fatalf("preview offset after changing selection = %d, want 0", got.previewOffset)
	}
}
