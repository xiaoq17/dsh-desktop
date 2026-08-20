/**
 * Markdown link-integrity gate.
 *
 * Rejects: any `[text](target)`/`![alt](target)` in the repo's OWN Markdown —
 * root README/AGENTS, `docs/spec/**`, `docs/concept.md`, package/app READMEs,
 * and Agent Notes under `.agents/notes/{proposed,implemented,rejected}/` —
 * whose relative path does not resolve, or whose `#fragment` does not match a
 * GitHub-style slug of an ATX heading (or an explicit `{#anchor}`) in the
 * target file. Links inside fenced code blocks are ignored.
 *
 * Scoped to owned docs: `docs/AGENTS.md`, `docs/development.md`,
 * `docs/testing.md`, `docs/cordis-primer.md`, `docs/defensive-patterns.md`,
 * `docs/glossary.md`, `docs/cookbook/`, `docs/postmortem/` and
 * `.agents/skills/**` are vendored from deepseek-harness (see S-0001 §1) and
 * reference that repo's internal docs; they are not enforced here.
 */
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Vendored external docs excluded from enforcement — none in this repo. */
const VENDORED_PREFIXES: string[] = [];

function isVendored(file: string): boolean {
	const rel = relative(root, file);
	return VENDORED_PREFIXES.some((prefix) => rel === prefix || rel.startsWith(prefix));
}

function walkMarkdown(dir: string, out: string[]): void {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (entry.name === "node_modules" || entry.name === ".data" || entry.name === "lib") continue;
		const full = join(dir, entry.name);
		if (isVendored(full)) continue;
		if (entry.isDirectory()) walkMarkdown(full, out);
		else if (entry.name.endsWith(".md")) out.push(full);
	}
}

const markdownFiles: string[] = [];
for (const extra of ["README.md", "AGENTS.md"]) {
	const file = join(root, extra);
	if (existsSync(file)) markdownFiles.push(file);
}
// Owned docs: everything under docs/ and plugins/; Agent Notes (lifecycle
// tree only — not the scaffolding READMEs).
for (const area of ["docs", "plugins"]) {
	const dir = join(root, area);
	if (existsSync(dir)) walkMarkdown(dir, markdownFiles);
}
for (const lifecycle of ["proposed", "implemented", "rejected"]) {
	const dir = join(root, ".agents", "notes", lifecycle);
	if (existsSync(dir)) walkMarkdown(dir, markdownFiles);
}

/** Remove fenced code blocks, inline code, and HTML comments. */
function stripNoise(text: string): string {
	return text
		.replace(/```[\s\S]*?```/g, "")
		.replace(/`[^`]*`/g, "")
		.replace(/<!--[\s\S]*?-->/g, "");
}

function slugify(text: string): string {
	return text
		.toLowerCase()
		.replace(/[^\p{L}\p{N}\s_-]/gu, "")
		.replace(/\s+/g, "-")
		.replace(/-+/g, "-")
		.replace(/^-+|-+$/g, "");
}

interface Heading {
	slug: string;
	explicit?: string;
}

function headingsOf(text: string): Heading[] {
	const headings: Heading[] = [];
	let inFence = false;
	for (const line of text.split("\n")) {
		if (line.trim().startsWith("```")) {
			inFence = !inFence;
			continue;
		}
		if (inFence) continue;
		const match = /^#{1,6}\s+(.*)$/.exec(line);
		if (!match) continue;
		const explicitMatch = /\{#([^}]+)\}/.exec(match[1]);
		// GitHub-style slugs keep inline-code text (backticks stripped), so keep
		// the content and only remove the punctuation/syntax characters.
		const title = match[1].replace(/\{#[^}]+\}/, "").replace(/`([^`]*)`/g, "$1");
		headings.push({ slug: slugify(title), explicit: explicitMatch?.[1] });
	}
	return headings;
}

const linkPattern = /!?\[[^\]]*\]\(([^)]+)\)/g;

const violations: string[] = [];
for (const file of markdownFiles) {
	const dir = dirname(file);
	const source = stripNoise(readFileSync(file, "utf8"));
	for (const match of source.matchAll(linkPattern)) {
		let target = match[1].trim();
		if (target.startsWith("<") && target.endsWith(">")) target = target.slice(1, -1);
		target = target.replace(/\s+"[^"]*"$/, "").trim();
		if (target === "") continue;
		if (/^(https?:|mailto:|tel:)/.test(target)) continue;
		if (target.startsWith("#")) continue; // bare same-document anchor

		const hashIndex = target.indexOf("#");
		const path = hashIndex === -1 ? target : target.slice(0, hashIndex);
		const fragment = hashIndex === -1 ? "" : target.slice(hashIndex + 1);

		let resolved = resolve(dir, path);
		if (!existsSync(resolved)) {
			violations.push(`${relative(root, file)} → ${target}`);
			continue;
		}
		let targetFile = resolved;
		if (statSync(resolved).isDirectory()) {
			const inside = [join(resolved, "README.md"), join(resolved, "index.md")].find(existsSync);
			if (inside === undefined) {
				violations.push(`${relative(root, file)} → ${target} (directory without README.md/index.md)`);
				continue;
			}
			targetFile = inside;
		}
		if (fragment === "" || !targetFile.endsWith(".md")) continue;

		const headings = headingsOf(readFileSync(targetFile, "utf8"));
		const found = headings.some((h) => h.slug === fragment || h.explicit === fragment);
		if (!found) violations.push(`${relative(root, file)} → ${target}`);
	}
}

for (const violation of violations) process.stderr.write(`broken link: ${violation}\n`);
if (violations.length > 0) process.exitCode = 1;
