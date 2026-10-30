package panel

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type screen int

const (
	browseScreen screen = iota
	argumentsScreen
	confirmScreen
	runningScreen
	resultScreen
)

type scriptItem struct {
	script Script
}

func (item scriptItem) Title() string       { return item.script.Name }
func (item scriptItem) Description() string { return item.script.Description }
func (item scriptItem) FilterValue() string {
	return item.script.Name + " " + item.script.Description
}

type argumentField struct {
	label       string
	placeholder string
	required    bool
	input       textinput.Model
	value       string
}

type tuiModel struct {
	root          string
	list          list.Model
	screen        screen
	selected      Script
	fields        []argumentField
	fieldIndex    int
	args          []string
	message       string
	runErr        error
	width         int
	height        int
	previewOffset int
}

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#F095C8"))
	mutedStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#9AA5B1"))
	accentStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#84DCC6"))
	warningStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#F2C879"))
	panelStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#35414D")).
			Padding(0, 1)
)

func newTUIModel(root string, scripts []Script) *tuiModel {
	items := make([]list.Item, 0, len(scripts))
	for _, script := range scripts {
		items = append(items, scriptItem{script: script})
	}

	delegate := list.NewDefaultDelegate()
	delegate.SetHeight(2)
	delegate.SetSpacing(1)
	scriptList := list.New(items, delegate, 0, 0)
	scriptList.Title = "Scripts disponibles"
	scriptList.SetShowStatusBar(false)
	scriptList.SetFilteringEnabled(true)
	scriptList.SetShowHelp(false)
	scriptList.DisableQuitKeybindings()

	return &tuiModel{
		root:     root,
		list:     scriptList,
		selected: scripts[0],
	}
}

func (model *tuiModel) Init() tea.Cmd {
	return nil
}

func (model *tuiModel) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch message := message.(type) {
	case tea.WindowSizeMsg:
		model.width = message.Width
		model.height = message.Height
		model.resizeList()
		return model, nil
	case processFinishedMsg:
		model.runErr = message.err
		model.screen = resultScreen
		if message.err != nil {
			model.message = fmt.Sprintf("El script terminó con error: %v", message.err)
		} else {
			model.message = "El script terminó correctamente."
		}
		return model, nil
	case tea.KeyMsg:
		return model.updateKey(message)
	}

	if model.screen == browseScreen {
		updated, command := model.list.Update(message)
		model.list = updated
		model.syncSelected()
		return model, command
	}
	return model, nil
}

func (model *tuiModel) updateKey(message tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch model.screen {
	case browseScreen:
		switch message.String() {
		case "ctrl+c":
			return model, tea.Quit
		case "q":
			if model.list.FilterState() != list.Filtering {
				return model, tea.Quit
			}
			updated, command := model.list.Update(message)
			model.list = updated
			model.syncSelected()
			return model, command
		case "ctrl+d", "pgdown":
			model.scrollPreview(1)
			return model, nil
		case "ctrl+u", "pgup":
			model.scrollPreview(-1)
			return model, nil
		case "enter":
			if model.list.FilterState() == list.Filtering {
				updated, command := model.list.Update(message)
				model.list = updated
				model.syncSelected()
				return model, command
			}
			selected, ok := model.list.SelectedItem().(scriptItem)
			if !ok {
				return model, nil
			}
			model.selected = selected.script
			model.message = ""
			model.args = nil
			return model, model.beginArguments()
		default:
			updated, command := model.list.Update(message)
			model.list = updated
			model.syncSelected()
			return model, command
		}
	case argumentsScreen:
		switch message.String() {
		case "ctrl+c", "esc":
			model.screen = browseScreen
			model.message = ""
			return model, nil
		case "enter":
			field := &model.fields[model.fieldIndex]
			field.value = field.input.Value()
			if field.required && strings.TrimSpace(field.value) == "" {
				model.message = "Este valor es obligatorio."
				return model, nil
			}
			model.message = ""
			if model.fieldIndex < len(model.fields)-1 {
				model.fieldIndex++
				return model, model.fields[model.fieldIndex].input.Focus()
			}
			if err := model.finishArguments(); err != nil {
				model.message = err.Error()
				return model, nil
			}
			model.screen = confirmScreen
			return model, nil
		default:
			var command tea.Cmd
			model.fields[model.fieldIndex].input, command =
				model.fields[model.fieldIndex].input.Update(message)
			return model, command
		}
	case confirmScreen:
		switch message.String() {
		case "y", "Y", "s", "S":
			command, err := CommandFor(model.root, model.selected, model.args)
			if err != nil {
				model.message = err.Error()
				return model, nil
			}
			model.screen = runningScreen
			return model, tea.ExecProcess(command, func(err error) tea.Msg {
				return processFinishedMsg{err: err}
			})
		case "n", "N", "enter", "esc", "q", "ctrl+c":
			model.screen = browseScreen
			model.message = "Ejecución cancelada."
			return model, nil
		}
	case resultScreen:
		switch message.String() {
		case "enter", "esc", "q", "ctrl+c":
			return model, tea.Quit
		}
	}
	return model, nil
}

