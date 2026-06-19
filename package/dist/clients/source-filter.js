/**
 * Source File Filter — Deduplicates source files by detecting build artifacts.
 *
 * Problem: When scanning a codebase, we encounter both source files and their
 * compiled/transpiled outputs (TypeScript → JavaScript, Vue → JavaScript, etc.).
 * Scanning both wastes time and produces duplicate findings.
 *
 * Solution: For each file, check if a "higher precedence" source sibling exists.
 * If yes, skip the file as a build artifact. If no, keep it as hand-written source.
 *
 * Supported ecosystems:
 * - TypeScript: .ts shadows .js, .tsx shadows .jsx
 * - Vue/Svelte: .vue/.svelte shadows .js
 * - CoffeeScript: .coffee shadows .js
 *
 * Files without higher-precedence siblings are kept only when they do not look
 * generated/codegen-produced (hand-written JS, Python, Go, Rust, etc.).
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { getProjectIgnoreMatcher, isExcludedDirName } from "./file-utils.js";
import { isDeclarationFile, isGeneratedArtifactDirectoryName, isGeneratedOrArtifact, } from "./generated-artifacts.js";
/**
 * Mapping of file extension to the extensions it shadows (build artifacts).
 * Order matters: first entry has highest precedence.
 */
export const SOURCE_PRECEDENCE = {
    ".ts": [".js", ".mjs", ".cjs"],
    ".tsx": [".jsx", ".js", ".mjs", ".cjs"],
    ".vue": [".js", ".mjs"],
    ".svelte": [".js", ".mjs"],
    ".coffee": [".js"],
};
/**
 * All extensions that could be source or artifacts, in precedence order.
 */
export const ALL_SCANNABLE_EXTENSIONS = [
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".mjs",
    ".cjs",
    ".vue",
    ".svelte",
    ".coffee",
    ".py",
    ".go",
    ".rs",
    ".rb",
    ".rake",
    ".gemspec",
    ".ru",
];
function shouldSkipGeneratedOrArtifact(filePath, options) {
    const includeDeclarations = options?.includeDeclarationFiles === true;
    if (options?.includeGenerated === true) {
        return !includeDeclarations && isDeclarationFile(filePath);
    }
    return isGeneratedOrArtifact(filePath, {
        readContentHeader: options?.inspectGeneratedHeaders !== false,
        includeDeclarations: !includeDeclarations,
    });
}
/**
 * Extract the basename (filename without extension) from a path.
 */
function getBasename(filePath) {
    const ext = path.extname(filePath);
    return path.basename(filePath, ext);
}
/**
 * Get the directory of a file path.
 */
function getDir(filePath) {
    return path.dirname(filePath);
}
/**
 * Check if a file has a higher-precedence source sibling.
 * Returns the shadowing source file path if found, null otherwise.
 */
export function findSourceSibling(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    const dir = getDir(filePath);
    const base = getBasename(filePath);
    // Find which precedence group this extension belongs to
    for (const [sourceExt, shadowedExts] of Object.entries(SOURCE_PRECEDENCE)) {
        if (shadowedExts.includes(ext)) {
            // This file could be shadowed by a source file with sourceExt
            const siblingPath = path.join(dir, base + sourceExt);
            if (fs.existsSync(siblingPath)) {
                return siblingPath;
            }
        }
    }
    return null;
}
/**
 * Check if a file is a build artifact (has a source sibling).
 */
export function isBuildArtifact(filePath) {
    return findSourceSibling(filePath) !== null;
}
/**
 * Filter a list of files, removing build artifacts that have source siblings
 * plus likely generated/codegen artifacts.
 * Returns de-duplicated list keeping only highest-precedence source files.
 */
export function filterSourceFiles(filePaths, options) {
    // Track which files we're keeping and why we're skipping others
    const keep = [];
    const skipReasons = new Map(); // skipped file -> kept source
    for (const filePath of filePaths) {
        const sourceSibling = findSourceSibling(filePath);
        if (sourceSibling) {
            // This is a build artifact, skip it
            skipReasons.set(filePath, sourceSibling);
        }
        else if (shouldSkipGeneratedOrArtifact(filePath, options)) {
            // Generated/codegen outputs are not hand-written source.
            skipReasons.set(filePath, "generated-or-artifact");
        }
        else {
            // No higher-precedence source, keep it
            keep.push(filePath);
        }
    }
    return keep;
}
function resolveCollectionConfig(rootDir, options) {
    return {
        ignoreMatcher: getProjectIgnoreMatcher(rootDir),
        extraExcludePatterns: options?.excludeDirs ?? [],
        extensions: new Set(options?.extensions || ALL_SCANNABLE_EXTENSIONS),
        options,
    };
}
/**
 * Decide how to handle a single directory entry. Returns the subdirectory to
 * recurse into (`recurseInto`), the source file to keep (`keepFile`), or
 * neither (skip). Shared verbatim by the sync and async collectors so they
 * produce identical results — the only difference between the two is that the
 * async variant yields to the event loop every N entries.
 */
