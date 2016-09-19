package main_test

import (
	. "github.com/apuigsech/git-seekret"
	"github.com/libgit2/git2go"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	. "github.com/onsi/gomega/gexec"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
)

var exePath string

var _ = SynchronizedBeforeSuite(func() []byte {
	path, buildErr := Build("github.com/apuigsech/git-seekret")
	Expect(buildErr).NotTo(HaveOccurred())
	return []byte(path)
}, func(data []byte) {
	exePath = string(data)
})

// gexec.Build leaves a compiled binary behind in /tmp.
var _ = SynchronizedAfterSuite(func() {}, func() {
	CleanupBuildArtifacts()
})

var helpName = `NAME:
   git-seekret - prevent from committing sensitive information into git repository

USAGE:
   git-seekret [global options] command [command options] [arguments...]`

var helpVersion = `
VERSION:
   0.0.1`

var helpAuthor = `
AUTHOR(S):
   Albert Puigsech Galicia <albert@puigsech.com>`

var helpCommands = `COMMANDS:
     config   manage configuration seetings
     rules    manage rules
     check    inspect git repository
     hook     manage git hooks
     help, h  Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --global`

var _ = Describe("main", func() {
	var repoDir string
	var oldDir string
	BeforeEach(func() {
		// Create a directory
		var err error
		repoDir, err = ioutil.TempDir("", "repo")
		Expect(err).NotTo(HaveOccurred())
		// Go to the directory and save the old directory
		oldDir, err = os.Getwd()
		Expect(err).NotTo(HaveOccurred())
		err = os.Chdir(repoDir)
		Expect(err).NotTo(HaveOccurred())
		// Run `git init`
		cmd := exec.Command("git", "init")
		session, err := Start(cmd, GinkgoWriter, GinkgoWriter)
		Eventually(session).Should(Exit(0))
		Expect(err).NotTo(HaveOccurred())
		Eventually(string(session.Out.Contents())).Should(ContainSubstring("Initialized empty Git repository in "))
	})
	AfterEach(func() {
		// Remove the temp git directory
		os.RemoveAll(repoDir)
		// Go back to the old directory
		err := os.Chdir(oldDir)
		Expect(err).NotTo(HaveOccurred())
	})
	Describe("help", func() {
		Context("when no arguments are provided", func() {

			It("should show the help for the command", func() {
				process := GitSeekret()
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpName))
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpVersion))
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpAuthor))
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpCommands))
			})
		})
		Context("when the -h flag is provided", func() {
			It("should show the help for the command", func() {
				process := GitSeekret("-h")
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpName))
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpVersion))
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpAuthor))
				Eventually(string(process.Out.Contents())).Should(ContainSubstring(helpCommands))
			})
		})
	})
	Describe("config", func() {
		Context("when it has not been configured", func() {
			It("should show a warning that it has been configured", func() {
				process := GitSeekret("config")
				Eventually(string(process.Out.Contents())).Should(Equal(""))
				Eventually(string(process.Err.Contents())).Should(Equal("Config not initialised - Try: 'git-seekret config --init'\n"))
			})
		})
		Context("when it initialized to a config locally", func() {
			It("should create the config for the local config.", func() {
				rulesPath := filepath.Join(os.Getenv("HOME"), ".seekret_rules")
				InitLocalConfig(rulesPath, repoDir)
			})
			It("should create the config for the local config with the rules in a custom location by supplying SEEKRET_RULES_PATH.", func() {
				rulesDir := CreateCustomRulesPath()
				defer os.RemoveAll(rulesDir)

				InitLocalConfig(rulesDir, repoDir)
			})
		})
	})
	Describe("rules", func() {
		Context("with a configured repository", func() {
			var rulesDir string
			BeforeEach(func() {
				rulesDir = CreateCustomRulesPath()
				InitLocalConfig(rulesDir, repoDir)
			})
			AfterEach(func() {
				os.RemoveAll(rulesDir)
			})
			It("should nothing when there are no rules in the directory", func() {
				process := GitSeekret("rules")
				VerifyRules(process, []string{})

			})
			It("should show rules when there are rules in the rules directory", func() {
				CopyRuleFixtures(oldDir, rulesDir)
				process := GitSeekret("rules")
				VerifyRules(process, []string{"[ ] password.password", "[ ] password.pwd", "[ ] password.pass", "[ ] password.cred"})
			})
			It("should allow for rules to be enabled", func() {
				CopyRuleFixtures(oldDir, rulesDir)
				process := GitSeekret("rules", "--enable", "password.pwd")
				VerifyRules(process, []string{"[ ] password.password", "[x] password.pwd", "[ ] password.pass", "[ ] password.cred"})
			})
			It("should allow for rules to be disabled", func() {
				CopyRuleFixtures(oldDir, rulesDir)
				process := GitSeekret("rules", "--enable", "password.pwd")
				VerifyRules(process, []string{"[ ] password.password", "[x] password.pwd", "[ ] password.pass", "[ ] password.cred"})
				process = GitSeekret("rules", "--disable", "password.pwd")
				VerifyRules(process, []string{"[ ] password.password", "[ ] password.pwd", "[ ] password.pass", "[ ] password.cred"})
			})
		})
	})
})

