import * as ts from "typescript";
const BOUNDARY_PREFIXES = [
    "fetch",
    "fs.",
    "db.",
    "http",
    "axios",
    "got",
    "req.",
    "res.",
];
function getFunctionName(node) {
    if (ts.isFunctionDeclaration(node)) {
        return node.name?.text ?? "<anonymous>";
    }
    if (ts.isMethodDeclaration(node)) {
        if (ts.isIdentifier(node.name))
            return node.name.text;
        return node.name.getText();
    }
    if (ts.isArrowFunction(node) || ts.isFunctionExpression(node)) {
        const parent = node.parent;
        if (ts.isVariableDeclaration(parent) && ts.isIdentifier(parent.name)) {
            return parent.name.text;
        }
        if (ts.isPropertyAssignment(parent)) {
            return parent.name.getText();
        }
        return "<anonymous>";
    }
    return "<unknown>";
}
function isCallPassThrough(stmt, paramNames) {
    if (!ts.isReturnStatement(stmt) || !stmt.expression)
        return { pass: false };
    const expr = stmt.expression;
    if (!ts.isCallExpression(expr))
        return { pass: false };
    const args = expr.arguments.map((a) => a.getText());
    if (args.length !== paramNames.length)
        return { pass: false };
    for (let i = 0; i < args.length; i += 1) {
        if (args[i] !== paramNames[i])
            return { pass: false };
    }
    return { pass: true, target: expr.expression.getText() };
}
function calcCyclomaticComplexity(body) {
    let cc = 1;
    const walk = (node) => {
        switch (node.kind) {
            case ts.SyntaxKind.IfStatement:
            case ts.SyntaxKind.ForStatement:
            case ts.SyntaxKind.ForInStatement:
            case ts.SyntaxKind.ForOfStatement:
            case ts.SyntaxKind.WhileStatement:
            case ts.SyntaxKind.DoStatement:
            case ts.SyntaxKind.CaseClause:
            case ts.SyntaxKind.CatchClause:
            case ts.SyntaxKind.ConditionalExpression:
                cc++;
                break;
            case ts.SyntaxKind.BinaryExpression: {
                const op = node.operatorToken.kind;
                if (op === ts.SyntaxKind.AmpersandAmpersandToken ||
                    op === ts.SyntaxKind.BarBarToken ||
                    op === ts.SyntaxKind.QuestionQuestionToken)
                    cc++;
                break;
            }
        }
        ts.forEachChild(node, walk);
    };
    walk(body);
    return cc;
}
function calcMaxNestingDepth(body) {
    let maxDepth = 0;
    const isNestingNode = (node) => {
        switch (node.kind) {
            case ts.SyntaxKind.IfStatement:
            case ts.SyntaxKind.ForStatement:
            case ts.SyntaxKind.ForInStatement:
            case ts.SyntaxKind.ForOfStatement:
            case ts.SyntaxKind.WhileStatement:
            case ts.SyntaxKind.DoStatement:
            case ts.SyntaxKind.SwitchStatement:
            case ts.SyntaxKind.TryStatement:
                return true;
            default:
                return false;
        }
    };
    const walk = (node, depth) => {
        if (depth > maxDepth)
            maxDepth = depth;
        const next = isNestingNode(node) ? depth + 1 : depth;
        ts.forEachChild(node, (child) => walk(child, next));
    };
    ts.forEachChild(body, (child) => walk(child, 0));
    return maxDepth;
}
function collectOutgoingCalls(body) {
    const calls = new Set();
    const walk = (node) => {
        if (ts.isCallExpression(node)) {
            const callee = node.expression.getText();
            if (callee.length < 80)
                calls.add(callee);
        }
        ts.forEachChild(node, walk);
    };
    walk(body);
    return [...calls];
}
function hasAwaitInNode(node) {
    let found = false;
    const walk = (n) => {
        if (found)
            return;
        if (ts.isAwaitExpression(n)) {
            found = true;
            return;
        }
        ts.forEachChild(n, walk);
    };
    walk(node);
    return found;
}
function hasReturnAwaitCall(node) {
    let found = false;
    const walk = (n) => {
        if (found)
            return;
        if (ts.isReturnStatement(n) &&
            n.expression &&
            ts.isAwaitExpression(n.expression) &&
            ts.isCallExpression(n.expression.expression)) {
            found = true;
            return;
        }
        ts.forEachChild(n, walk);
    };
    walk(node);
    return found;
}
export const functionFactProvider = {
    id: "fact.file.functions",
    provides: ["file.functionSummaries"],
    requires: ["file.content"],
    appliesTo(ctx) {
        return /\.tsx?$/.test(ctx.filePath);
    },
    run(ctx, store) {
        const content = store.getFileFact(ctx.filePath, "file.content");
        if (!content) {
            store.setFileFact(ctx.filePath, "file.functionSummaries", []);
            return;
        }
        const sourceFile = ts.createSourceFile(ctx.filePath, content, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
        const summaries = [];
        const addSummary = (node) => {
            const body = node.body;
            if (!body || !ts.isBlock(body))
                return;
            const lc = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
            const paramNames = node.parameters.map((p) => p.name.getText(sourceFile));
            const statementCount = body.statements.length;
            const passThrough = statementCount === 1
                ? isCallPassThrough(body.statements[0], paramNames)
                : { pass: false };
            const target = passThrough.target ?? "";
            const lowerTarget = target.toLowerCase();
            const isBoundaryWrapper = BOUNDARY_PREFIXES.some((prefix) => lowerTarget.startsWith(prefix));
            summaries.push({
                name: getFunctionName(node),
                line: lc.line + 1,
                column: lc.character + 1,
                isAsync: !!node.modifiers?.some((m) => m.kind === ts.SyntaxKind.AsyncKeyword),
                hasAwait: hasAwaitInNode(body),
                hasReturnAwaitCall: hasReturnAwaitCall(body),
                statementCount,
                parameterCount: node.parameters.length,
                isPassThroughWrapper: passThrough.pass,
                passThroughTarget: passThrough.target,
                isBoundaryWrapper,
                cyclomaticComplexity: calcCyclomaticComplexity(body),
                maxNestingDepth: calcMaxNestingDepth(body),
                outgoingCalls: collectOutgoingCalls(body),
            });
        };
        const visit = (node) => {
            if (ts.isFunctionDeclaration(node) ||
                ts.isMethodDeclaration(node) ||
                ts.isFunctionExpression(node) ||
                ts.isArrowFunction(node)) {
                addSummary(node);
            }
            ts.forEachChild(node, visit);
        };
        visit(sourceFile);
        store.setFileFact(ctx.filePath, "file.functionSummaries", summaries);
    },
};
