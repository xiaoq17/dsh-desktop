/**
 * Documentation word-budget gate.
 *
 * Rejects: a manifest entry whose file does not exist, or a document whose
 * word count (code blocks, tables and HTML comments stripped) exceeds its
 * ceiling in `scripts/doc-budgets.manifest.json`.
 */
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = join(root, "scripts", "doc-budgets.manifest.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
	defaultCeiling: number;
	documents: Record<string, number>;
};

function wordCount(file: string): number {
	const text = readFileSync(file, "utf8")
		.replace(/```[\s\S]*?```/g, "")
		.replace(/<!--[\s\S]*?-->/g, "");
	const withoutTables = text.split("\n").filter((line) => !line.includes("|"));
	return withoutTables.join(" ").split(/\s+/).filter(Boolean).length;
}

const violations: string[] = [];
const rows: string[] = [];
for (const [doc, ceiling] of Object.entries(manifest.documents)) {
	const file = join(root, doc);
	if (!existsSync(file)) {
		violations.push(`MISSING ${doc} — listed in the manifest but no such file`);
		continue;
	}
	const count = wordCount(file);
	rows.push(`${doc}: ${count} words (ceiling ${ceiling})`);
	if (count > ceiling) violations.push(`${doc} exceeds ceiling: ${count} > ${ceiling}`);
}

for (const row of rows) process.stdout.write(`doc-budgets: ${row}\n`);
for (const violation of violations) process.stderr.write(`doc-budget violation: ${violation}\n`);
if (violations.length > 0) process.exitCode = 1;
