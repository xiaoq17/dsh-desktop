/**
 * clean — remove build outputs and safe residue.
 */
import { rm } from "node:fs/promises";

const targets = [
	"plugins/volcano-search/lib",
	"plugins/volcano-search/tsconfig.tsbuildinfo",
	"coverage",
	"node_modules/.cache",
];

for (const target of targets) {
	await rm(target, { recursive: true, force: true });
}
console.log(`clean: removed ${targets.length} build/cache outputs`);
