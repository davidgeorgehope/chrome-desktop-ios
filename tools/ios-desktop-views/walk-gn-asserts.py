#!/usr/bin/env python3
"""Iteratively gn gen the BrowserView iOS probe and widen iOS-excluding asserts."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

SRC = (Path.home() / "chromium-build/chromium/src")
OUT = SRC / "out/Release-iphonesimulator-views"
LOG = (Path.home() / "chromium-build/logs/views-m2/gn-walk.log")
CHANGES = (Path.home() / "chromium-build/logs/views-m2/gn-walk-changes.txt")
UI_IMPORT = 'import("//build/config/ui.gni")'
MAX_ITERS = 150

PLAT = r"(is_win|is_mac|is_linux|is_chromeos|is_android|is_desktop_android)"
RE_PLAT_COND = re.compile(rf"^{PLAT}(?:\s*\|\|\s*{PLAT})+$")
RE_ERROR = re.compile(
    r"^ERROR at //([^:]+):(\d+):\d+: Assertion failed\.\n(assert\([^\n]+)",
    re.M,
)
RE_ERROR_ANY = re.compile(r"^ERROR at //([^:]+):(\d+):", re.M)


def run_gn_gen() -> tuple[int, str]:
    proc = subprocess.run(
        ["gn", "gen", str(OUT)],
        cwd=str(SRC),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return proc.returncode, proc.stdout


def ensure_ui_import(text: str) -> str:
    if UI_IMPORT not in text:
        lines = text.splitlines(keepends=True)
        insert_at = 0
        seen_code = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                if not seen_code:
                    insert_at = i + 1
                continue
            if stripped.startswith("import("):
                insert_at = i + 1
                seen_code = True
                continue
            break
        lines.insert(insert_at, UI_IMPORT + "\n")
        text = "".join(lines)
    # Move import above the first assert if needed.
    lines = text.splitlines(keepends=True)
    import_idx = first_assert = None
    for i, line in enumerate(lines):
        if UI_IMPORT in line and import_idx is None:
            import_idx = i
        if line.strip().startswith("assert(") and first_assert is None:
            first_assert = i
    if import_idx is not None and first_assert is not None and import_idx > first_assert:
        imp = lines.pop(import_idx)
        lines.insert(first_assert, imp if imp.endswith("\n") else imp + "\n")
        text = "".join(lines)
    return text


def extract_assert(lines: list[str], start_idx: int) -> tuple[int, str] | None:
    """Return (end_idx_inclusive, assert_text) for the assert starting at start_idx."""
    if start_idx < 0 or start_idx >= len(lines):
        return None
    # Scan backward a few lines if this line is a continuation.
    i = start_idx
    while i > 0 and "assert(" not in "".join(lines[max(0, i - 3) : i + 1]):
        i -= 1
    # Find the line that actually contains assert(
    found = None
    for j in range(max(0, start_idx - 5), min(len(lines), start_idx + 3)):
        if "assert(" in lines[j]:
            found = j
            break
    if found is None:
        return None
    buf = []
    depth = 0
    started = False
    for k in range(found, len(lines)):
        buf.append(lines[k])
        for ch in lines[k]:
            if ch == "(":
                depth += 1
                started = True
            elif ch == ")":
                depth -= 1
        if started and depth <= 0:
            return k, "".join(buf)
    return None


def widen_assert_text(text: str) -> str | None:
    if "enable_ios_desktop_views" in text:
        return None
    # Normalize to reason about the condition, but rewrite the original text.
    compact = re.sub(r"\s+", " ", text).strip()
    m = re.match(r"assert\((.*)\)\s*$", compact, re.S)
    if not m:
        return None
    inner = m.group(1)
    msg_m = re.search(r',\s*("[^"]*")\s*$', inner)
    if msg_m:
        cond = inner[: msg_m.start()].strip()
        has_msg = True
    else:
        cond = inner.strip()
        has_msg = False

    new_cond = None
    if "!is_ios" in cond:
        new_cond = cond.replace("!is_ios", "(!is_ios || enable_ios_desktop_views)")
    elif RE_PLAT_COND.match(cond):
        new_cond = f"{cond} || (is_ios && enable_ios_desktop_views)"
    else:
        return None

    if has_msg:
        # Keep a multi-line shape if the original was multi-line.
        if "\n" in text:
            # Replace just the condition portion: from assert( to the last comma
            # before the message.
            return re.sub(
                r"assert\((.*),\s*(\"[^\"]*\")\)",
                lambda mm: f"assert({new_cond},\n       {mm.group(2)})",
                compact,
                count=1,
                flags=re.S,
            ) + ("\n" if text.endswith("\n") else "")
        return f'assert({new_cond}, {msg_m.group(1)})\n'
    # Single-line no-message (or collapsed).
    indent = re.match(r"^(\s*)", text).group(1)
    return f"{indent}assert({new_cond})\n"


def patch_file(rel: str, line_no: int, assert_head: str | None = None) -> str:
    path = SRC / rel
    if not path.exists():
        return f"MISSING {rel}"
    text = ensure_ui_import(path.read_text())
    lines = text.splitlines(keepends=True)
    extracted = None
    if assert_head:
        for i, line in enumerate(lines):
            if assert_head.strip() in line or line.strip().startswith(assert_head.strip()[:40]):
                extracted = extract_assert(lines, i)
                if extracted:
                    break
    if extracted is None:
        extracted = extract_assert(lines, line_no - 1)
    if extracted is None:
        # Search the first 40 lines for a file-level assert.
        for i, line in enumerate(lines[:50]):
            if "assert(" in line:
                extracted = extract_assert(lines, i)
                if extracted:
                    break
    if extracted is None:
        snippet = "".join(f"{i+1}: {l}" for i, l in enumerate(lines[:25]))
        return f"UNHANDLED (no assert found) in {rel}:{line_no}\n{snippet}"
    end_idx, assert_text = extracted
    # start idx: walk back from end by the number of lines in assert_text
    nlines = assert_text.count("\n")
    if assert_text.endswith("\n"):
        start_idx = end_idx - nlines + 1
    else:
        start_idx = end_idx - nlines
    # Safer: find start by searching backward for assert(
    start_idx = end_idx
    while start_idx > 0 and "assert(" not in lines[start_idx]:
        start_idx -= 1
    assert_text = "".join(lines[start_idx : end_idx + 1])
    new = widen_assert_text(assert_text)
    if new is None:
        snippet = "".join(f"{i+1}: {l}" for i, l in enumerate(lines[:30]))
        return f"UNHANDLED assert in {rel}:{line_no}\n{assert_text}\n----\n{snippet}"
    if not new.endswith("\n"):
        new += "\n"
    lines[start_idx : end_idx + 1] = [new]
    path.write_text("".join(lines))
    return f"OK\n  {rel}:{start_idx+1}: {assert_text.strip()}  ->  {new.strip()}"



RE_ENABLE_ASSERT = re.compile(r"^assert\((enable_[a-z0-9_]+)\)\s*$", re.M)
RE_SEE = re.compile(
    r"^See //([^:]+):(\d+):\d+: which caused the file to be included\.\n\s+(\"[^\"]+\")",
    re.M,
)


def wrap_feature_dep(out: str) -> str | None:
    """If a feature-flag assert was caused by a GN dep, move that dep under if (flag)."""
    am = RE_ENABLE_ASSERT.search(out)
    sm = RE_SEE.search(out)
    if not am or not sm:
        return None
    flag, rel, line_no, dep = am.group(1), sm.group(1), int(sm.group(2)), sm.group(3)
    path = SRC / rel
    if not path.exists():
        return f"MISSING cause {rel}"
    text = path.read_text()
    # Ensure the flag's typical import exists if it's extensions.
    if flag.startswith("enable_extensions") and 'import("//extensions/buildflags/buildflags.gni")' not in text:
        text = ensure_ui_import(text)  # not the right import; add explicitly
        if 'import("//extensions/buildflags/buildflags.gni")' not in text:
            # put after last import
            lines = text.splitlines(keepends=True)
            insert_at = 0
            for i, line in enumerate(lines):
                if line.strip().startswith("import("):
                    insert_at = i + 1
            lines.insert(insert_at, 'import("//extensions/buildflags/buildflags.gni")\n')
            text = "".join(lines)
    lines = text.splitlines(keepends=True)
    idx = line_no - 1
    if idx < 0 or idx >= len(lines) or dep not in lines[idx]:
        # search nearby
        found = None
        for j in range(max(0, idx - 3), min(len(lines), idx + 4)):
            if dep in lines[j]:
                found = j
                break
        if found is None:
            return f"UNHANDLED dep {dep} not at {rel}:{line_no}"
        idx = found
    # Identify deps vs public_deps by scanning back for the last open list.
    kind = "deps"
    depth = 0
    for j in range(idx, -1, -1):
        s = lines[j]
        depth += s.count("]") - s.count("[")
        # when we cross out of the current list, the line with `[` declaring it
        if "[" in s:
            if "public_deps" in s:
                kind = "public_deps"
                break
            if "deps" in s:
                kind = "deps"
                break
    # Remove the dep line
    removed = lines.pop(idx)
    # Find the enclosing target closing brace: after idx, the current target
    # still ends at the same place (line numbers after idx shifted by -1).
    # Search backward from original idx for `source_set(`/`component(`/`static_library(`/`group(`
    # then find its closing `}` at indent 0 or same indent as the target.
    start = None
    for j in range(min(idx, len(lines) - 1), -1, -1):
        st = lines[j].lstrip()
        if st.startswith("source_set(") or st.startswith("component(") or st.startswith("static_library(") or st.startswith("group("):
            start = j
            break
    if start is None:
        return f"UNHANDLED no enclosing target for {rel}:{line_no}"
    indent = re.match(r"^(\s*)", lines[start]).group(1)
    # Closing brace of this target: a line that is exactly `indent + "}\n"` and
    # bracket/brace depth from start is 0 after that line.
    close = None
    brace = 0
    started = False
    for j in range(start, len(lines)):
        brace += lines[j].count("{") - lines[j].count("}")
        started = started or "{" in lines[j]
        if started and brace <= 0:
            close = j
            break
    if close is None:
        return f"UNHANDLED no closing brace in {rel}"
    block = (
        f"{indent}  if ({flag}) {{\n"
        f"{indent}    {kind} += [ {dep} ]\n"
        f"{indent}  }}\n"
    )
    lines.insert(close, block)
    path.write_text("".join(lines))
    return (
        f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} +=\n"
        f"  removed: {removed.strip()}"
    )


def main() -> int:
    # Append; don't wipe previous successful patches' log history entirely
    with LOG.open("a") as f:
        f.write("\n===== new walk session =====\n")
    for i in range(1, MAX_ITERS + 1):
        rc, out = run_gn_gen()
        with LOG.open("a") as f:
            f.write(f"\n===== iter {i} rc={rc} =====\n")
            f.write(out[-8000:])
        if rc == 0:
            # Confirm graph is loaded: look for "Done. Made"
            print(f"GN_OK after {i} gen(s)")
            print(out[-500:])
            with CHANGES.open("a") as f:
                f.write(f"GN_OK after {i} gens\n{out[-300:]}\n")
            return 0
        m = RE_ERROR.search(out)
        if not m:
            any_m = RE_ERROR_ANY.search(out)
            print(f"STOP non-assert GN error at iter {i}")
            print(out[-5000:])
            with CHANGES.open("a") as f:
                f.write(f"STOP iter {i} non-assert\n{out[-5000:]}\n")
            return 2
        rel, line_no, assert_head = m.group(1), int(m.group(2)), m.group(3)
        print(f"iter {i}: assertion at //{rel}:{line_no}", flush=True)
        result = patch_file(rel, line_no, assert_head=assert_head)
        print(result, flush=True)
        with CHANGES.open("a") as f:
            f.write(f"iter {i}: //{rel}:{line_no}\n{result}\n")
        if result.startswith("UNHANDLED") or result.startswith("MISSING"):
            wrapped = wrap_feature_dep(out)
            if wrapped and wrapped.startswith("OK"):
                print(wrapped, flush=True)
                with CHANGES.open("a") as f:
                    f.write(f"iter {i}: wrap\n{wrapped}\n")
                continue
            if wrapped:
                print(wrapped, flush=True)
            print(out[-3000:])
            return 3
    print(f"HIT MAX_ITERS={MAX_ITERS}")
    return 4


if __name__ == "__main__":
    sys.exit(main())
