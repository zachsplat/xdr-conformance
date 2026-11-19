#!/usr/bin/env python3
"""Feed requests one at a time to a long-running adapter process and restart it
if it dies, recording the request that killed it as a crash.

Usage: driver.py CMD [ARGS...] < req.jsonl > out.jsonl
"""
import json
import subprocess
import sys


def start(cmd):
    return subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def main():
    cmd = sys.argv[1:]
    p = start(cmd)
    out = sys.stdout
    for line in sys.stdin:
        if not line.strip():
            continue
        req = json.loads(line)
        try:
            p.stdin.write(line.encode() if line.endswith("\n") else (line + "\n").encode())
            p.stdin.flush()
            res = p.stdout.readline()
        except BrokenPipeError:
            res = b""
        if not res:
            try:
                p.stdin.close()
            except Exception:
                pass
            err = p.stderr.read().decode(errors="replace").strip().splitlines()
            p.wait()
            out.write(json.dumps({"id": req.get("id"), "ok": False,
                                  "error": "CRASH (process died, exit %s): %s" % (p.returncode, (err[-1] if err else "")[:250])}) + "\n")
            out.flush()
            p = start(cmd)
            continue
        out.write(res.decode())
    p.stdin.close()
    p.wait()


if __name__ == "__main__":
    main()
