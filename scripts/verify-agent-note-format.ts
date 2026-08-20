/**
 * Agent Note header/skeleton gate.
 *
 * Rejects: a note under `.agents/notes/{proposed,implemented,rejected}/` whose
 * first line is not `# Agent Note: …`, whose status line does not match
 * `Status: proposed|implemented|rejected — …`, whose third line is not blank,
 * whose lifecycle folder disagrees with the status token, or whose body lacks
 * a `## Problem` heading. No notes present is a pass.
 */
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const notesRoot = join(root, ".agents", "notes");
const lifecycleDirs = ["proposed", "implemented", "rejected"];

function walkMarkdown(dir: string, out: string[]): void {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) walkMarkdown(full, out);
		else if (entry.name.endsWith(".md")) out.push(full);
	}
}

const noteFiles: string[] = [];
for (const lifecycle of lifecycleDirs) {
	const dir = join(notesRoot, lifecycle);
	if (existsSync(dir)) walkMarkdown(dir, noteFiles);
}

if (noteFiles.length === 0) {
	process.stdout.write("verify-agent-note-format: no agent notes found — nothing to check\n");
} else {
	const violations: string[] = [];
	for (const file of noteFiles) {
		const lines = readFileSync(file, "utf8").split("\n");
		const parts = dirname(file).split(/[\\/]/);
		// Lifecycle is the parent of the class folder: {lifecycle}/{class}/file.md.
		const folder = parts[parts.length - 2] ?? "";
		const rel = relative(root, file);
		if (lines.length === 0 || !/^# Agent Note: .+/.test(lines[0])) {
			violations.push(`${rel}:1 — expected "# Agent Note: …"`);
		}
		const statusMatch = /^Status: (proposed|implemented|rejected(?: — .+)?)$/.exec(lines[1] ?? "");
		if (!statusMatch) {
			violations.push(`${rel}:2 — expected "Status: proposed|implemented|rejected — …"`);
		} else {
			const token = statusMatch[1].split(/\s/)[0];
			if (token !== folder) violations.push(`${rel} — Status token "${token}" disagrees with folder "${folder}"`);
		}
		if ((lines[2] ?? "").trim() !== "") {
			violations.push(`${rel}:3 — expected a blank line after the status`);
		}
		if (!lines.slice(3).some((line) => /^##\s+Problem\b/.test(line))) {
			violations.push(`${rel} — body has no "## Problem" heading`);
		}
	}
	for (const violation of violations) process.stderr.write(`agent-note violation: ${violation}\n`);
	if (violations.length > 0) process.exitCode = 1;
}
