#!/usr/bin/env python3
"""Iteratively gn gen the BrowserView iOS probe and widen iOS-excluding asserts."""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

SRC = Path("/Users/davidhope/chromium-build/chromium/src")
OUT = SRC / os.environ.get("WALK_OUT", "out/Release-iphonesimulator-views")
LOG = Path("/Users/davidhope/chromium-build/logs/views-m2/gn-walk.log")
CHANGES = Path("/Users/davidhope/chromium-build/logs/views-m2/gn-walk-changes.txt")
UI_IMPORT = 'import("//build/config/ui.gni")'
MAX_ITERS = 2000

# File-level "Chromium/iOS shouldn't use anything in //chrome" asserts.
# Widening these pulls the entire chrome/test graph; wrap incoming deps instead.
NEVER_WIDEN = {
    "chrome/BUILD.gn",
    "chrome/test/BUILD.gn",
}

# Targets in NEVER_WIDEN files that we actually need on iOS. Replace the
# group label with these leaves instead of wrapping the dep under if (!is_ios).
RETARGET_LABELS = {
    "//chrome:strings": [
        "//chrome/app:branded_strings",
        "//chrome/app:generated_resources",
        "//chrome/app/resources:locale_settings",
    ],
    "//chrome:resources": [
        "//chrome/browser:resources",
        "//chrome/common:resources",
        "//chrome/renderer:resources",
    ],
}
SKIP_DIR_PARTS = {
    "out",
    ".git",
    "node_modules",
    "__pycache__",
    ".cipd",
    "llvm-build",
    "rust-toolchain",
}

PLAT = r"(is_win|is_mac|is_linux|is_chromeos|is_android|is_desktop_android)"
RE_PLAT_COND = re.compile(rf"^{PLAT}(?:\s*\|\|\s*{PLAT})+$")
RE_ERROR = re.compile(
    r"^ERROR at //([^:]+):(\d+):\d+: Assertion failed\.\n\s*(assert\([^\n]+)",
    re.M,
)
RE_ERROR_ANY = re.compile(r"^ERROR at //([^:]+):(\d+):", re.M)
RE_UNDEF = re.compile(
    r"^ERROR at //([^:]+):(\d+):\d+: Undefined identifier\n[^\n]*\b([A-Za-z_][A-Za-z0-9_]*)\b",
    re.M,
)
RE_ENABLE_ASSERT = re.compile(r"^assert\(([A-Za-z_][A-Za-z0-9_]*)\)\s*$", re.M)
RE_SEE = re.compile(
    r"^See //([^:]+):(\d+):\d+: which caused the file to be included\.\n[^\"]*(\"[^\"]+\")",
    re.M,
)
RE_FLAG_ASSIGN = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=", re.M)

FLAG_IMPORTS: dict[str, str] = {}


def iter_gnis():
    for dirpath, dirnames, filenames in os.walk(SRC):
        dirnames[:] = [
            d
            for d in dirnames
            if d not in SKIP_DIR_PARTS and not d.startswith("out")
        ]
        for fn in filenames:
            if fn.endswith(".gni"):
                yield Path(dirpath) / fn


def score_flag_source(path: Path, line: str) -> int:
    rel = path.relative_to(SRC).as_posix()
    score = 0
    name = path.name
    if name in ("buildflags.gni", "features.gni"):
        score += 20
    if name.endswith("buildflags.gni") or name.endswith("features.gni"):
        score += 10
    if "/buildflags/" in rel or rel.endswith("/features.gni"):
        score += 5
    if "declare_args" in "".join([]):
        score += 0
    # Prefer official chrome/ui/components/extensions/build trees over tests.
    if any(rel.startswith(p) for p in ("build/", "ui/", "chrome/", "extensions/", "components/", "media/", "printing/", "pdf/", "ios/")):
        score += 3
    if "test" in rel or "/examples/" in rel:
        score -= 8
    # Prefer unindented (top-level / declare_args) assignments.
    if not line.startswith((" ", "\t")) or line.startswith("  "):
        score += 1
    return score


def iter_declare_args_bodies(text: str):
    idx = 0
    while True:
        m = re.search(r"declare_args\s*\(\s*\)\s*\{", text[idx:])
        if not m:
            return
        start = idx + m.end()
        depth = 1
        i = start
        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        yield text[start : i - 1]
        idx = i


