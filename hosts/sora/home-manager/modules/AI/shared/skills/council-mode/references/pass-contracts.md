# Council Mode Pass Contracts

Load this before launching council advisors.

## Pass 1 report

Request structured JSON (via native schema support when available, or plain JSON text otherwise):

```json
{
  "recommendation": "string",
  "evidence": [
    { "claim": "string", "sources": ["path/or/url"] }
  ],
  "assumptions": [
    { "assumption": "string", "status": "verified | unverified" }
  ],
  "risks": ["string"],
  "confidence": {
    "level": "high | medium | low",
    "reason": "string"
  },
  "challengeClaims": ["at most 3 claims to test against peers"],
  "ownerDecisions": ["decisions only the owner can make"],
  "changeMyMind": ["concrete evidence that would flip the recommendation"]
}
```

Advisor rules:
- Inspect supplied evidence directly.
- Stay strictly read-only; do not edit files, run mutating commands, contact peers, or spawn children.
- Keep the report concise (under ~600 words).

## Pass 2 cross-examination

Build a compact challenge packet containing only disputed claims, conflicting evidence, missing proof, owner decisions, and high-impact risks. Attribute peer points neutrally as "another advisor"; do not paste full peer reports.

Request this response shape:

```json
{
  "responses": [
    {
      "claimId": "string",
      "disposition": "accept | reject | refine | owner-decision",
      "reason": "string",
      "sources": ["path/or/url"]
    }
  ],
  "recommendationChanged": {
    "changed": true,
    "reason": "string"
  },
  "outOfScopeFindings": ["string"]
}
```

## Synthesis rubric

1. Separate verified facts (with exact file/command/source citations) from unverified assumptions.
2. Distinguish engineering tradeoffs from owner preferences.
3. Do not vote-count advisors; weigh direct evidence over consensus.
