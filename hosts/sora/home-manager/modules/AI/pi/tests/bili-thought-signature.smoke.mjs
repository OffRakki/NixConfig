import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const biliRoot = process.argv[2];
assert.ok(biliRoot, "Expected path to billion-context package directory");

function loadGoogleCodec(filePath) {
  const src = fs.readFileSync(filePath, "utf8");
  const start = src.indexOf('var googleBatchThoughtSignature=Symbol("googleBatchThoughtSignature");');
  assert.ok(start >= 0, `Missing googleBatchThoughtSignature patch in ${filePath}`);
  const endMarker = "function jsonValue(text2){if(!text2)return{};try{const value=JSON.parse(text2);return value===null?{}:value}catch{return{output:text2}}}";
  const end = src.indexOf(endMarker, start);
  assert.ok(end >= 0, `Missing jsonValue end marker in ${filePath}`);
  const snippet = src.slice(start, end + endMarker.length);

  class ClusterCounter {
    #seen = new Map();
    next(base) {
      const n = this.#seen.get(base) ?? 0;
      this.#seen.set(base, n + 1);
      return n === 0 ? base : `${base}_${n}`;
    }
  }

  let idSeq = 0;
  const sandbox = {
    ClusterCounter,
    CANONICAL_IMAGE_TEXT: "[image]",
    googleSystemText: () => "",
    canonicalToolArgs: (t) => t,
    deriveCanonicalMessageId: (role, type) => `${role}_${type}_${++idSeq}`,
    imageMediaFingerprint: () => "img",
    hashId2: (s) => s,
  };
  vm.runInNewContext(
    `${snippet}\nthis.__exports = { googleToCore, coreToGoogle };`,
    sandbox,
    { filename: filePath },
  );
  return sandbox.__exports;
}

for (const rel of ["dist/index.js", "dist/agent/pi-native.js", "dist/agent/opencode-native.js"]) {
  const filePath = path.join(biliRoot, rel);
  const { googleToCore, coreToGoogle } = loadGoogleCodec(filePath);

  const parallelTurn = {
    contents: [
      { role: "user", parts: [{ text: "read these files" }] },
      {
        role: "model",
        parts: [
          { functionCall: { name: "read_file", args: { path: "a" }, id: "c1" }, thoughtSignature: "SIG_TURN_13" },
          { functionCall: { name: "read_file", args: { path: "b" }, id: "c2" } },
          { functionCall: { name: "run_command", args: { cmd: "ls" }, id: "c3" } },
        ],
      },
    ],
  };

  const { msgs } = googleToCore(parallelTurn);
  const calls = msgs.filter((m) => m.contentType === "tool-call");
  assert.equal(calls.length, 3, `${rel}: expected 3 tool-call messages`);

  // Symbol metadata must stay invisible to Object.keys / JSON serialization.
  for (const c of calls) {
    assert.ok(!Object.keys(c).includes("googleBatchThoughtSignature"), `${rel}: unexpected enumerable key`);
    assert.ok(!JSON.stringify(c).includes("googleBatchThoughtSignature"), `${rel}: leaked into JSON`);
  }

  // 1. Unsplit batch: byte-identical signature placement (only first call has signature).
  const unsplit = coreToGoogle(msgs);
  assert.equal(unsplit[1].parts[0].thoughtSignature, "SIG_TURN_13", `${rel}: unsplit first call keeps signature`);
  assert.equal(unsplit[1].parts[1].thoughtSignature, undefined, `${rel}: unsplit second call untouched`);
  assert.equal(unsplit[1].parts[2].thoughtSignature, undefined, `${rel}: unsplit third call untouched`);

  // 2. Split batch (first call folded away, remaining calls shallow-copied like processTurn does):
  //    surviving first call must inherit the batch's thoughtSignature.
  const foldedMsgs = [msgs[0], ...calls.slice(1).map((m) => ({ ...m }))];
  const split = coreToGoogle(foldedMsgs);
  assert.equal(split[1].parts.length, 2, `${rel}: expected 2 surviving calls`);
  assert.equal(split[1].parts[0].functionCall.name, "read_file");
  assert.equal(split[1].parts[0].thoughtSignature, "SIG_TURN_13", `${rel}: split first surviving call promoted signature`);
  assert.equal(split[1].parts[1].thoughtSignature, undefined, `${rel}: split second surviving call has no signature`);

  // 3. Turn without any thoughtSignature: never invent one.
  const unsigned = googleToCore({
    contents: [
      {
        role: "model",
        parts: [
          { functionCall: { name: "read_file", args: { path: "a" }, id: "u1" } },
          { functionCall: { name: "read_file", args: { path: "b" }, id: "u2" } },
        ],
      },
    ],
  });
  const unsignedSplit = coreToGoogle([unsigned.msgs[1]]);
  assert.equal(unsignedSplit[0].parts[0].thoughtSignature, undefined, `${rel}: unsigned batch stayed unsigned`);
}

console.log("bili thoughtSignature split-batch smoke passed");
