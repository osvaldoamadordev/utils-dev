package main

import (
	"fmt"
	"os"

	"github.com/osvaldoamadordev/utils-dev/internal/panel"
)

func main() {
	if err := panel.NewRootCommand().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