func (model *tuiModel) beginArguments() tea.Cmd {
	model.fields = makeFields(model.selected)
	model.fieldIndex = 0
	if len(model.fields) == 0 {
		model.args = nil
		model.screen = confirmScreen
		return nil
	}
	model.screen = argumentsScreen
	return model.fields[0].input.Focus()
}

func makeFields(script Script) []argumentField {
	var labels []argumentField
	switch script.Name {
	case "add-worktree.sh":
		labels = []argumentField{
			{label: "Nombre de la nueva rama", placeholder: "feature-name", required: true},
			{label: "Rama base", placeholder: "vacío = rama actual"},
		}
	case "backup-pc-work.sh", "backup-server.sh":
		labels = []argumentField{
			{label: "Directorio de origen", placeholder: "vacío = valor predeterminado"},
			{label: "Directorio de destino", placeholder: "vacío = valor predeterminado"},
		}
	case "harden-ubuntu26.sh":
		labels = []argumentField{
			{label: "Puerto SSH", placeholder: "22"},
		}
	}

	for index := range labels {
		input := textinput.New()
		input.Prompt = "> "
		input.Placeholder = labels[index].placeholder
		input.CharLimit = 1024
		input.Width = 48
		labels[index].input = input
	}
	return labels
}

func (model *tuiModel) finishArguments() error {
	values := make([]string, len(model.fields))
	for index := range model.fields {
		values[index] = model.fields[index].value
	}

	switch model.selected.Name {
	case "add-worktree.sh":
		model.args = append(model.args, values[0])
		if values[1] != "" {
			model.args = append(model.args, values[1])
		}
	case "backup-pc-work.sh", "backup-server.sh":
		if values[0] != "" {
			model.args = append(model.args, values[0])
		}
		if values[1] != "" {
			if values[0] == "" {
				home, err := os.UserHomeDir()
				if err != nil {
					return fmt.Errorf("leer directorio personal: %w", err)
				}
				model.args = append(model.args, home)
			}
			model.args = append(model.args, values[1])
		}
	case "harden-ubuntu26.sh":
		port := values[0]
		if port == "" {
			port = "22"
		}
		number, err := strconv.ParseUint(port, 10, 16)
		if err != nil || number == 0 {
			return fmt.Errorf("indica un puerto SSH entre 1 y 65535")
		}
		model.args = append(model.args, strconv.FormatUint(number, 10))
	}

	return ValidateScriptArgs(model.selected, model.args)
}

func (model *tuiModel) syncSelected() {
	selected, ok := model.list.SelectedItem().(scriptItem)
	if ok {
		if selected.script.Name != model.selected.Name {
			model.previewOffset = 0
		}
		model.selected = selected.script
	}
}

func (model *tuiModel) scrollPreview(direction int) {
	visibleLines := model.height - 18
	if visibleLines < 1 {
		visibleLines = 1
	}
	lines := strings.Split(model.selected.Source, "\n")
	maximumOffset := len(lines) - visibleLines
	if maximumOffset < 0 {
		maximumOffset = 0
	}
	model.previewOffset += direction * visibleLines
	if model.previewOffset < 0 {
		model.previewOffset = 0
	}
	if model.previewOffset > maximumOffset {
		model.previewOffset = maximumOffset
	}
}

func (model *tuiModel) resizeList() {
	if model.width < 1 || model.height < 1 {
		return
	}
	leftWidth := model.width * 38 / 100
	if leftWidth < 30 {
		leftWidth = 30
	}
	model.list.SetSize(leftWidth-4, model.height-7)
}

func (model *tuiModel) View() string {
	if model.width == 0 {
		return "Iniciando panel..."
	}

	header := titleStyle.Render("UTILIDADES DE DESARROLLO") + "\n" +
		mutedStyle.Render("Busca · revisa · ejecuta con confirmación")

	switch model.screen {
	case argumentsScreen:
		return model.renderForm(header)
	case confirmScreen:
		return model.renderConfirmation(header)
	case runningScreen:
		return header + "\n\n" + accentStyle.Render("Ejecutando "+model.selected.Name+"...") +
			"\n" + mutedStyle.Render("El control de la terminal se entrega temporalmente al script.")
	case resultScreen:
		return header + "\n\n" + model.resultView()
	default:
		return model.renderBrowser(header)
	}
}

