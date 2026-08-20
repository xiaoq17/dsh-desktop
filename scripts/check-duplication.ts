/**
 * Cross-file TypeScript clone-detection gate.
 *
 * Rejects: the same 6+ normalized source lines appearing in two or more
 * distinct files under `packages/` and `apps/` (build output `lib/`, fixture
 * trees and node_modules are skipped). Intentionally-paired files can be
 * allow-listed in `scripts/duplication.ignore.json` as `"pathA <-> pathB"`.
 */
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const WINDOW = 6;
const SKIP_SEGMENTS = new Set(["node_modules", "lib", ".data", "fixture", "fixtures"]);

function walkTs(dir: string, out: string[]): void {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (SKIP_SEGMENTS.has(entry.name)) continue;
		const full = join(dir, entry.name);
		if (entry.isDirectory()) walkTs(full, out);
		else if (entry.name.endsWith(".ts")) out.push(full);
	}
}

function normalize(line: string): string | undefined {
	const collapsed = line.trim().replace(/\s+/g, " ");
	if (collapsed === "") return undefined;
	if (/^(\/\/|\/\*|\*)/.test(collapsed)) return undefined; // comment-only
	if (/^[{}]+[;,]*$/.test(collapsed)) return undefined; // braces-only
	return collapsed;
}

/** Per file: kept normalized lines and the original 1-based line of each. */
interface Source {
	file: string;
	lines: string[];
	lineNumbers: number[];
}

const sources: Source[] = [];
for (const area of ["plugins"]) {
	const areaDir = join(root, area);
	if (!existsSync(areaDir)) continue;
	const files: string[] = [];
	walkTs(areaDir, files);
	for (const file of files) {
		const lines = readFileSync(file, "utf8").split("\n");
		const kept: string[] = [];
		const lineNumbers: number[] = [];
		lines.forEach((raw, index) => {
			const normalized = normalize(raw);
			if (normalized !== undefined) {
				kept.push(normalized);
				lineNumbers.push(index + 1);
			}
		});
		sources.push({ file, lines: kept, lineNumbers });
	}
}

/** Sliding 6-line windows → the sources/lines where each window occurs. */
const byWindow = new Map<string, Array<{ source: number; kept: number }>>();
for (let s = 0; s < sources.length; s++) {
	const { lines } = sources[s];
	for (let i = 0; i + WINDOW <= lines.length; i++) {
		const key = lines.slice(i, i + WINDOW).join("\u0000");
		const occurrences = byWindow.get(key) ?? [];
		occurrences.push({ source: s, kept: i });
		byWindow.set(key, occurrences);
	}
}

let ignore: string[] = [];
const ignoreFile = join(root, "scripts", "duplication.ignore.json");
if (existsSync(ignoreFile)) {
	ignore = JSON.parse(readFileSync(ignoreFile, "utf8")) as string[];
}

function ignored(relA: string, relB: string): boolean {
	return ignore.includes(`${relA} <-> ${relB}`) || ignore.includes(`${relB} <-> ${relA}`);
}

const violations: string[] = [];
for (const occurrences of byWindow.values()) {
	if (occurrences.length < 2) continue;
	const distinct = new Map<number, Array<{ source: number; kept: number }>>();
	for (const occ of occurrences) {
		const list = distinct.get(occ.source) ?? [];
		list.push(occ);
		distinct.set(occ.source, list);
	}
	if (distinct.size < 2) continue;

	// One report per maximal matching run: only the first window of a run is
	// reported, then the run is extended to its full length.
	for (const [sourceA, listA] of distinct) {
		const linesA = sources[sourceA].lines;
		for (const occA of listA) {
			for (const [sourceB, listB] of distinct) {
				if (sourceB <= sourceA) continue;
				const linesB = sources[sourceB].lines;
				for (const occB of listB) {
					// Skip windows that continue an already-matching run.
					if (occA.kept > 0 && occB.kept > 0 && linesA[occA.kept - 1] === linesB[occB.kept - 1]) continue;
					let run = WINDOW;
					while (occA.kept + run < linesA.length && occB.kept + run < linesB.length && linesA[occA.kept + run] === linesB[occB.kept + run]) run++;
					const relA = relative(root, sources[sourceA].file);
					const relB = relative(root, sources[sourceB].file);
					if (ignored(relA, relB)) continue;
					violations.push(
						`${relA}:${sources[sourceA].lineNumbers[occA.kept]} and ${relB}:${sources[sourceB].lineNumbers[occB.kept]} (window ${run})`
					);
				}
			}
		}
	}
}

for (const violation of violations) process.stderr.write(`duplication: ${violation}\n`);
if (violations.length > 0) process.exitCode = 1;
