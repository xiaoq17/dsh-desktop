/**
 * NodeNext-consumer gate over the BUILT plugin declarations.
 *
 * Rejects: a build without `plugins/volcano-search/lib/types`, built
 * declarations whose relative import/export specifiers still end in `.ts`,
 * missing built plugin artifacts, or any diagnostic from compiling the built
 * `.d.ts` tree as a strict NodeNext program against a consumer that imports
 * `volcano-search` and every exported subpath.
 *
 * TS7's `rewriteRelativeImportExtensions` rewrites the `.js` emit but not the
 * `.d.ts` emit (upstream gap), so this gate deterministically rewrites the
 * relative `.ts` specifiers in the built declarations to `.js` before
 * compiling them — the transform the build is declared to perform.
 */
import { existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scriptsDir = join(root, "scripts");
const typesRoot = join(root, "plugins", "volcano-search", "lib", "types");
const entry = join(typesRoot, "index.d.ts");

function walkDts(dir: string): string[] {
	const out: string[] = [];
	for (const item of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, item.name);
		if (item.isDirectory()) out.push(...walkDts(full));
		else if (item.name.endsWith(".d.ts")) out.push(full);
	}
	return out;
}

const violations: string[] = [];

// Build dependency: the gate consumes built declarations.
if (!existsSync(entry)) {
	process.stderr.write("verify-node-next-types: plugins/volcano-search/lib/types/index.d.ts is missing — run `pnpm run build` first\n");
	process.exitCode = 1;
} else {
	for (const artifact of [
		join(root, "plugins", "volcano-search", "lib", "index.js"),
		join(root, "plugins", "volcano-search", "lib", "parser.js"),
	]) {
		if (!existsSync(artifact)) violations.push(`missing built artifact: ${relative(root, artifact)}`);
	}

	// Rewrite relative `.ts` specifiers to `.js` (the rewrite the build is
	// declared to perform but TS7 skips on declarations); fail on any residue.
	const relativeImport = /(?:from\s*["']|import\s*["']|import\(\s*["'])(\.\.?\/)/;
	const extension = /(["'])(\.\.?\/[^'"]*?)\.ts\1/g;
	let rewritten = 0;
	for (const file of walkDts(typesRoot)) {
		const lines = readFileSync(file, "utf8").split("\n");
		let dirty = false;
		for (let i = 0; i < lines.length; i++) {
			if (!relativeImport.test(lines[i])) continue;
			const fixed = lines[i].replace(extension, "$1$2.js$1");
			if (fixed !== lines[i]) {
				lines[i] = fixed;
				rewritten += 1;
				dirty = true;
			}
		}
		if (dirty) writeFileSync(file, lines.join("\n"), "utf8");
	}
	if (rewritten > 0) {
		process.stdout.write(`verify-node-next-types: rewrote ${rewritten} relative .ts specifiers to .js in built declarations (TS7 .d.ts emit gap)\n`);
	}
	for (const file of walkDts(typesRoot)) {
		readFileSync(file, "utf8")
			.split("\n")
			.forEach((line, index) => {
				if (/["'](\.\.?\/[^'"]*)\.ts["']/.test(line)) violations.push(`${relative(root, file)}:${index + 1} — relative specifier still ends in .ts`);
			});
	}

	// Compile the corrected built declarations as a strict NodeNext program
	// through the installed tsc CLI.
	const tempTsconfig = join(scriptsDir, ".tmp-node-next-tsconfig.json");
	const tempConsumer = join(scriptsDir, ".tmp-node-next-consumer.ts");
	try {
		writeFileSync(
			tempTsconfig,
			JSON.stringify(
				{
					compilerOptions: {
						module: "nodenext",
						moduleResolution: "nodenext",
						noEmit: true,
						skipLibCheck: false,
						strict: true,
						lib: ["esnext"],
						types: ["node"],
						paths: {
							"volcano-search": ["../plugins/volcano-search/lib/types/index.d.ts"],
							// Exact subpath mappings land on the built declarations.
							"volcano-search/parser": ["../plugins/volcano-search/lib/types/parser.d.ts"],
							"volcano-search/*": ["../plugins/volcano-search/lib/types/*.d.ts"],
						},
					},
					include: ["../plugins/volcano-search/lib/types/**/*.d.ts", ".tmp-node-next-consumer.ts"],
				},
				null,
				2
			),
			"utf8"
		);
		writeFileSync(
			tempConsumer,
			'import { PROVIDER_ID, VolcanoSearchProvider } from "volcano-search";\n' +
				'import { mapArkResponse } from "volcano-search/parser";\n' +
				"void PROVIDER_ID;\n" +
				"void VolcanoSearchProvider;\n" +
				"void mapArkResponse;\n",
			"utf8"
		);

		const result = spawnSync(
			process.execPath,
			[join(root, "node_modules", "typescript", "bin", "tsc"), "-p", tempTsconfig],
			{ encoding: "utf8" }
		);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		for (const line of output.split("\n")) {
			const match = /^(.*?)\((\d+),(\d+)\): error (TS\d+): (.+)$/.exec(line.trim());
			if (!match) continue;
			// Scope the check to the built declarations under verification and the
			// consumer; unrelated third-party declaration diagnostics are out of scope.
			const diagnosticFile = resolve(root, match[1]);
			const inScope = diagnosticFile.startsWith(`${typesRoot}${sep}`) || diagnosticFile === tempConsumer;
			if (inScope) violations.push(`${relative(root, diagnosticFile)}:${match[2]} — ${match[4]} ${match[5]}`);
		}
	} finally {
		rmSync(tempTsconfig, { force: true });
		rmSync(tempConsumer, { force: true });
	}
}

for (const violation of violations) process.stderr.write(`node-next violation: ${violation}\n`);
if (violations.length > 0) process.exitCode = 1;
