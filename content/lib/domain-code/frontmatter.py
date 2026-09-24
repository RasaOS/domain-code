"""frontmatter.py — the Python twin of frontmatter.sh (same READ contract).

Installed to .claude/lib/domain-code/. For the Element's Python readers
(dashboard.py, and the python blocks in environment.sh, runtime.sh and
suite-lib.sh). bin/check-frontmatter runs both implementations over
test/frontmatter/ and fails if they ever disagree.

get() returns a value verbatim: `#` is a literal character. scalar() is the
older stamp convention (unquote, drop a ` # comment`), for stamps written
that way. Run callers as `python3 -B`, so importing this writes no
__pycache__ into an install.

Stdlib only; Python >= 3.8.
"""
import re

_FENCE = re.compile(r"---[ \t]*\Z")


def split(text):
    """Return (lines, body) or (None, text) when there is no frontmatter.

    Raises ValueError for an opened-but-unterminated block (rc 3 in bash).
    """
    if text.startswith("﻿"):
        text = text[1:]
    lines = text.split("\n")
    norm = [l[:-1] if l.endswith("\r") else l for l in lines]
    if not norm or not _FENCE.match(norm[0]):
        return None, text
    for i in range(1, len(norm)):
        if _FENCE.match(norm[i]):
            return norm[1:i], "\n".join(lines[i + 1:])
    raise ValueError("unterminated frontmatter block")


def _key_line(line, key):
    if not line.startswith(key):
        return None
    rest = line[len(key):]
    m = re.match(r"[ \t]*:(.*)\Z", rest)
    return m.group(1).strip(" \t") if m else None


def get(text, key):
    """Raw value of the FIRST top-level `key:`; None when absent."""
    fm, _ = split(text)
    if fm is None:
        raise LookupError("no frontmatter")
    for line in fm:
        v = _key_line(line, key)
        if v is not None:
            return v
    return None


def scalar(v):
    if v is None:
        return None
    if v.startswith('"'):
        out, i = [], 1
        while i < len(v):
            c = v[i]
            if c == "\\" and i + 1 < len(v):
                out.append(v[i + 1]); i += 2; continue
            if c == '"':
                break
            out.append(c); i += 1
        return "".join(out)
    if v.startswith("'"):
        return v[1:].split("'", 1)[0]
    v = re.sub(r"[ \t]+#.*\Z", "", v)
    return "" if v.startswith("#") else v


def child(text, parent, key):
    fm, _ = split(text)
    if fm is None:
        raise LookupError("no frontmatter")
    inp = False
    for line in fm:
        if line[:1] not in (" ", "\t"):
            inp = _key_line(line, parent) is not None
            continue
        if inp:
            v = _key_line(line.lstrip(" \t"), key)
            if v is not None:
                return v
    return None


def title(text):
    try:
        _, body = split(text)
    except ValueError:
        return ""
    for line in body.split("\n"):
        line = line[:-1] if line.endswith("\r") else line
        if line.startswith("# "):
            return re.sub(r"^#[ \t]+", "", line)
    return ""