function classifyEntry(entry, fullPath, cfg) {
    const { ignoreMatcher, extraExcludePatterns, extensions, options } = cfg;
    if (entry.isDirectory()) {
        if (isExcludedDirName(entry.name, extraExcludePatterns))
            return {};
        if (ignoreMatcher.isIgnored(fullPath, true))
            return {};
        if (options?.includeGenerated !== true &&
            isGeneratedArtifactDirectoryName(entry.name)) {
            return {};
        }
        if (!options?.followSymlinks && entry.isSymbolicLink())
            return {};
        return { recurseInto: fullPath };
    }
    if (entry.isFile()) {
        if (ignoreMatcher.isIgnored(fullPath, false))
            return {};
        const ext = path.extname(entry.name).toLowerCase();
        if (!extensions.has(ext))
            return {};
        // Skip if this is a build artifact or generated/codegen output.
        if (isBuildArtifact(fullPath))
            return {};
        if (shouldSkipGeneratedOrArtifact(fullPath, options))
            return {};
        return { keepFile: fullPath };
    }
    return {};
}
export function collectSourceFiles(dir, options) {
    const rootDir = path.resolve(dir);
    const cfg = resolveCollectionConfig(rootDir, options);
    const files = [];
    function scan(currentDir) {
        let entries = [];
        try {
            entries = fs.readdirSync(currentDir, { withFileTypes: true });
        }
        catch {
            return; // Permission denied or directory doesn't exist
        }
        for (const entry of entries) {
            const fullPath = path.join(currentDir, entry.name);
            const { recurseInto, keepFile } = classifyEntry(entry, fullPath, cfg);
            if (recurseInto)
                scan(recurseInto);
            else if (keepFile)
                files.push(keepFile);
        }
    }
    scan(rootDir);
    return files;
}
/**
 * Async, chunked-yield twin of {@link collectSourceFiles}. Returns the exact
 * same file list (it shares `classifyEntry`), but yields to the event loop
 * every `yieldEvery` directory entries so a large tree never holds the loop in
 * one synchronous burst.
 *
 * Why this exists: on a ~2k-file project the synchronous `collectSourceFiles`
 * blocks the loop for ~1.5s on a cold scan (≈70% of that is the per-file
 * generated-header read inside `shouldSkipGeneratedOrArtifact`). When that runs
 * on a hook tick — even a deferred background one — pi's TUI input stalls for
 * the whole burst. Background / deferred callers should prefer this variant;
 * the sync version is kept for synchronous call sites and tests.
 */
export async function collectSourceFilesAsync(dir, options) {
    const rootDir = path.resolve(dir);
    const cfg = resolveCollectionConfig(rootDir, options);
    // 50 entries/chunk keeps the worst-case synchronous burst under ~40ms even
    // on a cold scan where every kept file pays the 4 KB generated-header read
    // (measured on a 2k-file fixture). Larger values regress past the ~50ms
    // event-loop budget; see PERF-AUDIT.md.
    const yieldEvery = Math.max(1, options?.yieldEvery ?? 50);
    const files = [];
    // Depth-first stack mirrors the recursion order of the sync collector.
    const stack = [rootDir];
    let processedSinceYield = 0;
    while (stack.length > 0) {
        const currentDir = stack.pop();
        if (currentDir === undefined)
            continue;
        let entries = [];
        try {
            entries = fs.readdirSync(currentDir, { withFileTypes: true });
        }
        catch {
            continue; // Permission denied or directory doesn't exist
        }
        // Push subdirectories in reverse so the deepest-first pop order matches
        // the sync collector's left-to-right recursion within a directory.
        const subDirs = [];
        for (const entry of entries) {
            const fullPath = path.join(currentDir, entry.name);
            const { recurseInto, keepFile } = classifyEntry(entry, fullPath, cfg);
            if (recurseInto)
                subDirs.push(recurseInto);
            else if (keepFile)
                files.push(keepFile);
            if (++processedSinceYield >= yieldEvery) {
                processedSinceYield = 0;
                await new Promise((resolve) => setImmediate(resolve));
            }
        }
        for (let i = subDirs.length - 1; i >= 0; i--)
            stack.push(subDirs[i]);
    }
    return files;
}
/**
 * Get statistics about source file filtering for debugging/monitoring.
 */
export function getFilterStats(allFiles, filteredFiles) {
    const skipped = allFiles.length - filteredFiles.length;
    const byType = {};
    // Count what we skipped
    for (const file of allFiles) {
        if (!filteredFiles.includes(file)) {
            const ext = path.extname(file).toLowerCase();
            byType[ext] = (byType[ext] || 0) + 1;
        }
    }
    return {
        total: allFiles.length,
        kept: filteredFiles.length,
        skipped,
        byType,
    };
}
