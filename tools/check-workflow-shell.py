#!/usr/bin/env python3
"""Syntax-check every `run: |` block in a GitHub Actions workflow.

A YAML workflow is executable shell. A typo inside a `run:` block is invisible
until the job executes on a runner, so this extracts each block, dedents it,
neutralises GitHub expressions, and hands it to `bash -n`.

Usage: python3 tools/check-workflow-shell.py .github/workflows/audit.yml
"""
import os
import re
import subprocess
import sys

RUN_BLOCK = re.compile(r"^(\s*)run: \|\s*\n((?:\1  .*\n|\1\s*\n)+)", re.M)
EXPRESSION = re.compile(r"\$\{\{[^}]*\}\}")
PARAM_DEFAULT = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(:-?|\+)?")
# `::set-output`-style and step outputs are not shell; only rewrite $VAR forms.
RUN_KEYWORDS = ("if:", "name:", "uses:", "env:", "with:", "id:", "run:")

# Honour $BASH so this runs where `bash` is not first on PATH (Windows/MSYS).
BASH = os.environ.get("BASH", "bash")


def iter_run_blocks(text):
    """Yield (line_number, dedented_script) for each `run: |` block."""
    for match in RUN_BLOCK.finditer(text):
        indent = match.group(1)
        body = match.group(2)
        lines = []
        for line in body.splitlines():
            if not line.strip():
                lines.append("")
            else:
                lines.append(line[len(indent) + 2:])
        line_no = text[:match.start()].count("\n") + 1
        yield line_no, "\n".join(lines)


def neutralise(script):
    """Replace GitHub Actions constructs that are not valid shell."""
    script = EXPRESSION.sub("GITHUB_EXPRESSION", script)
    # Turn ${VAR...} into a plain variable reference so bash -n can parse it.
    return PARAM_DEFAULT.sub(lambda m: "${" + m.group(1), script)


def main(argv):
    if len(argv) != 2:
        print("usage: check-workflow-shell.py <workflow.yml>", file=sys.stderr)
        return 2
    with open(argv[1], "r", encoding="utf-8") as handle:
        text = handle.read()

    blocks = list(iter_run_blocks(text))
    if not blocks:
        print("error: no `run: |` blocks found in " + argv[1], file=sys.stderr)
        return 1

    failures = 0
    for line_no, script in blocks:
        checked = neutralise(script)
        result = subprocess.run([BASH, "-n"], input=checked, text=True,
                                capture_output=True)
        if result.returncode != 0:
            failures += 1
            print("FAIL %s:%d" % (argv[1], line_no), file=sys.stderr)
            print(result.stderr, file=sys.stderr)
    print("%s: %d run blocks checked, %d failed"
          % (argv[1], len(blocks), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
