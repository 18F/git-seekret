package main_test

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	. "github.com/onsi/gomega/gexec"
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


var _ = Describe("main", func() {
	Describe("showing the help menu", func() {
		Context("when no arguments are provided", func() {
			It("should show the help for the command", func() {
				process := GitSeekret()
				//Eventually(string(process.Out.Contents())).Should(ContainSubstring("git-seekret [global options] command [command options] [arguments...]"))
				//Eventually(string(process.Out.Contents())).Should(ContainSubstring("config   manage configuration seetings"))
				//Eventually(string(process.Out.Contents())).Should(ContainSubstring("rules    manage rules"))
				//Eventually(string(process.Out.Contents())).Should(ContainSubstring("check    inspect git repository"))
				//Eventually(string(process.Out.Contents())).Should(ContainSubstring("hook     manage git hooks"))
				//Eventually(string(process.Out.Contents())).Should(ContainSubstring("help, h  Shows a list of commands or help for one command"))
				Eventually(process).Should(Exit(0))
			})
		})
		Context("when the -h flag is provided", func () {

		})
	})

})

func GitSeekret(args ...string) *Session {
	cmd := exec.Command("git", append([]string{"seekret"}, args...)...)
	cmd.Env = []string{filepath.Dir(exePath)}
	session, err := Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	session.Wait()
	Expect(session.Command.Args).To(ConsistOf([]string{"git", "seekret"}))
	//Eventually(string(session.Err.Contents())).Should(Equal(""))
	Expect(session.Command.Env).To(ConsistOf([]string{}))

	return session
}