func (model *tuiModel) renderBrowser(header string) string {
	leftWidth := model.width * 38 / 100
	if leftWidth < 30 {
		leftWidth = 30
	}
	rightWidth := model.width - leftWidth - 3
	if rightWidth < 24 {
		rightWidth = 24
		leftWidth = model.width - rightWidth - 3
	}
	panelHeight := model.height - 5
	if panelHeight < 8 {
		panelHeight = 8
	}
	model.list.SetSize(leftWidth-4, panelHeight-2)

	left := panelStyle.Width(leftWidth).Height(panelHeight).Render(model.list.View())
	detail := model.renderPreview(rightWidth-4, panelHeight-2)
	right := panelStyle.Width(rightWidth).Height(panelHeight).Render(detail)
	footer := "↑/↓ navegar · / filtrar · Ctrl+D/U desplazar código · Enter seleccionar · q salir"
	footerView := mutedStyle.Render(footer)
	if model.message != "" {
		footerView += "\n" + mutedStyle.Render(model.message)
	}
	return lipgloss.JoinVertical(lipgloss.Left, header, lipgloss.JoinHorizontal(lipgloss.Top, left, " ", right), footerView)
}

func (model *tuiModel) renderPreview(width, height int) string {
	title := accentStyle.Render(model.selected.Name)
	description := model.selected.Description
	warning := warningStyle.Render("Precaución: " + model.selected.Warning)
	previewHeight := height - 8
	if previewHeight < 1 {
		previewHeight = 1
	}
	allLines := strings.Split(model.selected.Source, "\n")
	maximumOffset := len(allLines) - previewHeight
	if maximumOffset < 0 {
		maximumOffset = 0
	}
	offset := model.previewOffset
	if offset > maximumOffset {
		offset = maximumOffset
	}
	end := offset + previewHeight
	if end > len(allLines) {
		end = len(allLines)
	}
	lines := allLines[offset:end]
	preview := make([]string, len(lines))
	for index, line := range lines {
		preview[index] = fmt.Sprintf("%3d  %s", offset+index+1, EscapeTerminalControls(line))
	}
	codeTitle := fmt.Sprintf("Código fuente · líneas %d–%d de %d", offset+1, end, len(allLines))
	content := strings.Join([]string{title, description, warning, mutedStyle.Render(codeTitle), strings.Join(preview, "\n")}, "\n\n")
	return lipgloss.NewStyle().Width(width).MaxHeight(height).Render(content)
}

func (model *tuiModel) renderForm(header string) string {
	field := model.fields[model.fieldIndex]
	parts := []string{
		header,
		"",
		accentStyle.Render(model.selected.Name),
		field.label,
		field.input.View(),
		mutedStyle.Render(fmt.Sprintf("Campo %d de %d · Enter continuar · Esc cancelar", model.fieldIndex+1, len(model.fields))),
	}
	if model.message != "" {
		parts = append(parts, warningStyle.Render(model.message))
	}
	return strings.Join(parts, "\n")
}

func (model *tuiModel) renderConfirmation(header string) string {
	command, err := CommandFor(model.root, model.selected, model.args)
	commandLine := model.selected.Name
	if err == nil {
		parts := make([]string, len(command.Args))
		for index, argument := range command.Args {
			parts[index] = strconv.Quote(argument)
		}
		commandLine = strconv.Quote(command.Path) + " " + strings.Join(parts[1:], " ")
	}
	parts := []string{
		header,
		"",
		accentStyle.Render("Confirmar ejecución"),
		"Script: " + model.selected.Name,
		model.selected.Description,
		warningStyle.Render("Precaución: " + model.selected.Warning),
		"Comando: " + commandLine,
		"",
		"¿Ejecutar? [s/N]",
	}
	if model.message != "" {
		parts = append(parts, mutedStyle.Render(model.message))
	}
	parts = append(parts, mutedStyle.Render("s confirmar · n/Esc cancelar"))
	return strings.Join(parts, "\n")
}

func (model *tuiModel) resultView() string {
	if model.runErr != nil {
		return warningStyle.Render(model.message) + "\n\n" + mutedStyle.Render("Pulsa Enter o q para salir.")
	}
	return accentStyle.Render(model.message) + "\n\n" + mutedStyle.Render("Pulsa Enter o q para salir.")
}

type processFinishedMsg struct {
	err error
}
