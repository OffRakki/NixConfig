#!/usr/bin/env python3
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
buddy_controller = root / "@apat183/pi-buddy/src/controller.ts"


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"Expected exactly one patch target, found {count}: {old!r}")
    return text.replace(old, new, 1)


# The footer already receives Pi's live theme proxy, but its Git branch used a
# fixed green. Keep that segment on the same palette as the rest of the bar.
footer = root / "pi-powerline/extensions/footer.ts"
text = replace_once(footer.read_text(), "hasNerdFonts, hexFg, withIcon", "hasNerdFonts, withIcon")
text = replace_once(
    text,
    "hexFg('#5faf5f', withIcon(ICON_GIT, branch))",
    "theme.fg('success', withIcon(ICON_GIT, branch))",
)
footer.write_text(text)

text = buddy_controller.read_text()
text = replace_once(
    text,
    "\t\tthis.applyAll(ctx);\n\t\tctx.ui.setTitle(",
    "\t\t// Pi 0.80 misplaces widgets registered synchronously during session_start.\n"
    "\t\tsetImmediate(() => this.applyAll(ctx));\n\t\tctx.ui.setTitle(",
)
buddy_controller.write_text(text)

# Suppress only the informational startup banner; keep actionable warnings.
failover_index = root / "pi-multi-account/index.ts"
text = failover_index.read_text()
text = replace_once(
    text,
    '\t\tctx.ui.notify(\n'
    '\t\t\tsubagentChild\n'
    '\t\t\t\t? `pi-multi-account v${VERSION} loaded in passive pi-subagents child mode. Model routing remains owned by the parent runner.`\n'
    '\t\t\t\t: `pi-multi-account v${VERSION} loaded (${config.enabled ? "enabled" : "disabled"}). ${rotation.length} account(s) in rotation. Config: ${CONFIG_PATH}`,\n'
    '\t\t\t"info",\n'
    '\t\t);\n',
    "",
)
text = replace_once(
    text,
    '\t\t\t} else if (!seamlessResume) {\n'
    '\t\t\t\tctx.ui?.notify?.(\n'
    '\t\t\t\t\t`pi-multi-account v${VERSION}: seamless in-place resume (pi.continueAgent) is not available on this Pi build — automatic recovery resumes from the preserved task context in a fresh turn. Temporary errors keep the same provider/model; confirmed quota limits retain failover. This is the expected fallback, not an error.`,\n'
    '\t\t\t\t\t"info",\n'
    '\t\t\t\t);\n',
    "",
)
failover_index.write_text(text)

# Gemini 3+ attaches thoughtSignature only to the first functionCall in a parallel
# batch. When billion-context folds earlier calls of a batch into a block while
# leaving later calls visible (e.g. protected recent messages), coreToGoogle emits
# the surviving calls with no thoughtSignature and Google rejects the turn (400).
# Preserve the batch's leading signature on a non-enumerable Symbol so unsplit turns
# stay byte-identical and split turns promote the signature to the first surviving call.
bili_root = root / "billion-context"
bili_fc_old = (
    'for(const part of parts){const fc=part.functionCall;'
    'if(!fc||typeof fc.name!=="string")continue;'
    'const text2=jsonText(fc.args??{});'
    'const wireId=typeof fc.id==="string"?fc.id:void 0;'
    'const base=deriveCanonicalMessageId("assistant","tool-call",canonicalToolArgs(text2),{toolName:fc.name});'
    'const id=clusters.next(base);'
    'const toolCallId=wireId??id;'
    'const queue=unmatchedCalls.get(fc.name);'
    'if(queue)queue.push(toolCallId);else unmatchedCalls.set(fc.name,[toolCallId]);'
    'msgs.push({id,role:"assistant",contentType:"tool-call",toolName:fc.name,toolCallId,text:text2,'
    'rawGoogleParts:[part],...signatureField("googleThoughtSignature",part.thoughtSignature)})}'
)
bili_fc_new = (
    'let batchCallSig;'
    'for(const part of parts){const fc=part.functionCall;'
    'if(!fc||typeof fc.name!=="string")continue;'
    'if(!batchCallSig&&typeof part.thoughtSignature==="string"&&part.thoughtSignature.length>0)'
    'batchCallSig=part.thoughtSignature;'
    'const text2=jsonText(fc.args??{});'
    'const wireId=typeof fc.id==="string"?fc.id:void 0;'
    'const base=deriveCanonicalMessageId("assistant","tool-call",canonicalToolArgs(text2),{toolName:fc.name});'
    'const id=clusters.next(base);'
    'const toolCallId=wireId??id;'
    'const queue=unmatchedCalls.get(fc.name);'
    'if(queue)queue.push(toolCallId);else unmatchedCalls.set(fc.name,[toolCallId]);'
    'msgs.push({id,role:"assistant",contentType:"tool-call",toolName:fc.name,toolCallId,text:text2,'
    'rawGoogleParts:[part],...signatureField("googleThoughtSignature",part.thoughtSignature),'
    '...batchCallSig&&!part.thoughtSignature?{[googleBatchThoughtSignature]:batchCallSig}:{}})}'
)
bili_flush_old = (
    'function coreToGoogle(messages,opts){const out=[];let model=null;let user=null;'
    'const flushModel=()=>{if(!model)return;'
    'const parts=[...model.reasoning,...model.text,...model.calls];'
    'model=null;if(parts.length>0)out.push({role:"model",parts})};'
)
bili_flush_new = (
    'function coreToGoogle(messages,opts){const out=[];let model=null;let user=null;'
    'const flushModel=()=>{if(!model)return;'
    'if(model.calls.length>0&&model.batchCallSig){const first=model.calls[0];'
    'if(typeof first.thoughtSignature!=="string"||first.thoughtSignature.length===0)'
    'model.calls[0]={...first,thoughtSignature:model.batchCallSig}}'
    'const parts=[...model.reasoning,...model.text,...model.calls];'
    'model=null;if(parts.length>0)out.push({role:"model",parts})};'
)
for rel, loop_var in [
    ("dist/index.js", "m2"),
    ("dist/agent/pi-native.js", "m4"),
    ("dist/agent/opencode-native.js", "m2"),
]:
    target = bili_root / rel
    text = target.read_text()
    text = replace_once(
        text,
        "function googleToCore(body){",
        'var googleBatchThoughtSignature=Symbol("googleBatchThoughtSignature");'
        "function googleToCore(body){",
    )
    text = replace_once(text, bili_fc_old, bili_fc_new)
    text = replace_once(text, bili_flush_old, bili_flush_new)
    text = replace_once(
        text,
        f'else if({loop_var}.contentType==="tool-call")model.calls.push(toolCallPart({loop_var}));',
        f'else if({loop_var}.contentType==="tool-call"){{model.calls.push(toolCallPart({loop_var}));'
        f'if(!model.batchCallSig&&typeof {loop_var}[googleBatchThoughtSignature]==="string"'
        f'&&{loop_var}[googleBatchThoughtSignature].length>0)'
        f'model.batchCallSig={loop_var}[googleBatchThoughtSignature]}}',
    )
    target.write_text(text)
