#!/usr/bin/env python3
"""Score uml-darwin TTP screenshots from tesseract OCR (and optionally OCR them).

Times are seconds after process start. Chrome is the first real browser
window after the empty labwc desktop (New Tab, Loading, or example.com).
Boot-console OCR, including a bare "chromium" on the Linux tty, is ignored.
English is the English body of example.com; full is Example Domain title plus
that body; learn is "Learn more".

Usage:
  score-ttp-shots.py --t0 HHMMSS --ready-utc HH:MM:SS TAG_MANUAL_DIR
  score-ttp-shots.py --memlog persist-memory-ab-TAG-....log --session session-ab-TAG-....log TAG_MANUAL_DIR
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def norm(text: str) -> str:
    text = text.lower().replace("\u201c", '"').replace("\u201d", '"')
    return re.sub(r"\s+", " ", text)


def is_boot(text: str) -> bool:
    hits = 0
    for s in (
        "linux version",
        "initrd memory",
        "virtio_gpu",
        "[drm]",
        "printk",
        "freeing initrd",
        "zone ranges",
        "calibrating delay",
        "host memory window",
        "key type asymmetric",
        "smp: brought up",
    ):
        if s in text:
            hits += 1
    if len(re.findall(r"\[\s*\d+\.\d+\]", text)) >= 6:
        hits += 2
    return hits >= 2


def classify(text: str) -> dict:
    boot = is_boot(text)
    newtab = "new tab" in text or "newtab" in text
    loading = (
        "loading" in text
        or "transferring data" in text
        or "waiting for example" in text
    )
    example_title = "example domain" in text
    example_url = "example.com" in text
    english_body = (
        "this domain is for use" in text
        or "documentation examples" in text
        or "without needing permission" in text
        or "this is not a service" in text
    )
    learn = "learn more" in text
    firefox = ("firefox" in text or "mozilla" in text) and not boot
    fallback = (not boot) and (
        "darwin uml virtio-gpu" in text
        and (
            "new tab" in text
            or "example.com" in text
            or " + " in text
            or " x |" in text
        )
    )
    chrome = (not boot) and (
        newtab or loading or example_title or example_url or firefox or fallback
    )
    why = []
    if boot:
        why.append("boot")
    if newtab:
        why.append("newtab")
    if loading:
        why.append("loading")
    if example_title:
        why.append("example")
    if english_body:
        why.append("english")
    if learn:
        why.append("learn")
    return {
        "boot": boot,
        "chrome": chrome,
        "english": english_body,
        "full": example_title and english_body,
        "learn": learn,
        "why": why,
    }


def hhmmss_to_secs(value: str) -> int:
    value = value.replace(":", "")
    if len(value) != 6 or not value.isdigit():
        raise ValueError(f"bad time {value!r}")
    return int(value[0:2]) * 3600 + int(value[2:4]) * 60 + int(value[4:6])


def stamp_from_name(name: str) -> str | None:
    m = re.search(r"t-(\d{6})-", name)
    return m.group(1) if m else None


def t0_from_memlog(path: Path) -> str:
    first = path.read_text(errors="replace").splitlines()[0]
    m = re.search(r"(\d{2}):(\d{2}):(\d{2})", first)
    if not m:
        raise SystemExit(f"no time in {path}")
    return "".join(m.groups())


def ready_utc_from_session(path: Path) -> str | None:
    text = path.read_text(errors="replace")
    m = re.search(
        r"===DESKTOP_READY=== Fri Nov \d+ (\d{2}):(\d{2}):(\d{2}) UTC", text
    )
    if not m:
        m = re.search(r"===DESKTOP_READY=== .* (\d{2}):(\d{2}):(\d{2}) UTC", text)
    if not m:
        return None
    h, mi, s = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    h = (h - 5) % 24  # America/New_York standard time as used on the mini
    return f"{h:02d}{mi:02d}{s:02d}"


def ocr_missing(shotdir: Path) -> None:
    ocrdir = shotdir / "ocr"
    ocrdir.mkdir(exist_ok=True)
    jobs = []
    for png in sorted(shotdir.glob("t-*.png")):
        out = ocrdir / png.stem
        if not (ocrdir / f"{png.stem}.txt").exists():
            jobs.append((png, out))
    for png, out in jobs:
        subprocess.run(
            ["tesseract", str(png), str(out), "-l", "eng", "--psm", "6"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def score(shotdir: Path, t0s: str, ready_s: str | None) -> dict:
    t0 = hhmmss_to_secs(t0s)
    ocrdir = shotdir / "ocr"
    events = []
    for txt in sorted(ocrdir.glob("t-*.txt")):
        stamp = stamp_from_name(txt.name)
        if not stamp:
            continue
        rel = hhmmss_to_secs(stamp) - t0
        ev = classify(norm(txt.read_text(errors="replace")))
        ev["stamp"] = stamp
        ev["rel"] = rel
        events.append(ev)

    def first(pred):
        for ev in events:
            if ev["rel"] < 0:
                continue
            if pred(ev):
                return ev
        return None

    chrome = first(lambda e: e["chrome"])
    english = first(lambda e: e["english"])
    full = first(lambda e: e["full"])
    learn = first(lambda e: e["learn"])
    ready = None
    if ready_s:
        ready = hhmmss_to_secs(ready_s) - t0
    net = (full["rel"] - chrome["rel"]) if chrome and full else None
    return {
        "t0": t0s,
        "ready": ready,
        "chrome": None if chrome is None else chrome["rel"],
        "english": None if english is None else english["rel"],
        "full": None if full is None else full["rel"],
        "learn": None if learn is None else learn["rel"],
        "net": net,
        "chrome_stamp": "" if chrome is None else chrome["stamp"],
        "english_stamp": "" if english is None else english["stamp"],
        "full_stamp": "" if full is None else full["stamp"],
        "learn_stamp": "" if learn is None else learn["stamp"],
        "why": chrome["why"] if chrome else [],
        "nshots": len(events),
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("shotdir", type=Path)
    ap.add_argument("--t0", help="process-start HHMMSS or HH:MM:SS")
    ap.add_argument("--ready", help="READY HHMMSS or HH:MM:SS in the user's zone")
    ap.add_argument("--ready-utc", help="DESKTOP_READY clock time in UTC, converted -5")
    ap.add_argument("--memlog", type=Path)
    ap.add_argument("--session", type=Path)
    ap.add_argument("--ocr", action="store_true", help="run tesseract on missing shots")
    args = ap.parse_args(argv)
    shotdir = args.shotdir
    if not shotdir.is_dir():
        print(f"missing shotdir {shotdir}", file=sys.stderr)
        return 2
    t0s = args.t0
    if args.memlog:
        t0s = t0_from_memlog(args.memlog)
    if not t0s:
        print("need --t0 or --memlog", file=sys.stderr)
        return 2
    t0s = t0s.replace(":", "")
    ready_s = args.ready.replace(":", "") if args.ready else None
    if args.ready_utc:
        raw = args.ready_utc.replace(":", "")
        hh, mm, ss = int(raw[0:2]), int(raw[2:4]), int(raw[4:6])
        ready_s = f"{(hh - 5) % 24:02d}{mm:02d}{ss:02d}"
    if args.session and not ready_s:
        ready_s = ready_utc_from_session(args.session)
    if args.ocr:
        ocr_missing(shotdir)
    row = score(shotdir, t0s, ready_s)
    print(
        "tag={name} t0={t0} ready={ready} chrome={chrome} english={english} "
        "full={full} learn={learn} net={net} chrome_stamp={chrome_stamp} "
        "english_stamp={english_stamp} full_stamp={full_stamp} "
        "learn_stamp={learn_stamp} why={why} nshots={nshots}".format(
            name=shotdir.name, **row
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