def build_flag_index() -> dict[str, str]:
    mapping: dict[str, tuple[int, str]] = {}
    for gni in iter_gnis():
        try:
            text = gni.read_text(errors="ignore")
        except OSError:
            continue
        rel = gni.relative_to(SRC).as_posix()
        name = gni.name
        is_flag_file = name.endswith("buildflags.gni") or name.endswith("features.gni")
        declare_bodies = list(iter_declare_args_bodies(text))
        declare_flags = set()
        for body in declare_bodies:
            for m in RE_FLAG_ASSIGN.finditer(body):
                declare_flags.add(m.group(2))
        for m in RE_FLAG_ASSIGN.finditer(text):
            ident = m.group(2)
            line = m.group(0)
            in_declare = ident in declare_flags
            looks_like_flag = (
                ident.startswith(("enable_", "is_", "use_", "build_", "disable_", "enterprise_", "toolkit_"))
                or ident.endswith(("_enabled", "_available", "_supported"))
                or is_flag_file
                or in_declare
            )
            if not looks_like_flag:
                continue
            # Skip list/scope-looking identifiers that aren't flags
            if ident in {"sources", "deps", "public_deps", "configs", "ldflags", "cflags", "libs", "frameworks", "inputs", "outputs", "defines", "data", "data_deps", "public", "visibility", "testonly", "sources_assignment_filter"}:
                continue
            score = score_flag_source(gni, line)
            if in_declare:
                score += 8
            if is_flag_file:
                score += 6
            prev = mapping.get(ident)
            if prev is None or score > prev[0]:
                mapping[ident] = (score, f'import("//{rel}")')
    return {k: v[1] for k, v in mapping.items()}



