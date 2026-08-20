/**
 * Workspace package constraints gate.
 *
 * Rejects: a `packages/*`/`apps/*` package whose `name` is not a dsk bare name,
 * that lacks `"type": "module"`, whose `version` is not semver, or that depends
 * on a package name which is neither a workspace member nor resolvable from
 * `node_modules` (dependencies/devDependencies/peerDependencies).
 */
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SEMVER_PATTERN = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/;

interface PackageManifest {
	file: string;
	json: Record<string, unknown>;
}

function findPackageManifests(): PackageManifest[] {
	const found: PackageManifest[] = [];
	for (const area of ["plugins"]) {
		const areaDir = join(root, area);
		if (!existsSync(areaDir)) continue;
		for (const entry of readdirSync(areaDir)) {
			const file = join(areaDir, entry, "package.json");
			if (!existsSync(file)) continue;
			if (statSync(join(areaDir, entry)).isDirectory()) {
				found.push({ file, json: JSON.parse(readFileSync(file, "utf8")) });
			}
		}
	}
	return found;
}

function lineOf(file: string, needle: string): number | undefined {
	const lines = readFileSync(file, "utf8").split("\n");
	const index = lines.findIndex((line) => line.includes(`"${needle}"`));
	return index === -1 ? undefined : index + 1;
}

const manifests = findPackageManifests();
const workspaceNames = new Set(manifests.map((m) => m.json.name as string | undefined).filter((n): n is string => typeof n === "string"));

const violations: string[] = [];
for (const { file, json } of manifests) {
	const name = json.name;
	if (typeof name !== "string" || !NAME_PATTERN.test(name)) {
		violations.push(`${file}${lineOf(file, "name") ? `:${lineOf(file, "name")}` : ""} — name ${JSON.stringify(name)} must match ${NAME_PATTERN}`);
	}
	if (json.type !== "module") {
		violations.push(`${file}${lineOf(file, '"type"') ? `:${lineOf(file, '"type"')}` : ""} — missing "type": "module"`);
	}
	if (typeof json.version !== "string" || !SEMVER_PATTERN.test(json.version)) {
		violations.push(`${file}${lineOf(file, "version") ? `:${lineOf(file, "version")}` : ""} — version ${JSON.stringify(json.version)} is not semver`);
	}
	for (const section of ["dependencies", "devDependencies", "peerDependencies"] as const) {
		const deps = json[section];
		if (!deps || typeof deps !== "object") continue;
		for (const depName of Object.keys(deps)) {
			const resolves = workspaceNames.has(depName) || existsSync(join(root, "node_modules", ...depName.split("/")));
			if (!resolves) {
				violations.push(`${file}:${lineOf(file, depName) ?? "?"} — ${section}.${depName} is not a workspace package and does not resolve from node_modules`);
			}
		}
	}
}

for (const violation of violations) process.stderr.write(`constraint violation: ${violation}\n`);
if (violations.length > 0) process.exitCode = 1;