func CopyRuleFixtures(oldDir, rulesDir string) {
	CopyFile(filepath.Join(oldDir, "fixtures", "rules", "password.rule"), filepath.Join(rulesDir, "password.rule"))
}

func VerifyRules(process *Session, rules []string) {
	Eventually(string(process.Out.Contents())).Should(ContainSubstring("List of rules:"))
	for _, rule := range rules {
		Eventually(string(process.Out.Contents())).Should(ContainSubstring(rule))
	}
}

func CopyFile(srcFile string, destFile string) {
	b, err := ioutil.ReadFile(srcFile)
	Expect(err).NotTo(HaveOccurred())
	err = ioutil.WriteFile(destFile, b, 0644)
	Expect(err).NotTo(HaveOccurred())
}

func CreateCustomRulesPath() string {
	By("creating the SEEKRET_RULES_PATH folder")
	rulesDir, err := ioutil.TempDir("", "repo")
	Expect(err).NotTo(HaveOccurred())

	By("setting the SEEKRET_RULES_PATH")
	err = os.Setenv("SEEKRET_RULES_PATH", rulesDir)
	Expect(err).NotTo(HaveOccurred())
	return rulesDir
}

func InitLocalConfig(rulesPath string, repoDir string) {
	By("calling the config --init and checking the output")
	process := GitSeekret("config", "--init")
	CheckConfigStdOut(process, rulesPath)

	By("checking the local git config")
	config, err := GetLocalGitConfig(repoDir)
	Expect(err).NotTo(HaveOccurred())
	defer config.Free()
	// Check the config file
	CheckConfigFile(config, rulesPath)

	By("calling config again, it should just print out the config again.")
	process = GitSeekret("config")
	CheckConfigStdOut(process, rulesPath)
}

func GitSeekret(args ...string) *Session {
	cmd := exec.Command(exePath, args...)
	session, err := Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	session.Wait()
	return session
}

// CheckConfigStdOut checks the output for commands that simply just print out the config.
func CheckConfigStdOut(process *Session, rulesPath string) {
	Eventually(string(process.Out.Contents())).Should(ContainSubstring("Config:"))
	Eventually(string(process.Out.Contents())).Should(ContainSubstring("version = 1"))
	Eventually(string(process.Out.Contents())).Should(ContainSubstring("rulespath = " + rulesPath))
	Eventually(string(process.Out.Contents())).Should(ContainSubstring("rulesenabled ="))
	Eventually(string(process.Out.Contents())).Should(ContainSubstring("exceptionsfile ="))
	Eventually(string(process.Err.Contents())).Should(Equal(""))
}

func CheckConfigFile(config *git.Config, rulesPath string) {
	version, err := config.LookupString("gitseekret.version")
	Expect(err).NotTo(HaveOccurred())
	Expect(version).To(Equal("1"))
	rulepath, err := config.LookupString("gitseekret.rulespath")
	Expect(err).NotTo(HaveOccurred())
	Expect(rulepath).To(Equal(rulesPath))
	rulesenabled, err := config.LookupString("gitseekret.rulesenabled")
	Expect(err).NotTo(HaveOccurred())
	Expect(rulesenabled).To(Equal(""))
	exceptionsfile, err := config.LookupString("gitseekret.exceptionsfile")
	Expect(err).NotTo(HaveOccurred())
	Expect(exceptionsfile).To(Equal(""))
}
