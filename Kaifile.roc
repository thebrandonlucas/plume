# Product checks use the current nightly on PATH. Released automation tools
# and the compiler that runs scripts have independent, reviewed lock entries
# in .kai/lock.json. Everything here is a pinned download or a program the
# machine must have, so Kai serves it without Nix.
app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.11/65bk6qdahqxn1mm6LR6Hkyw8dSdoeRZGwjNSuiPfvguP.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.11/std-6Jw5GxNCFkpnvBbnFmQg4KAVEn5bAfEveSZfDSzTDs42.tar.zst",
}

import std.Std

systems = ["x86_64-linux", "aarch64-linux", "aarch64-darwin"]

## A Roc nightly's compiler, for each system this project declares.
roc_nightly = |tag| {
	date = tag.drop_prefix("nightly-")
	file = |system, build| {
		top = "roc_nightly-${build}-${date}"
		{
			system,
			url: "https://github.com/roc-lang/nightlies/releases/download/${tag}/${top}.tar.gz",
			mirrors: [],
			program: Archive("${top}/roc"),
		}
	}
	[
		file("x86_64-linux", "linux_x86_64"),
		file("aarch64-linux", "linux_arm64"),
		file("aarch64-darwin", "macos_apple_silicon"),
	]
}

## A released file for each system this project declares, named by the system.
per_system = |prefix|
	systems.map(|system| { system, url: "${prefix}${system.to_str()}", mirrors: [], program: File })

tools = "https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0"

kaifile = Std.kaifile([
	Name("plume"),
	Systems(systems),
	FetchLocked("roc-stable", roc_nightly("nightly-2026-10-18-1df370f")),
	FetchLocked("release-package", per_system("${tools}/release-package-")),
	FetchLocked("roc-policy", per_system("${tools}/roc-policy-")),
	FetchLocked("roc-docs", per_system("${tools}/roc-docs-")),
	Environment("package", [Tools(["roc-stable#roc-stable", "release-package#release-package", "roc-policy#roc-policy"]), Expect(["roc"])]),
	Environment("release", [Tools(["release-package#release-package"]), Expect(["roc", "git", "gh", "tar", "unzip", "zip", "chmod", "touch", "env"])]),
	Environment("release-test", [Tools(["release-package#release-package"]), Expect(["roc"])]),
	Environment("docs", [Tools(["roc-docs#roc-docs"]), Expect(["sh", "realpath", "roc"])]),
	Environment("screenshots", [Tools(["roc-stable#roc-stable"]), Expect(["roc", "node", "npm"])]),
	Shell("default", [Use("package")]),
	Task("check", [Use("package"), Run(["roc-stable", "scripts/check.roc"])]),
	# roc-policy reads repository_policy from Blueprint.roc unless told otherwise,
	# so it is pointed at this file.
	Task("policy", [Use("package"), Run(["roc-policy", "check", "--root", ".", "--config", "Kaifile.roc"])]),
	Task("api-docs", [Use("package"), Run(["roc", "docs", "package/main.roc", "--output=generated-docs"])]),
	Task("screenshots-setup", [Use("screenshots"), Run(["node", "tools/screenshots/setup.mjs"])]),
	Task("screenshots", [Use("screenshots"), Run(["node", "tools/screenshots/run.mjs"])]),
	Task("screenshots-update", [Use("screenshots"), Run(["node", "tools/screenshots/run.mjs", "--update"])]),
	Task("test", [Use("package"), Run(["roc", "test", "--opt=dev", "package/main.roc"])]),
	Task("type-safety", [Use("package"), Run(["roc-stable", "scripts/type_safety.roc"])]),
	Task("release-package", [Use("release"), Run(["release-package"])]),
	Task("release-test", [Use("release-test"), Run(["release-package"])]),
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "plume.pdf", "--api-entrypoint", "package/main.roc", "--roc-command", "roc", "--site-url", "https://lukewilliamboswell.github.io/plume/"])]),
	Task("docs-path", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
])

# The embedded profile checks attached documentation on the complete public
# nominal surface. Fail incomplete scans rather than accepting missing coverage.
repository_policy = {
	schema_version: 2,
	roots: ["package"],
	test_roots: ["package"],
	profiles: [{ name: "base", builtin: "roc-package", version: 1 }],
	rules: [],
	overrides: [
		{
			rule: "base/public_docs",
			reason: "The public package modules must be present in every policy scan.",
			changes: { require_match: True },
		},
	],
}
