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

# A step may carry its script as `- run: |` (a step without a name) or as
# `run: |-` / `run: |+` with a chomping indicator. All of them are ordinary
# YAML and all of them carry shell, so all of them have to be checked. The
# block body is not matched here: YAML fixes its indentation from the first
# non-empty line of the block, which only the lines themselves can tell.
RUN_BLOCK = re.compile(r"^(?P<prefix>[ \t]*(?:-[ \t]+)?)run:[ \t]*\|[+-]?[ \t]*(?:#.*)?$")
EXPRESSION = re.compile(r"\$\{\{[^}]*\}\}")
# `${VAR}`, `${VAR:-default}` and `${VAR:+word}` are all valid shell. Only the
# default text is not: rewriting just the name would silently change which
# variable the script reads, so the whole expansion is replaced by a plain
# reference. Expansions that nest braces are left alone; bash parses those.
PARAM_DEFAULT = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)[^}{]*\}")
# `::set-output`-style and step outputs are not shell; only rewrite $VAR forms.
RUN_KEYWORDS = ("if:", "name:", "uses:", "env:", "with:", "id:", "run:")

# Honour $BASH so this runs where `bash` is not first on PATH (Windows/MSYS).
BASH = os.environ.get("BASH", "bash")


def iter_run_blocks(text):
    """Yield (line_number, dedented_script) for each `run: |` block."""
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        header = RUN_BLOCK.match(lines[index])
        if header is None:
            index += 1
            continue
        line_no = index + 1
        index += 1
        # The content of a block scalar is indented deeper than the `run:` key.
        # A step written as `- run: |` puts the key two columns further right
        # than the dash, so the key column is taken from the matched prefix.
        key_column = len(header.group("prefix"))
        content = []
        content_indent = None
        while index < len(lines):
            line = lines[index]
            if not line.strip():
                # A blank line belongs to the block only while more content
                # follows; keeping it here matches how YAML reads the block.
                content.append("")
                index += 1
                continue
            indent = len(line) - len(line.lstrip())
            if indent <= key_column or (content_indent is not None
                                       and indent < content_indent):
                # The block ended; this line belongs to the surrounding YAML.
                break
            if content_indent is None:
                content_indent = indent
            content.append(line)
            index += 1
        if content_indent is None:
            content_indent = 0
        script = "\n".join(line[content_indent:] if line.strip() else ""
                           for line in content)
        yield line_no, script


def neutralise(script):
    """Replace GitHub Actions constructs that are not valid shell."""
    script = EXPRESSION.sub("GITHUB_EXPRESSION", script)
    # Turn ${VAR...} into a plain variable reference so bash -n can parse it.
    return PARAM_DEFAULT.sub(lambda m: "${" + m.group(1) + "}", script)


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
