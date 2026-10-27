#!/usr/bin/env python3
"""Write the last fenced code block of an agent transcript (JSONL) to a file. usage: extract.py transcript out"""
import json, re, sys
text = ""
for line in open(sys.argv[1]):
    try: m = json.loads(line)
    except Exception: continue
    msg = m.get("message") or {}
    content = msg.get("content")
    parts = content if isinstance(content, list) else [{"type": "text", "text": content}] if isinstance(content, str) else []
    for p in parts:
        if isinstance(p, dict):
            if p.get("type") == "text" and "```" in (p.get("text") or ""): text = p["text"]
            if p.get("type") == "tool_use":
                inp = json.dumps(p.get("input", {}))
                if "```" in inp: text = json.loads(inp).get("report") or json.loads(inp).get("message") or text
blocks = re.findall(r"```[a-zA-Z0-9]*\n(.*?)```", text, re.S)
if not blocks: sys.exit("no code block found")
open(sys.argv[2], "w").write(blocks[-1])
print(f"{sys.argv[2]}: {len(blocks[-1].splitlines())} lines")
