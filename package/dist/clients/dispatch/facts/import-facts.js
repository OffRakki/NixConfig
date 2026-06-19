import * as ts from "typescript";
import { logLatency } from "../../latency-logger.js";
function detectModuleType(sourceFile) {
    let hasEsm = false;
    let hasCjs = false;
    function visit(node) {
        if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
            hasEsm = true;
        }
        else if (ts.isCallExpression(node) &&
            ts.isIdentifier(node.expression) &&
            node.expression.text === "require" &&
            node.arguments.length === 1 &&
            ts.isStringLiteral(node.arguments[0])) {
            hasCjs = true;
        }
        else if (ts.isPropertyAccessExpression(node) &&
            ts.isIdentifier(node.expression) &&
            node.expression.text === "module" &&
            node.name.text === "exports") {
            hasCjs = true;
        }
        ts.forEachChild(node, visit);
    }
    ts.forEachChild(sourceFile, visit);
    if (hasEsm && !hasCjs)
        return "esm";
    if (hasCjs && !hasEsm)
        return "cjs";
    if (hasEsm || hasCjs)
        return "esm"; // mixed — treat as ESM (static imports present)
    return "unknown";
}
function collectDynamicImports(sourceFile, moduleType) {
    const entries = [];
    function visit(node) {
        // import('specifier') — dynamic ESM import
        if (ts.isCallExpression(node) &&
            node.expression.kind === ts.SyntaxKind.ImportKeyword &&
            node.arguments.length === 1 &&
            ts.isStringLiteral(node.arguments[0])) {
            entries.push({
                source: node.arguments[0].text,
                names: [],
                isDynamic: true,
                moduleType,
            });
        }
        // require('specifier') — CJS import
        else if (ts.isCallExpression(node) &&
            ts.isIdentifier(node.expression) &&
            node.expression.text === "require" &&
            node.arguments.length === 1 &&
            ts.isStringLiteral(node.arguments[0])) {
            entries.push({
                source: node.arguments[0].text,
                names: [],
                moduleType: "cjs",
            });
        }
        ts.forEachChild(node, visit);
    }
    ts.forEachChild(sourceFile, visit);
    return entries;
}
function collectReExports(sourceFile) {
    const entries = [];
    for (const stmt of sourceFile.statements) {
        if (!ts.isExportDeclaration(stmt) || !stmt.moduleSpecifier)
            continue;
        const source = stmt.moduleSpecifier.text;
        if (!stmt.exportClause) {
            // export * from '...'
            entries.push({ source, names: [] });
        }
        else if (ts.isNamedExports(stmt.exportClause)) {
            const names = stmt.exportClause.elements.map((e) => e.name.text);
            entries.push({ source, names });
        }
    }
    return entries;
}
const EXT_TO_SCRIPT_KIND = {
    ".ts": ts.ScriptKind.TS,
    ".tsx": ts.ScriptKind.TSX,
    ".mts": ts.ScriptKind.TS,
    ".cts": ts.ScriptKind.TS,
    ".js": ts.ScriptKind.JS,
    ".jsx": ts.ScriptKind.JSX,
    ".mjs": ts.ScriptKind.JS,
    ".cjs": ts.ScriptKind.JS,
};
export const importFactProvider = {
    id: "fact.file.imports",
    provides: ["file.imports", "file.reexports"],
    requires: ["file.content"],
    appliesTo(ctx) {
        const ext = ctx.filePath.slice(ctx.filePath.lastIndexOf(".")).toLowerCase();
        return ext in EXT_TO_SCRIPT_KIND;
    },
    run(ctx, store) {
        const content = store.getFileFact(ctx.filePath, "file.content");
        if (!content) {
            store.setFileFact(ctx.filePath, "file.imports", []);
            store.setFileFact(ctx.filePath, "file.reexports", []);
            return;
        }
        const ext = ctx.filePath.slice(ctx.filePath.lastIndexOf(".")).toLowerCase();
        const scriptKind = EXT_TO_SCRIPT_KIND[ext] ?? ts.ScriptKind.JS;
        const sourceFile = ts.createSourceFile(ctx.filePath, content, ts.ScriptTarget.Latest, true, scriptKind);
        const moduleType = detectModuleType(sourceFile);
        const imports = [];
        // Static import declarations
        for (const stmt of sourceFile.statements) {
            if (!ts.isImportDeclaration(stmt))
                continue;
            const source = stmt.moduleSpecifier.text;
            const clause = stmt.importClause;
            if (!clause) {
                imports.push({ source, names: [], moduleType });
                continue;
            }
            const entry = { source, names: [], moduleType };
            if (clause.name) {
                entry.defaultName = clause.name.text;
            }
            if (clause.namedBindings) {
                if (ts.isNamespaceImport(clause.namedBindings)) {
                    entry.namespace = clause.namedBindings.name.text;
                }
                else {
                    entry.names = clause.namedBindings.elements.map((e) => e.name.text);
                }
            }
            imports.push(entry);
        }
        // Dynamic imports and require() calls
        const dynamic = collectDynamicImports(sourceFile, moduleType);
        imports.push(...dynamic);
        store.setFileFact(ctx.filePath, "file.imports", imports);
        // Re-export edges (used by call graph for barrel-file traversal)
        const reexports = collectReExports(sourceFile);
        store.setFileFact(ctx.filePath, "file.reexports", reexports);
        // Telemetry: log when a file has dynamic imports or re-exports so we can
        // measure coverage and validate the implementation across real projects.
        const dynamicCount = dynamic.length;
        const reexportCount = reexports.length;
        if (dynamicCount > 0 || reexportCount > 0) {
            logLatency({
                type: "call_graph_facts",
                filePath: ctx.filePath,
                durationMs: 0,
                metadata: {
                    moduleType,
                    staticImports: imports.length - dynamicCount,
                    dynamicImports: dynamicCount,
                    reexports: reexportCount,
                    starReexports: reexports.filter((r) => r.names.length === 0).length,
                },
            });
        }
    },
};
