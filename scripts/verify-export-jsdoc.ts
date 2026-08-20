/**
 * Export-JSDoc gate over the `src` trees of every workspace package.
 *
 * Rejects: exported function-like declarations (functions, const arrows,
 * public class methods, documented constructors) that lack JSDoc entirely, or
 * whose JSDoc omits an `@param` for an identifier parameter or a `@returns`
 * when the return type is not void-like; and exported classes without a
 * class-level JSDoc. Type/interface/enum exports and plugin object-literal
 * default exports are exempt.
 *
 * Parsing uses the installed native TypeScript's LSP API (`typescript/unstable`),
 * which serves real SourceFile ASTs; JSDoc blocks are read from the source text
 * the AST points at.
 */
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { API } from "typescript/unstable/sync";
import {
	SyntaxKind,
	getTokenPosOfNode,
	isArrowFunction,
	isClassDeclaration,
	isConstructorDeclaration,
	isFunctionDeclaration,
	isFunctionExpression,
	isIdentifier,
	isMethodDeclaration,
	isPrivateIdentifier,
	isVariableStatement,
	type Node,
	type SourceFile,
} from "typescript/unstable/ast";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function walkTs(dir: string, out: string[]): void {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (entry.name === "lib" || entry.name === "node_modules") continue;
		const full = join(dir, entry.name);
		if (entry.isDirectory()) walkTs(full, out);
		else if (entry.name.endsWith(".ts")) out.push(full);
	}
}

const srcFiles: string[] = [];
for (const area of ["plugins"]) {
	for (const packageDir of readdirSync(join(root, area))) {
		const src = join(root, area, packageDir, "src");
		if (existsSync(src)) walkTs(src, srcFiles);
	}
}

const violations: string[] = [];

interface ModifierHost {
	modifiers?: readonly { kind: SyntaxKind }[];
}

function hasModifier(node: ModifierHost, kind: SyntaxKind): boolean {
	return node.modifiers?.some((modifier) => modifier.kind === kind) ?? false;
}

function isExported(node: ModifierHost): boolean {
	return hasModifier(node, SyntaxKind.ExportKeyword) || hasModifier(node, SyntaxKind.DefaultKeyword);
}

/** The JSDoc comment text attached to a declaration, from its leading trivia. */
function jsDocOf(text: string, node: Node, sourceFile: SourceFile): string | undefined {
	const tokenStart = getTokenPosOfNode(node, sourceFile, false);
	const trivia = text.slice(node.pos, tokenStart);
	const start = trivia.lastIndexOf("/**");
	if (start === -1) return undefined;
	const end = trivia.indexOf("*/", start + 3);
	if (end === -1) return undefined;
	return trivia.slice(start + 3, end);
}

/** Whether the return type annotation is void-like (void/undefined/Promise<void>). */
function isVoidLikeReturn(fn: { type?: unknown }): boolean {
	const type = fn.type as { kind?: SyntaxKind } | undefined;
	if (type === undefined) return false;
	if (type.kind === SyntaxKind.VoidKeyword || type.kind === SyntaxKind.UndefinedKeyword) return true;
	if (type.kind !== SyntaxKind.TypeReference) return false;
	const reference = type as { typeName?: unknown; typeArguments?: Array<{ kind?: SyntaxKind }> };
	const typeName = reference.typeName as { kind?: SyntaxKind; text?: string } | undefined;
	if (typeName === undefined || typeName.kind !== SyntaxKind.Identifier || typeName.text !== "Promise") return false;
	const argument = reference.typeArguments?.[0];
	return argument !== undefined && (argument.kind === SyntaxKind.VoidKeyword || argument.kind === SyntaxKind.UndefinedKeyword);
}

interface FunctionLike {
	pos: number;
	parameters: readonly { name: Node }[];
	type?: unknown;
}

function checkFunctionLike(
	file: string,
	text: string,
	sourceFile: SourceFile,
	fn: FunctionLike,
	container: Node,
	label: string,
	requireJsDoc: boolean,
	checkReturns = true,
): void {
	const line = text.slice(0, fn.pos).split("\n").length;
	const jsDoc = jsDocOf(text, container, sourceFile);
	if (jsDoc === undefined) {
		if (requireJsDoc) violations.push(`${relative(root, file)}:${line} — ${label} has no JSDoc`);
		return;
	}
	const documented = new Set<string>();
	for (const match of jsDoc.matchAll(/@param\s+(?:\{[^}]*}\s*)?([A-Za-z_$][\w$]*)/g)) documented.add(match[1]);
	for (const parameter of fn.parameters) {
		const name = parameter.name;
		if (isIdentifier(name) && !documented.has(name.text)) {
			violations.push(`${relative(root, file)}:${line} — ${label} JSDoc misses @param ${name.text}`);
		}
	}
	if (checkReturns && !/@returns?\b/.test(jsDoc) && !isVoidLikeReturn(fn)) {
		violations.push(`${relative(root, file)}:${line} — ${label} JSDoc misses @returns`);
	}
}

function checkClass(file: string, text: string, sourceFile: SourceFile, cls: Node & { name?: { text?: string }; members: readonly Node[] }): void {
	const label = `export class ${cls.name?.text ?? ""}`;
	if (jsDocOf(text, cls, sourceFile) === undefined) {
		violations.push(`${relative(root, file)}:${text.slice(0, cls.pos).split("\n").length} — ${label} has no JSDoc`);
	}
	for (const member of cls.members) {
		if (isMethodDeclaration(member)) {
			if (isPrivateIdentifier(member.name) || hasModifier(member, SyntaxKind.PrivateKeyword)) continue;
			if (jsDocOf(text, member, sourceFile) === undefined) continue; // undocumented methods are not flagged
			checkFunctionLike(file, text, sourceFile, member, member, `method ${member.name.getText()}`, false);
		} else if (isConstructorDeclaration(member) && jsDocOf(text, member, sourceFile) !== undefined) {
			checkFunctionLike(file, text, sourceFile, member, member, "constructor", false);
		}
	}
}

const api = new API({ cwd: root });
try {
	const configFile = join(root, "tsconfig.typecheck.json");
	const snapshot = api.updateSnapshot({ openProjects: [configFile] });
	try {
		const project = snapshot.getProjects().find((candidate) => candidate.configFileName === configFile) ?? snapshot.getProjects()[0];
		if (project === undefined) {
			process.stderr.write("verify-export-jsdoc: no TypeScript project could be loaded\n");
			process.exitCode = 1;
		} else {
			for (const file of srcFiles) {
				const sourceFile = project.program.getSourceFile(file);
				if (sourceFile === undefined) continue;
				const text = readFileSync(file, "utf8");
				for (const statement of sourceFile.statements) {
					if (isFunctionDeclaration(statement) && isExported(statement)) {
						checkFunctionLike(file, text, sourceFile, statement, statement, `export function ${statement.name?.text ?? ""}`, true);
					} else if (isVariableStatement(statement) && isExported(statement)) {
						for (const declaration of statement.declarationList.declarations) {
							const initializer = declaration.initializer;
							if (initializer !== undefined && (isArrowFunction(initializer) || isFunctionExpression(initializer))) {
								checkFunctionLike(file, text, sourceFile, initializer, statement, `export ${declaration.name.getText()}`, true);
							}
						}
					} else if (isClassDeclaration(statement) && isExported(statement)) {
						checkClass(file, text, sourceFile, statement);
					}
				}
			}
		}
	} finally {
		snapshot.dispose();
	}
} finally {
	api.close();
}

for (const violation of violations) process.stderr.write(`jsdoc violation: ${violation}\n`);
if (violations.length > 0) process.exitCode = 1;
