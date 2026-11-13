# Shared preflight for uml-darwin launches on the 16 GB mini.
# Sourced by launch-ab-uml-darwin.sh, launch-benches-bin.sh, and
# launch-atomic-stress-bin.sh.
#
# Start-of-run gates (2026-11-13, after sticky ~1.2G swap from the
# 0022-cas SIGPROF blowup proved not to be active paging):
#   - refuse if another uml-darwin is running (UML_ALLOW_OVERLAP=1)
#   - refuse if reclaimable headroom (vm_stat free + speculative +
#     inactive + purgeable) is below guest mem + ~2G margin, or if
#     swap-outs are actively accumulating (UML_ALLOW_HEAVY=1)
# Stale swap used is not a gate. JIT cache budget is a cap, not an
# immediate allocation (healthy 4G-guest / 8G-budget TTP peaked ~4.4G
# RSS), so the full budget is not reserved as physical headroom.
#
# Mid-run: launch scripts TERM the guest if swap used grows more than
# 2048M above UML_SWAP_USED_AT_START, which this preflight exports.
# Override: UML_ALLOW_HEAVY=1.
#
# UML_PREFLIGHT_GUEST_MEM default 4G; UML_PREFLIGHT_MARGIN_MB default 2048.
if [ "${UML_ALLOW_OVERLAP:-0}" != 1 ]; then
  if /usr/bin/pgrep -f '[u]ml-darwin' >/dev/null; then
    echo "preflight: refusing, uml-darwin already running (UML_ALLOW_OVERLAP=1 to override)" >&2
    /usr/bin/pgrep -lf '[u]ml-darwin' >&2 || true
    exit 2
  fi
fi

_swap_used=$(sysctl vm.swapusage | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
export UML_SWAP_USED_AT_START=${_swap_used:-0}

if [ "${UML_ALLOW_HEAVY:-0}" != 1 ]; then
  _guest="${UML_PREFLIGHT_GUEST_MEM:-4G}"
  _margin="${UML_PREFLIGHT_MARGIN_MB:-2048}"
  if ! /usr/bin/python3 - "$_guest" "$_margin" << 'PY'
import re, subprocess, sys, time

def parse_size_mb(s, default):
    if not s:
        return default
    m = re.match(r"^\s*([0-9.]+)\s*([KMG]i?)?\s*$", str(s), re.I)
    if not m:
        return default
    n = float(m.group(1))
    u = (m.group(2) or "M")[:1].upper()
    mul = {"K": 1.0 / 1024.0, "M": 1.0, "G": 1024.0}.get(u, 1.0)
    return n * mul

def vm_stat():
    out = subprocess.check_output(["vm_stat"], text=True)
    ps = 16384
    m = re.search(r"page size of (\d+)", out)
    if m:
        ps = int(m.group(1))
    def grab(label):
        m = re.search(rf"{re.escape(label)}:\s+(\d+)", out)
        return int(m.group(1)) if m else 0
    return {
        "pagesize": ps,
        "free": grab("Pages free"),
        "inactive": grab("Pages inactive"),
        "speculative": grab("Pages speculative"),
        "purgeable": grab("Pages purgeable"),
        "swapouts": grab("Swapouts"),
        "swapins": grab("Swapins"),
    }

def free_pct():
    try:
        out = subprocess.check_output(["memory_pressure"], text=True, errors="replace")
    except Exception:
        return None
    m = re.search(r"System-wide memory free percentage:\s*(\d+)", out)
    return int(m.group(1)) if m else None

guest_mb = parse_size_mb(sys.argv[1], 4096.0)
margin_mb = parse_size_mb(sys.argv[2], 2048.0)
need_mb = guest_mb + margin_mb

a = vm_stat()
time.sleep(2)
b = vm_stat()
delta_swapouts = b["swapouts"] - a["swapouts"]
headroom_pages = b["free"] + b["speculative"] + b["inactive"] + b["purgeable"]
headroom_mb = headroom_pages * b["pagesize"] / (1024.0 * 1024.0)
pct = free_pct()
swap = subprocess.check_output(["sysctl", "vm.swapusage"], text=True).strip()

print(
    "preflight: headroom={:.0f}M (free+spec+inact+purge) need={:.0f}M "
    "(guest={:.0f}M + margin={:.0f}M) swapouts_delta={} in 2s free%={} {}".format(
        headroom_mb, need_mb, guest_mb, margin_mb, delta_swapouts,
        pct if pct is not None else "n/a", swap
    )
)

# Active swap-out: more than 16 pages (~256 KiB at 16K pages) in the 2s window.
if delta_swapouts > 16:
    print(
        "preflight: refusing, active swap-out rate ({} pages in 2s) "
        "(UML_ALLOW_HEAVY=1 to override)".format(delta_swapouts),
        file=sys.stderr,
    )
    sys.exit(3)

if headroom_mb + 0.5 < need_mb:
    print(
        "preflight: refusing, reclaimable headroom {:.0f}M < need {:.0f}M "
        "(UML_ALLOW_HEAVY=1 to override)".format(headroom_mb, need_mb),
        file=sys.stderr,
    )
    sys.exit(3)

# Belt-and-suspenders: Apple's free-percentage under real pressure.
if pct is not None and pct < 15:
    print(
        "preflight: refusing, memory_pressure free {}% < 15% "
        "(UML_ALLOW_HEAVY=1 to override)".format(pct),
        file=sys.stderr,
    )
    sys.exit(3)
PY
  then
    exit 3
  fi
  unset _guest _margin
fi
unset _swap_used
