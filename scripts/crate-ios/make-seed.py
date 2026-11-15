#!/usr/bin/env python3
"""Build a 1 MiB FAT12 CIDATA seed.img with cloud-init files."""
import os, subprocess, sys, tempfile, shutil
os.environ["COPYFILE_DISABLE"]="1"
from pathlib import Path

SEED, UUID, TZ, USER = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
SETUP = Path(os.environ.get("CRATE_D4_SETUP", Path(__file__).resolve().parent))
PASS = os.environ["CRATE_BENCH_PASS"]  # throwaway local VM password; do not commit it
# Fixed salt so this is reproducible in logs; throwaway local VM password only.
hash_ = subprocess.check_output(
    ["/opt/homebrew/opt/openssl@3/bin/openssl", "passwd", "-6", "-salt", "crat3bencHsalt12", PASS],
    text=True,
).strip()

def read(name: str) -> str:
    return (SETUP / name).read_text()

def yaml_block(text: str, indent: int) -> str:
    pad = " " * indent
    # YAML literal: keep line breaks; indent every line including empties.
    lines = text.splitlines()
    if not lines:
        return pad
    return "\n".join(pad + line if line else pad for line in lines)

user_data = f"""#cloud-config
hostname: debian
users:
  - name: {USER}
    gecos: {USER}
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: "{hash_}"
    groups: [sudo]
ssh_pwauth: true
timezone: {TZ}
write_files:
  - path: /usr/local/bin/crate-bench.sh
    permissions: "0755"
    content: |
{yaml_block(read("crate-bench.sh"), 6)}
  - path: /usr/local/bin/metrics-server.py
    permissions: "0755"
    content: |
{yaml_block(read("metrics-server.py"), 6)}
  - path: /usr/local/bin/install-packages.sh
    permissions: "0755"
    content: |
{yaml_block(read("install-packages.sh"), 6)}
  - path: /usr/local/share/interactive-metrics/index.html
    permissions: "0644"
    content: |
{yaml_block(read("index.html"), 6)}
  - path: /usr/local/share/interactive-metrics/warm.html
    permissions: "0644"
    content: |
{yaml_block(read("warm.html"), 6)}
  - path: /home/{USER}/.config/autostart/crate-bench.desktop
    permissions: "0644"
    content: |
{yaml_block(read("crate-bench.desktop"), 6)}
  - path: /etc/lightdm/lightdm.conf.d/50-autologin.conf
    permissions: "0644"
    content: |
      [Seat:*]
      autologin-user={USER}
      autologin-user-timeout=0
      autologin-session=xfce
      user-session=xfce
runcmd:
  - mkdir -p /home/{USER}/.config/autostart /var/lib/crate /etc/lightdm/lightdm.conf.d
  - chown -R {USER}:{USER} /home/{USER}
  - [ bash, /usr/local/bin/install-packages.sh ]
"""
meta = f"instance-id: {UUID}\nlocal-hostname: debian\n"
vendor = f"""#cloud-config
# Straight into the owner's Xfce session.
write_files:
  - path: /etc/lightdm/lightdm.conf.d/50-autologin.conf
    content: |
      [Seat:*]
      autologin-user={USER}
      autologin-session=xfce
"""

seed_dir = Path(tempfile.mkdtemp(prefix="cidata-"))
try:
    (seed_dir / "user-data").write_text(user_data)
    (seed_dir / "meta-data").write_text(meta)
    (seed_dir / "vendor-data").write_text(vendor)
    seed = Path(SEED)
    seed.unlink(missing_ok=True)
    subprocess.check_call(["dd", "if=/dev/zero", f"of={seed}", "bs=1024", "count=1024", "status=none"])
    # macOS newfs_msdos wants a device, not a regular file.
    out = subprocess.check_output(["hdiutil", "attach", "-nomount", str(seed)], text=True)
    dev = out.split()[0]
    subprocess.check_call(["newfs_msdos", "-F", "12", "-v", "CIDATA", dev])
    mnt = Path("/tmp/k-harness/cidata-mnt")
    mnt.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(["mount", "-t", "msdos", dev, str(mnt)])
    for name in ("user-data", "meta-data", "vendor-data"):
        shutil.copy(seed_dir / name, mnt / name)
    print("SEED files", list(mnt.iterdir()), "user-data bytes", (mnt / "user-data").stat().st_size)
    subprocess.check_call(["umount", str(mnt)])
    subprocess.check_call(["hdiutil", "detach", dev])
    print("SEED_OK", seed, seed.stat().st_size)
finally:
    shutil.rmtree(seed_dir, ignore_errors=True)
