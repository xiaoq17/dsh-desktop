/**
 * Documentation TypeScript-fence gate.
 *
 * Rejects: a fenced code block whose info string is exactly `ts` in the
 * scanned Markdown (README.md, AGENTS.md, `docs/**`, `.agents/**`) that does
 * not compile as a strict NodeNext program. Blocks with `ts type-equiv`,
 * `ts public-api`, `tsconfig`, `json` or any other info string are exempt.
 */
import { existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scriptsDir = join(root, "scripts");

function walkMarkdown(dir: string, out: string[]): void {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (entry.name === "node_modules" || entry.name === ".data" || entry.name === "lib") continue;
		const full = join(dir, entry.name);
		if (entry.isDirectory()) walkMarkdown(full, out);
		else if (entry.name.endsWith(".md")) out.push(full);
	}
}

const markdownFiles: string[] = [];
for (const extra of ["README.md", "AGENTS.md"]) {
	const file = join(root, extra);
	if (existsSync(file)) markdownFiles.push(file);
}
for (const area of ["docs", ".agents"]) {
	const dir = join(root, area);
	if (existsSync(dir)) walkMarkdown(dir, markdownFiles);
}

const blocks: Array<{ file: string; index: number; code: string }> = [];
for (const file of markdownFiles) {
	const text = readFileSync(file, "utf8");
	let index = 0;
	for (const match of text.matchAll(/```([^\n]*)\n([\s\S]*?)```/g)) {
		if (match[1].trim() === "ts") blocks.push({ file, index: index++, code: match[2] });
	}
}

if (blocks.length === 0) {
	process.stdout.write("doc-typecheck: no compilable ts fences\n");
} else {
	// Compile every plain `ts` block as one strict NodeNext program so blocks
	// may reference each other and the dsk source plane.
	const tempFiles: string[] = [];
	const tempTsconfig = join(scriptsDir, ".tmp-doc-typecheck-tsconfig.json");
	try {
		for (const block of blocks) {
			const name = join(scriptsDir, `.tmp-doc-typecheck-${block.index}.ts`);
			writeFileSync(name, block.code, "utf8");
			tempFiles.push(name);
		}
		writeFileSync(
			tempTsconfig,
			JSON.stringify(
				{
					compilerOptions: {
						module: "nodenext",
						moduleResolution: "nodenext",
						target: "esnext",
						lib: ["esnext"],
						strict: true,
						noEmit: true,
						skipLibCheck: true,
						allowImportingTsExtensions: true,
						types: ["node"],
					},
					include: tempFiles.map((file) => relative(scriptsDir, file)),
				},
				null,
				2
			),
			"utf8"
		);

		const result = spawnSync(
			process.execPath,
			[join(root, "node_modules", "typescript", "bin", "tsc"), "-p", tempTsconfig],
			{ encoding: "utf8" }
		);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		const violations: string[] = [];
		for (const line of output.split("\n")) {
			const match = /error (TS\d+): (.+)$/.exec(line.trim());
			if (match) violations.push(`TS${match[1]} ${match[2]}`);
		}
		for (const block of blocks) {
			if (violations.length > 0) {
				process.stderr.write(`doc-typecheck: ${relative(root, block.file)} ts block #${block.index + 1} does not compile\n`);
			}
		}
		for (const violation of violations) process.stderr.write(`doc-typecheck: ${violation}\n`);
		if (violations.length > 0) process.exitCode = 1;
	} finally {
		for (const file of tempFiles) rmSync(file, { force: true });
		rmSync(tempTsconfig, { force: true });
	}
}