def run_gn_gen() -> tuple[int, str]:
    proc = subprocess.run(
        ["gn", "gen", str(OUT), "--root-target=//chrome/browser/ui/views/ios:browser_view_ios"],
        cwd=str(SRC),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return proc.returncode, proc.stdout


def ensure_import(text: str, import_stmt: str) -> str:
    if import_stmt in text:
        return text
    lines = text.splitlines(keepends=True)
    insert_at = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if line.startswith("import("):
            insert_at = i + 1
            continue
        if not stripped or stripped.startswith("#"):
            if insert_at == 0:
                insert_at = i + 1
            continue
        if not line.startswith((" ", "\t")):
            break
    lines.insert(insert_at, import_stmt + "\n")
    return "".join(lines)


def ensure_ui_import(text: str) -> str:
    text = ensure_import(text, UI_IMPORT)
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
    found = None
    if "assert(" in lines[start_idx]:
        found = start_idx
    else:
        # Prefer an assert at or after this line, then look back.
        for j in range(start_idx, min(len(lines), start_idx + 4)):
            if "assert(" in lines[j]:
                found = j
                break
        if found is None:
            for j in range(start_idx - 1, max(-1, start_idx - 6), -1):
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
        if "\n" in text:
            return re.sub(
                r"assert\((.*),\s*(\"[^\"]*\")\)",
                lambda mm: f"assert({new_cond},\n       {mm.group(2)})",
                compact,
                count=1,
                flags=re.S,
            ) + ("\n" if text.endswith("\n") else "")
        return f"assert({new_cond}, {msg_m.group(1)})\n"
    indent = re.match(r"^(\s*)", text).group(1)
    return f"{indent}assert({new_cond})\n"


def patch_file(rel: str, line_no: int, assert_head: str | None = None) -> str:
    path = SRC / rel
    if not path.exists():
        return f"MISSING {rel}"
    if rel in NEVER_WIDEN:
        return f"UNHANDLED never-widen {rel}"
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
        for i, line in enumerate(lines[:50]):
            if "assert(" in line:
                extracted = extract_assert(lines, i)
                if extracted:
                    break
    if extracted is None:
        snippet = "".join(f"{i+1}: {l}" for i, l in enumerate(lines[:25]))
        return f"UNHANDLED (no assert found) in {rel}:{line_no}\n{snippet}"
    end_idx, assert_text = extracted
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


def add_flag_import(rel: str, flag: str) -> str:
    path = SRC / rel
    if not path.exists():
        return f"MISSING {rel}"
    imp = FLAG_IMPORTS.get(flag)
    if not imp:
        return f"UNHANDLED no gni for flag {flag} in {rel}"
    text = path.read_text()
    if imp in text:
        return f"ALREADY has {imp} in {rel} (still undefined?)"
    path.write_text(ensure_import(text, imp))
    return f"OK import {imp} into {rel} for {flag}"


BUILTIN_IDENTS = {
    "is_win", "is_mac", "is_linux", "is_chromeos", "is_android", "is_ios",
    "is_fuchsia", "is_castos", "is_apple", "is_posix", "is_desktop_android",
    "true", "false", "is_official_build", "current_os", "current_cpu",
    "host_os", "host_cpu", "target_os", "target_cpu", "is_debug",
    "is_component_build", "is_clang", "is_chrome_for_testing_branded_build",
    "is_chrome_branded", "is_official_branded",
}


def condition_from_assert_out(out: str) -> str | None:
    m = RE_ERROR.search(out)
    if m:
        head = m.group(3).strip()
        mm = re.match(r"assert\((.*)\)\s*$", head)
        if mm:
            inner = mm.group(1)
            msg_m = re.search(r',\s*("[^"]*")\s*$', inner)
            cond = inner[: msg_m.start()].strip() if msg_m else inner.strip()
            if cond:
                return cond
        # Multi-line assert(COND,  or assert(COND   without the closing paren
        # on the first line (often a message follows).
        mm = re.match(r"assert\((.+)$", head)
        if mm:
            cond = mm.group(1).strip().rstrip(",")
            # If this still looks like a quoted message start, bail.
            if cond and not cond.startswith('"'):
                return cond
    am = RE_ENABLE_ASSERT.search(out)
    if am:
        return am.group(1)
    return None


def ensure_condition_imports(text: str, cond: str) -> str:
    for ident in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", cond):
        if ident in BUILTIN_IDENTS:
            continue
        imp = FLAG_IMPORTS.get(ident)
        if imp:
            text = ensure_import(text, imp)
        elif ident.startswith("enable_extensions"):
            text = ensure_import(text, 'import("//extensions/buildflags/buildflags.gni")')
    return text



def insert_gate_after_current_list(lines: list[str], item_idx: int, kind: str, dep: str, flag: str) -> tuple[list[str], str] | None:
    """Remove dep at item_idx and insert if (flag) { kind += [ dep ] } after the list."""
    # Find list start
    list_start = None
    depth = 0
    for j in range(item_idx, -1, -1):
        depth += lines[j].count("]") - lines[j].count("[")
        if "[" in lines[j] and depth >= 0:
            list_start = j
            if depth > 0 or (depth == 0 and "[" in lines[j]):
                # crossed into the opening bracket
                if depth > 0:
                    # still inside? if depth>0 we went past the opening via ]-count first
                    pass
            break
    # More reliable: walk back accumulating ] - [ until we hit the [ that brings depth to >0
    depth = 0
    list_start = None
    for j in range(item_idx, -1, -1):
        depth += lines[j].count("]") - lines[j].count("[")
        if depth > 0 or (lines[j].count("[") and depth <= 0 and "[" in lines[j]):
            # When walking backward, encountering more [ than ] so far means we found the open
            list_start = j
            break
        if "[" in lines[j] and depth <= 0:
            list_start = j
            break
    if list_start is None:
        return None
    depth = 0
    list_end = None
    for j in range(list_start, len(lines)):
        depth += lines[j].count("[") - lines[j].count("]")
        if depth <= 0:
            list_end = j
            break
    if list_end is None:
        return None
    removed = lines[item_idx]
    del lines[item_idx]
    if item_idx <= list_end:
        list_end -= 1
    indent = re.match(r"^(\s*)", lines[list_start]).group(1)
    block = (
        f"{indent}if ({flag}) {{\n"
        f"{indent}  {kind} += [ {dep} ]\n"
        f"{indent}}}\n"
    )
    lines.insert(list_end + 1, block)
    return lines, removed



def insert_gate_only_after_list(lines: list[str], around_idx: int, kind: str, dep: str, flag: str) -> list[str] | None:
    """Insert if (flag) { kind += [ dep ] } after the list that used to contain around_idx."""
    # around_idx is at/near the old item; the item may already have been removed,
    # so search backward for a deps/public_deps list close.
    j = min(around_idx, len(lines) - 1)
    list_end = None
    # If current line or a nearby line is a closing ], use it
    for k in range(j, min(len(lines), j + 8)):
        if "]" in lines[k]:
            # check this closes a list started above
            list_end = k
            # prefer the first close at or after j
            break
    if list_end is None:
        for k in range(j, max(-1, j - 15), -1):
            if "]" in lines[k] and ("deps" in "".join(lines[max(0,k-20):k+1]) or "sources" in "".join(lines[max(0,k-20):k+1])):
                list_end = k
                break
    if list_end is None:
        return None
    indent = re.match(r"^(\s*)", lines[list_end]).group(1)
    # If the ] is more indented, use its indent; if line is just "    ]", good
    block = (
        f"{indent}if ({flag}) {{\n"
        f"{indent}  {kind} += [ {dep} ]\n"
        f"{indent}}}\n"
    )
    lines.insert(list_end + 1, block)
    return lines



def detect_list_var(lines: list[str], idx: int) -> str:
    depth = 0
    for j in range(idx, -1, -1):
        s = lines[j]
        depth += s.count("]") - s.count("[")
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\+?=\s*\[", s)
        if m and ("[" in s):
            return m.group(1)
        if j > 0 and "[" in s:
            m2 = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\+?=\s*$", lines[j - 1])
            if m2:
                return m2.group(1)
        if "[" in s and depth > 0:
            break
    return "deps"


def is_named_block_start(lines: list[str], j: int) -> bool:
    st = lines[j].lstrip()
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\(", st)
    if not m:
        return False
    if m.group(1) in {
        "if", "else", "assert", "foreach", "print", "not_needed",
        "rebase_path", "exec_script", "read_file", "write_file",
        "get_path_info", "getenv", "defined", "filter_include",
        "filter_exclude", "string_replace", "process_file_template",
        "set_defaults", "invoker",
    }:
        return False
    if "{" in lines[j]:
        return True
    if j + 1 < len(lines) and lines[j + 1].strip().startswith("{"):
        return True
    return False


def find_named_block_start(lines: list[str], idx: int) -> int | None:
    for j in range(min(idx, len(lines) - 1), -1, -1):
        if is_named_block_start(lines, j):
            return j
    return None


def wrap_feature_dep(out: str) -> str | None:
    """If a feature-flag assert was caused by a GN dep, gate that dep under if (cond)."""
    flag = condition_from_assert_out(out)
    sm = RE_SEE.search(out)
    if not flag or not sm:
        return None
    rel, line_no, dep = sm.group(1), int(sm.group(2)), sm.group(3)
    path = SRC / rel
    if not path.exists():
        return f"MISSING cause {rel}"
    text = ensure_condition_imports(path.read_text(), flag)
    lines = text.splitlines(keepends=True)
    idx = line_no - 1
    if idx < 0 or idx >= len(lines) or dep not in lines[idx]:
        found = None
        for j in range(max(0, idx - 3), min(len(lines), idx + 4)):
            if dep in lines[j]:
                found = j
                break
        if found is None:
            return f"UNHANDLED dep {dep} not at {rel}:{line_no}"
        idx = found

    kind = detect_list_var(lines, idx)
    start_remove = idx
    end_remove = idx
    dep_label = dep.strip().strip('"')
    if dep_label in RETARGET_LABELS:
        indent = re.match(r"^(\s*)", lines[idx]).group(1)
        leaves = RETARGET_LABELS[dep_label]
        block = "".join(f'{indent}"{leaf}",\n' for leaf in leaves)
        lines[idx] = block
        path.write_text("".join(lines))
        return f"OK retarget {rel}:{line_no} {dep} -> {leaves}"

    def prev_nonempty(i):
        j = i - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        return j

    def next_nonempty(i):
        j = i + 1
        while j < len(lines) and not lines[j].strip():
            j += 1
        return j if j < len(lines) else -1

    prev = prev_nonempty(idx)
    nxt = next_nonempty(idx)
    line = lines[idx]
    # Two-line form:
    #   public_deps +=
    #       [ "//foo:bar" ]
    if prev >= 0 and re.search(r"(public_)?deps\s*\+=\s*$", lines[prev]):
        start_remove = prev
        kind = "public_deps" if "public_deps" in lines[prev] else "deps"
        # include a following lone ] if present
        if nxt >= 0 and lines[nxt].strip() == "]":
            end_remove = nxt
    elif re.search(r"(public_)?deps\s*\+=\s*\[\s*$", line):
        # deps += [
        #   "//foo:bar",
        # ]
        # only if this list contains just our dep
        kind = "public_deps" if "public_deps" in line else "deps"
        # find closing ]
        close = None
        depth = 0
        items = []
        for j in range(idx, len(lines)):
            depth += lines[j].count("[") - lines[j].count("]")
            if j > idx:
                for m in re.finditer(r'"[^"]+"', lines[j]):
                    items.append(m.group(0))
            if depth <= 0:
                close = j
                break
        if close is not None and items == [dep]:
            end_remove = close
        else:
            # multi-item list: just drop this one line
            start_remove = end_remove = idx
            # kind already set; will add if-block after the list or at target end
            kind = "public_deps" if "public_deps" in line else kind
            # look back for list header kind
            for j in range(idx, -1, -1):
                if "public_deps" in lines[j] and "[" in lines[j]:
                    kind = "public_deps"
                    break
                if re.search(r"\bdeps\s*\+?=?\s*\[", lines[j]) or re.search(r"\bdeps\s*=", lines[j]):
                    kind = "deps"
                    break
            # remove trailing comma on previous item later if needed — GN allows trailing commas
            # After delete, insert block at target close (legacy path)
            removed = "".join(lines[start_remove : end_remove + 1])
            del lines[start_remove : end_remove + 1]
            # find enclosing target close
            start = find_named_block_start(lines, min(start_remove, len(lines) - 1))
            if start is None:
                fb = insert_gate_only_after_list(lines, min(idx, len(lines)-1), kind, dep, flag)
                if fb is None:
                    return f"UNHANDLED no enclosing target for {rel}:{line_no}"
                lines = fb
                path.write_text("".join(lines))
                return (
                    f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (after list)\n"
                    f"  removed: {dep}"
                )
            indent = re.match(r"^(\s*)", lines[start]).group(1)
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
                fb = insert_gate_only_after_list(lines, min(idx, len(lines)-1), kind, dep, flag)
                if fb is None:
                    return f"UNHANDLED no closing brace in {rel}"
                lines = fb
                path.write_text("".join(lines))
                return (
                    f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (after list)\n"
                    f"  removed: {dep}"
                )
            block = (
                f"{indent}  if ({flag}) {{\n"
                f"{indent}    {kind} += [ {dep} ]\n"
                f"{indent}  }}\n"
            )
            lines.insert(close, block)
            path.write_text("".join(lines))
            return (
                f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (from list)\n"
                f"  removed: {removed.strip()}"
            )
    else:
        # One-liner: deps += [ "foo" ]  or a list item "foo",
        if re.search(r"(public_)?deps\s*\+=\s*\[", line):
            kind = "public_deps" if "public_deps" in line else "deps"
            # wrap this one-liner in place
        elif dep in line and (line.strip().startswith('"') or line.strip().startswith("[")):
            # list item; decide if it's the only item of a list that started above
            for j in range(idx, -1, -1):
                if "public_deps" in lines[j] and "[" in lines[j]:
                    kind = "public_deps"
                    break
                if re.search(r"\bdeps\s*", lines[j]) and "[" in lines[j]:
                    kind = "deps"
                    break
            # If this list has only our dep (plus maybe close bracket on next line)
            # treat as in-place wrap of the whole list? Safer: list-item path below
            # Count items in current list
            # Find list start
            list_start = None
            depth = 0
            for j in range(idx, -1, -1):
                depth += lines[j].count("]") - lines[j].count("[")
                if depth > 0 or ("[" in lines[j] and depth <= 0):
                    # crossed out or found start
                    if "[" in lines[j]:
                        list_start = j
                        break
            if list_start is not None:
                items = []
                d = 0
                list_end = None
                for j in range(list_start, len(lines)):
                    d += lines[j].count("[") - lines[j].count("]")
                    for m in re.finditer(r'"[^"]+"', lines[j]):
                        items.append(m.group(0))
                    if d <= 0 and j >= list_start:
                        list_end = j
                        break
                if list_end is not None and items == [dep] and re.search(r"(public_)?deps\s*\+?=", lines[list_start]):
                    start_remove = list_start
                    end_remove = list_end
                    kind = "public_deps" if "public_deps" in lines[list_start] else "deps"
                else:
                    # multi-item: drop the line and append if-block at target end
                    removed = lines.pop(idx)
                    start = find_named_block_start(lines, min(idx, len(lines) - 1))
                    if start is None:
                        fb = insert_gate_only_after_list(lines, min(idx, len(lines)-1), kind, dep, flag)
                        if fb is None:
                            return f"UNHANDLED no enclosing target for {rel}:{line_no}"
                        lines = fb
                        path.write_text("".join(lines))
                        return (
                            f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (after list)\n"
                            f"  removed: {dep}"
                        )
                    indent = re.match(r"^(\s*)", lines[start]).group(1)
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
                        fb = insert_gate_only_after_list(lines, min(idx, len(lines)-1), kind, dep, flag)
                        if fb is None:
                            return f"UNHANDLED no closing brace in {rel}"
                        lines = fb
                        path.write_text("".join(lines))
                        return (
                            f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (after list)\n"
                            f"  removed: {dep}"
                        )
                    block = (
                        f"{indent}  if ({flag}) {{\n"
                        f"{indent}    {kind} += [ {dep} ]\n"
                        f"{indent}  }}\n"
                    )
                    lines.insert(close, block)
                    path.write_text("".join(lines))
                    return (
                        f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (from list)\n"
                        f"  removed: {removed.strip()}"
                    )

    # In-place wrap of the whole (single-dep) assignment.
    indent = re.match(r"^(\s*)", lines[start_remove]).group(1)
    block = (
        f"{indent}if ({flag}) {{\n"
        f"{indent}  {kind} += [ {dep} ]\n"
        f"{indent}}}\n"
    )
    removed = "".join(lines[start_remove : end_remove + 1])
    lines[start_remove : end_remove + 1] = [block]
    path.write_text("".join(lines))
    return (
        f"OK wrap {rel}:{line_no} {dep} under if ({flag}) as {kind} += (in place)\n"
        f"  removed: {removed.strip()}"
    )




RE_UNDEF_DEPS = re.compile(
    r"^ERROR at //([^:]+):(\d+):\d+: Undefined identifier\.\n\s*((?:public_)?deps)\s*\+=",
    re.M,
)


def fix_undefined_deps_plus(out: str) -> str | None:
    """Guard a deps += that runs when deps was never assigned (e.g. inside a false if)."""
    m = RE_UNDEF_DEPS.search(out)
    if not m:
        return None
    rel, line_no, kind = m.group(1), int(m.group(2)), m.group(3)
    path = SRC / rel
    if not path.exists():
        return f"MISSING {rel}"
    lines = path.read_text().splitlines(keepends=True)
    idx = line_no - 1
    if idx < 0 or idx >= len(lines) or kind not in lines[idx] or "+=" not in lines[idx]:
        found = None
        for j in range(max(0, idx - 2), min(len(lines), idx + 3)):
            if kind in lines[j] and "+=" in lines[j]:
                found = j
                break
        if found is None:
            return f"UNHANDLED deps += not at {rel}:{line_no}"
        idx = found
    # already guarded?
    blob = "".join(lines[max(0, idx - 4) : idx])
    if f"if (!defined({kind}))" in blob:
        return f"ALREADY guarded {kind} at {rel}:{line_no}"
    indent = re.match(r"^(\s*)", lines[idx]).group(1)
    guard = (
        f"{indent}if (!defined({kind})) {{\n"
        f"{indent}  {kind} = []\n"
        f"{indent}}}\n"
    )
    lines.insert(idx, guard)
    path.write_text("".join(lines))
    return f"OK guard !defined({kind}) before += at {rel}:{idx+1}"



RE_UNRESOLVED = re.compile(r"^ERROR Unresolved dependencies\.", re.M)
RE_NEEDS = re.compile(
    r"^(//[^\s(]+)\([^)]*\)\n  needs (//[^\s(]+)\(",
    re.M,
)
RE_TARGET_DEF = re.compile(
    r"^\s*(?:source_set|component|static_library|shared_library|group|executable|test|mojom|grit|action|copy|generated_file|proto_library|bundle_data)\s*\(\s*\"([^\"]+)\"\s*\)",
    re.M,
)


def split_gn_label(label: str) -> tuple[str, str]:
    body = label[2:] if label.startswith("//") else label
    if ":" in body:
        path, name = body.rsplit(":", 1)
    else:
        path, name = body, Path(body).name
    return path, name


def find_target_line(lines: list[str], name: str) -> int | None:
    """Line index of rule("name"), including grit("foo") when name is foo_grit."""
    pat = re.compile(
        rf'^\s*[A-Za-z_][A-Za-z0-9_]*\s*\(\s*"{re.escape(name)}"\s*\)'
    )
    for i, line in enumerate(lines):
        if line.lstrip().startswith("#"):
            continue
        if pat.search(line):
            return i
    if name.endswith("_grit"):
        base = name[: -len("_grit")]
        pat2 = re.compile(rf'^\s*grit\s*\(\s*"{re.escape(base)}"\s*\)')
        for i, line in enumerate(lines):
            if line.lstrip().startswith("#"):
                continue
            if pat2.search(line):
                return i
    return None


def parse_if_condition_at(lines: list[str], j: int) -> str | None:
    """If lines[j] starts an if (COND) {, return COND (possibly multi-line)."""
    if not re.match(r"^\s*if\s*\(", lines[j]):
        return None
    buf = []
    d = 0
    started = False
    found_brace = False
    for k in range(j, min(len(lines), j + 12)):
        buf.append(lines[k])
        for ch in lines[k]:
            if ch == "(":
                d += 1
                started = True
            elif ch == ")":
                d -= 1
            elif ch == "{" and started and d <= 0:
                found_brace = True
                break
        if found_brace or (started and d <= 0 and "{" in "".join(buf)):
            text = "".join(buf)
            mm = re.search(r"if\s*\((.*)\)\s*\{", text, re.S)
            if mm:
                return re.sub(r"\s+", " ", mm.group(1)).strip()
            break
    return None


def matching_close(lines: list[str], start: int) -> int | None:
    """Line index of the } that closes the first { at or after start."""
    depth = 0
    started = False
    for k in range(start, len(lines)):
        for ch in lines[k]:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth <= 0:
                    return k
    return None


def enclosing_if_condition(lines: list[str], idx: int) -> tuple[int, str] | None:
    """Return (line_idx, condition) of the nearest if whose block contains idx.

    Walk backward and keep an if only when its matching close is at or after
    idx. This ignores prior sibling ifs (e.g. a closed if (safe_browsing_mode)
    that appears above first_run_flow_controller inside if (enable_dice_support)).
    """
    found = None
    for j in range(idx, -1, -1):
        cond = parse_if_condition_at(lines, j)
        if not cond:
            continue
        close = matching_close(lines, j)
        if close is not None and close >= idx:
            found = (j, cond)
            break  # nearest (innermost) enclosing if
    return found


def line_mentions_label(line: str, miss: str, name: str, same_file: bool) -> bool:
    """True if this GN line lists miss, including :name in the same BUILD.gn."""
    s = line.strip()
    if not s or s.startswith("#"):
        return False
    if miss in line:
        return True
    path_only = miss.rsplit(":", 1)[0] if ":" in miss[2:] else miss
    if f'"{path_only}"' in line:
        return True
    if same_file and name and f'":{name}"' in line:
        return True
    return False





def target_span(lines: list[str], name: str) -> tuple[int, int] | None:
    start = find_target_line(lines, name)
    if start is None:
        return None
    close = matching_close(lines, start)
    if close is None:
        return None
    return start, close


def all_enclosing_ifs(lines: list[str], idx: int) -> list[tuple[int, str]]:
    """Innermost-first list of ifs whose blocks contain idx."""
    found: list[tuple[int, str]] = []
    for j in range(idx, -1, -1):
        cond = parse_if_condition_at(lines, j)
        if not cond:
            continue
        close = matching_close(lines, j)
        if close is not None and close >= idx:
            found.append((j, cond))
    return found


def already_gated(lines: list[str], idx: int, cond: str) -> bool:
    """True if idx is inside an if whose condition equals cond.

    Uses matching braces so a prior sibling if (cond) { ... } is ignored.
    """
    want = re.sub(r"\s+", " ", cond).strip()
    for _, c in all_enclosing_ifs(lines, idx):
        if re.sub(r"\s+", " ", c).strip() == want:
            return True
    return False


def dep_token_on_line(line: str, miss: str, name: str, same_file: bool) -> str:
    """Quoted GN dep token as it appears on line, preferring the original form."""
    if same_file and name and f'":{name}"' in line:
        return f'":{name}"'
    path_only = miss.rsplit(":", 1)[0] if ":" in miss[2:] else miss
    if f'"{path_only}"' in line and miss not in line:
        return f'"{path_only}"'
    if f'"{miss}"' in line:
        return f'"{miss}"'
    if miss in line:
        return f'"{miss}"'
    return f'":{name}"' if same_file and name else f'"{miss}"'


def widen_if_condition(cond: str) -> str | None:
    if "enable_ios_desktop_views" in cond:
        return None
    if "!is_ios" in cond:
        return cond.replace("!is_ios", "(!is_ios || enable_ios_desktop_views)")
    # Only widen multi-platform desktop allow-lists. A lone is_mac / is_linux
    # / is_win guards OS-specific code; wrap the incoming dep instead.
    if RE_PLAT_COND.match(cond):
        return f"{cond} || (is_ios && enable_ios_desktop_views)"
    return None


def is_feature_condition(cond: str) -> bool:
    # True if the condition mentions a feature/flag rather than only platforms.
    tokens = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", cond)
    plat = BUILTIN_IDENTS | {"is_win", "is_mac", "is_linux", "is_chromeos", "is_android", "is_ios", "is_fuchsia", "is_desktop_android"}
    return any(tok not in plat for tok in tokens)


def build_path_for_label_path(path: str) -> Path:
    p = SRC / path
    if p.is_dir():
        return p / "BUILD.gn"
    if path.endswith(".gni") or path.endswith(".gn"):
        return SRC / path
    # default
    return SRC / path / "BUILD.gn"


def fix_unresolved_deps(out: str) -> str | None:
    """Widen platform ifs that hide needed targets, or wrap feature-gated deps."""
    if not RE_UNRESOLVED.search(out):
        return None
    pairs = RE_NEEDS.findall(out)
    if not pairs:
        return None
    # unique missing, keep one from-label per missing
    missing_from: dict[str, list[str]] = {}
    for frm, miss in pairs:
        missing_from.setdefault(miss, []).append(frm)
    results = []
    changed = False
    for miss, frms in missing_from.items():
        path_s, name = split_gn_label(miss)
        bpath = build_path_for_label_path(path_s)
        if not bpath.exists():
            results.append(f"MISSING file for {miss} -> {bpath}")
            continue
        text = bpath.read_text()
        lines = text.splitlines(keepends=True)
        tline = find_target_line(lines, name)
        if tline is None:
            results.append(f"UNHANDLED no target {name} in {bpath.relative_to(SRC)}")
            continue
        enc = enclosing_if_condition(lines, tline)
        if enc is None:
            results.append(f"UNHANDLED no enclosing if for {miss}")
            continue
        if_idx, cond = enc
        if "if (" not in lines[if_idx] and "if(" not in lines[if_idx]:
            results.append(f"UNHANDLED if_idx not an if for {miss} at {if_idx+1}: {lines[if_idx].strip()[:80]}")
            continue
        widened = widen_if_condition(cond)
        if widened:
            # replace the if condition in-place
            # handle single-line if (cond) {
            line = lines[if_idx]
            if re.match(r"^\s*if\s*\(.+\)\s*\{\s*$", line.rstrip()):
                indent = re.match(r"^(\s*)", line).group(1)
                lines[if_idx] = f"{indent}if ({widened}) {{\n"
            else:
                # multi-line: rewrite from if_idx through the line with ) {
                end = if_idx
                while end < len(lines) and ") {" not in lines[end] and "){" not in lines[end]:
                    end += 1
                if end >= len(lines):
                    results.append(f"UNHANDLED multi-line if for {miss}")
                    continue
                indent = re.match(r"^(\s*)", lines[if_idx]).group(1)
                lines[if_idx : end + 1] = [f"{indent}if ({widened}) {{\n"]
            # ensure ui.gni import
            new_text = ensure_ui_import("".join(lines))
            bpath.write_text(new_text)
            rel = str(bpath.relative_to(SRC))
            results.append(f"OK widen if in {rel} for {name}: {cond} -> {widened}")
            changed = True
            continue
        if "enable_ios_desktop_views" in cond:
            results.append(f"UNHANDLED already-widened if still missing {miss}: {cond}")
            continue
        # Wrap incoming deps under the enclosing if (feature flag or a
        # single-OS / other condition we must not widen onto iOS).
        # Only rewrite mentions inside each from-target, and skip mentions
        # that are already inside an if (cond) (sibling ifs do not count).
        wrapped_any = False
        for frm in frms:
            fpath_s, frm_name = split_gn_label(frm)
            fpath = build_path_for_label_path(fpath_s)
            if not fpath.exists():
                results.append(f"MISSING from file {frm}")
                continue
            ftext = fpath.read_text()
            ftext = ensure_condition_imports(ftext, cond)
            flines = ftext.splitlines(keepends=True)
            same_file = fpath.resolve() == bpath.resolve()
            span = target_span(flines, frm_name)
            if span is None:
                results.append(
                    f"UNHANDLED no from-target {frm_name} in {fpath.relative_to(SRC)} (from {frm})"
                )
                continue
            start_i, end_i = span
            idx = None
            for i in range(start_i, end_i + 1):
                if not line_mentions_label(flines[i], miss, name, same_file):
                    continue
                if already_gated(flines, i, cond):
                    continue
                idx = i
                break
            if idx is None:
                results.append(
                    f"UNHANDLED dep {miss} not in {frm} within {fpath.relative_to(SRC)}"
                )
                continue
            kind = detect_list_var(flines, idx)
            token = dep_token_on_line(flines[idx], miss, name, same_file)
            flines.pop(idx)
            # Insert the gated dep just before the from-target's close,
            # which may have shifted back by one line after the pop.
            close = end_i - 1 if idx < end_i else end_i
            # Recompute close if braces drifted; prefer the target close.
            recomputed = matching_close(flines, start_i)
            if recomputed is not None:
                close = recomputed
            indent = re.match(r"^(\s*)", flines[start_i]).group(1)
            block = (
                f"{indent}  if ({cond}) {{\n"
                f"{indent}    {kind} += [ {token} ]\n"
                f"{indent}  }}\n"
            )
            flines.insert(close, block)
            fpath.write_text("".join(flines))
            results.append(
                f"OK wrap {fpath.relative_to(SRC)} {miss} in {frm_name} under if ({cond})"
            )
            wrapped_any = True
            changed = True
        if not wrapped_any:
            results.append(f"UNHANDLED feature cond {cond} for {miss}")
        continue
    if not changed:
        return "UNHANDLED unresolved (no edits)\n" + "\n".join(results)
    return "OK unresolved\n" + "\n".join(results)


def main() -> int:
    global FLAG_IMPORTS
    print("Indexing .gni flag definitions...", flush=True)
    FLAG_IMPORTS = build_flag_index()
    print(f"Indexed {len(FLAG_IMPORTS)} flags", flush=True)
    with LOG.open("a") as f:
        f.write("\n===== new walk session =====\n")
        f.write(f"flag index size {len(FLAG_IMPORTS)}\n")
    for i in range(1, MAX_ITERS + 1):
        rc, out = run_gn_gen()
        with LOG.open("a") as f:
            f.write(f"\n===== iter {i} rc={rc} =====\n")
            f.write(out[-8000:])
        if rc == 0:
            print(f"GN_OK after {i} gen(s)", flush=True)
            print(out[-500:])
            with CHANGES.open("a") as f:
                f.write(f"GN_OK after {i} gens\n{out[-300:]}\n")
            return 0
        m = RE_ERROR.search(out)
        if m:
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
            continue
        undef = RE_UNDEF.search(out)
        if undef:
            rel, line_no, ident = undef.group(1), int(undef.group(2)), undef.group(3)
            print(f"iter {i}: undefined {ident} at //{rel}:{line_no}", flush=True)
            result = add_flag_import(rel, ident)
            print(result, flush=True)
            with CHANGES.open("a") as f:
                f.write(f"iter {i}: import {ident} into {rel}\n{result}\n")
            if result.startswith("OK import"):
                continue
            # maybe a wrap leftover; try feature wrap too
            wrapped = wrap_feature_dep(out)
            if wrapped and wrapped.startswith("OK"):
                print(wrapped, flush=True)
                continue
            print(out[-3000:])
            return 5
        fixed = fix_undefined_deps_plus(out)
        if fixed and fixed.startswith("OK"):
            print(fixed, flush=True)
            with CHANGES.open("a") as f:
                f.write(f"iter {i}: {fixed}\n")
            continue
        unresolved = fix_unresolved_deps(out)
        if unresolved and unresolved.startswith("OK"):
            print(unresolved, flush=True)
            with CHANGES.open("a") as f:
                f.write(f"iter {i}: {unresolved}\n")
            continue
        print(f"STOP non-assert GN error at iter {i}")
        print(out[-5000:])
        with CHANGES.open("a") as f:
            f.write(f"STOP iter {i} non-assert\n{out[-5000:]}\n")
        return 2
    print(f"HIT MAX_ITERS={MAX_ITERS}")
    return 4


if __name__ == "__main__":
    sys.exit(main())
