package main

import (
	"github.com/urfave/cli"
)

func HookPreCommitEnable(args []string) (string, error) {
	return "git seekret hook --run pre-commit\n", nil
}

func HookPreCommitDisable(args []string) error {
	return nil
}

func HookPreCommitRun(args []string) error {
	options := map[string]interface{}{
		"commit-files": false,
		"staged-files": true,
	}

	secrets, err := gs.RunCheck(options)
	if err != nil {
		return err
	}
	if secrets != 0 {
		return cli.NewExitError("commit cannot proceed", 42)
	}

	return nil
}
