package main

import (
	"fmt"
	"os"
	"path/filepath"

	"nfsrun-server/internal/config"
	"nfsrun-server/internal/launcherpreset"
	"nfsrun-server/internal/server"
)

// stampLauncher writes a copy of the launcher exe with this server built in:
// launcher address, certificate pin and the Redirector domain the launcher
// patches into its game copy. Players then configure nothing.
func stampLauncher(cfgPath, in, out string) int {
	c, err := config.Load(cfgPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		return 2
	}
	url, pin, created, err := server.LauncherClientConfig(c)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if created {
		fmt.Fprintln(os.Stderr, "created self-signed launcher certificate", c.LauncherTLSCert)
	}
	domain, _, _, _, err := certTarget(c, "", "")
	if err != nil {
		fmt.Fprintf(os.Stderr, "no Redirector domain (%v): players must patch their game exe themselves\n", err)
		domain = ""
	}
	exe, err := os.ReadFile(in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "launcher:", err)
		return 1
	}
	if a, _ := filepath.Abs(in); a != "" {
		if b, _ := filepath.Abs(out); a == b {
			fmt.Fprintln(os.Stderr, "--stamp-launcher: write to another file, not over the original launcher")
			return 2
		}
	}
	stamped, err := launcherpreset.Stamp(exe, launcherpreset.Preset{ServerHTTP: url, Pin: pin, Domain: domain})
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", in, err)
		return 1
	}
	if err := os.WriteFile(out, stamped, 0755); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("SERVER_HTTP=%s\n", url)
	fmt.Printf("SERVER_CERT_PIN=%s\n", pin)
	fmt.Printf("BASE_DOMAIN=%s\n", domain)
	fmt.Fprintf(os.Stderr, "launcher with this server built in: %s\n", out)
	return 0
}
