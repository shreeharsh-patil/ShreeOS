#!/usr/bin/env python3
"""shreeos-audit -- machine-readable audit tool for the ShreeOS distribution.

This tool answers, in a form CI can diff and a human can read, the questions
that determine whether a ShreeOS ISO is actually a desktop distribution or
merely a kernel wrapped around a development sysroot.

It deliberately uses only the Python standard library so it can run on a
stock GitHub runner with no package installation.

Subcommands
-----------
  repo    Audit the source tree: pinned sources, checksums, workflows,
          component layout, and build-system wiring.
  rootfs  Audit an assembled target root filesystem directory.
  iso     Audit a built ISO: boot assets, payload classification, and a
          recursive inventory of the live filesystem it carries.

Every subcommand writes a JSON document (`--json`) and a human summary
(`--text`). Exit status is 0 when the audit ran, 1 on a usage/IO error.
Findings are reported, not judged: a distribution at an early phase should
produce many "missing" findings without the tool failing the build.
"""
from __future__ import annotations

import argparse
import collections
import fnmatch
import gzip
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys

SECTOR = 2048
S_IFMT = 0o170000
S_IFREG = 0o100000
S_IFDIR = 0o040000
S_IFLNK = 0o120000
S_IFCHR = 0o020000
S_IFBLK = 0o060000

# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------


def human(n: int) -> str:
    """Render a byte count in the MiB/GiB form used throughout the reports."""
    if n is None:
        return "unknown"
    step = 1024.0
    value = float(n)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < step or unit == "GiB":
            return "%.2f %s" % (value, unit) if unit != "B" else "%d B" % n
        value /= step
    return "%.2f GiB" % value


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def parse_build_conf(path: str) -> dict:
    """Extract the exported shell variables from build.conf without sourcing it.

    Sourcing build.conf would execute arbitrary code and require bash; this is a
    pure text parse so the audit tool is safe to run on any checkout. Values
    that reference other variables (${DISTRO_VERSION%%-*}) are resolved with a
    bounded substitution pass so reported values are real, not `${...}` text.
    """
    values: dict = {}
    pattern = re.compile(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
    for line in read_text(path).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        match = pattern.match(line)
        if not match:
            continue
        name, raw = match.group(1), match.group(2).strip()
        if raw.startswith('"'):
            closing = raw.find('"', 1)
            if closing < 0:
                continue
            value = raw[1:closing]
        elif raw.startswith("'"):
            closing = raw.find("'", 1)
            if closing < 0:
                continue
            value = raw[1:closing]
        else:
            # Unquoted: drop any trailing `# comment`.
            value = re.split(r"\s+#", raw, maxsplit=1)[0].strip()
        values[name] = value

    # Resolve ${OTHER} references, including the common ${VAR%%suffix} and
    # ${VAR#prefix} shell parameter expansions, with a bounded iteration count
    # so a self-referential value cannot loop forever.
    ref_pattern = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(##?|%{1,2})([^{}]*))?\}")

    def glob_matches(text: str, pattern: str) -> bool:
        """Shell-style glob test, used by the # / ## / % / %% operators.

        The operand is a pattern, not a literal (``${VER%%-*}``), so a plain
        substring split would silently return the input unchanged.
        """
        if not pattern:
            return True
        return fnmatch.fnmatchcase(text, pattern)

    def expand(text: str) -> str:
        def replace(match):
            name, operator, operand = match.group(1), match.group(2), match.group(3)
            base = values.get(name, "")
            if not operator:
                return base
            if not operand:
                return base
            if operator in ("##", "#"):
                # Strip longest (# #) or shortest (#) matching prefix.
                indices = range(0, len(base) + 1) if operator == "##" \
                    else range(len(base), -1, -1)
                for cut in indices:
                    if glob_matches(base[:cut], operand):
                        return base[cut:]
                return base
            # Strip longest (%%) or shortest (%) matching suffix.
            indices = range(len(base), -1, -1) if operator == "%%" \
                else range(0, len(base) + 1)
            for cut in indices:
                if glob_matches(base[cut:], operand):
                    return base[:cut]
            return base
        for _ in range(8):
            expanded = ref_pattern.sub(replace, text)
            if expanded == text:
                break
            text = expanded
        return text

    for _ in range(8):
        changed = False
        for key, value in list(values.items()):
            new_value = expand(value)
            if new_value != value:
                values[key] = new_value
                changed = True
        if not changed:
            break
    return values


def parse_manifest(path: str) -> list:
    """Parse a ShreeOS source manifest.

    Two formats exist in the tree and both must be audited identically:

    * tab-separated rows -- `name  version  url  sha256 [flags]`
      (base-system/packages.list, desktop/graphics/packages.list)
    * shell assignments  -- `NAME_URL=...` / `NAME_SHA256="..."`
      (kernel/sources.list, desktop/wm/sources.list), which are sourced by the
      build scripts rather than read as rows.

    The shell form is paired up by convention: any `*_URL` variable is matched
    with the `*_SHA256` variable sharing its prefix.
    """
    if not os.path.isfile(path):
        return []
    lines = read_text(path).splitlines()

    # -- shell assignment format -----------------------------------------
    assignments = {}
    has_assignment = False
    for line in lines:
        match = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=\"?'?([^\"'\n]*)"
                         r"\"?'?\s*(?:#.*)?$", line)
        if match and "=" in line:
            assignments[match.group(1)] = match.group(2).strip()
            has_assignment = True
    if has_assignment:
        entries = []
        for key in sorted(assignments):
            if not key.endswith("_URL"):
                continue
            name = key[:-4]
            url = assignments[key]
            sha = assignments.get(name + "_SHA256", "")
            problem = None
            if not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
                problem = "missing or malformed %s_SHA256" % name
            elif re.fullmatch(r"0{64}", sha):
                problem = "placeholder all-zero checksum: source is not pinned"
            elif not url.startswith("https://"):
                problem = "source URL is not HTTPS"
            entries.append({"line": 0, "name": name, "version": "", "url": url,
                            "sha256": sha, "valid": problem is None,
                            "problem": problem})
        return entries

    # -- tab-separated format --------------------------------------------
    entries = []
    for lineno, line in enumerate(lines, start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            entries.append({"line": lineno, "name": fields[0].strip(),
                            "version": "", "url": "", "sha256": "",
                            "valid": False,
                            "problem": "malformed row (%d columns, expected >= 4 "
                                       "tab-separated: name/version/url/sha256)"
                                       % len(fields)})
            continue
        name, version, url, sha = (f.strip() for f in fields[:4])
        problem = None
        if not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
            problem = "checksum is not 64 hex characters"
        elif re.fullmatch(r"0{64}", sha):
            problem = "placeholder all-zero checksum: source is not pinned"
        elif not url.startswith("https://"):
            problem = "source URL is not HTTPS"
        entries.append({"line": lineno, "name": name, "version": version,
                        "url": url, "sha256": sha,
                        "valid": problem is None, "problem": problem})
    return entries


# --------------------------------------------------------------------------
# ISO 9660 (+ Rock Ridge, + El Torito) reader
# --------------------------------------------------------------------------


def _both16(buf, off):
    return buf[off] | (buf[off + 1] << 8)


def _both32(buf, off):
    return (buf[off] | (buf[off + 1] << 8) |
            (buf[off + 2] << 16) | (buf[off + 3] << 24))


class IsoImage:
    """Minimal read-only ISO 9660 directory walker.

    Implemented in-tree rather than shelling out to xorriso so the audit runs
    on a runner with no ISO tooling installed, and reads the image the same way
    BIOS/UEFI firmware would.
    """

    def __init__(self, path: str):
        self.path = path
        self.handle = open(path, "rb")
        self.files = []          # (display_name, size, lba, is_dir)
        self.volume_id = self.publisher = self.preparer = self.app_id = ""
        self.rock_ridge = False
        self.el_torito = []
        self._parse()

    def close(self):
        self.handle.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def _sector(self, lba: int, count: int = 1) -> bytes:
        self.handle.seek(lba * SECTOR)
        return self.handle.read(count * SECTOR)

    def _parse(self):
        pvd = boot_record = None
        for index in range(16, 80):
            data = self._sector(index)
            if len(data) < 8 or data[1:6] != b"CD001":
                break
            kind = data[0]
            if kind == 255:
                break
            if kind == 1:
                pvd = data
            elif kind == 0 and boot_record is None:
                boot_record = data
        if pvd is None:
            raise ValueError("no ISO 9660 primary volume descriptor found")
        self.volume_id = pvd[40:72].decode("latin-1").strip()
        self.publisher = pvd[318:446].decode("latin-1").strip()
        self.preparer = pvd[446:574].decode("latin-1").strip()
        self.app_id = pvd[574:702].decode("latin-1").strip()
        if boot_record is not None:
            self._parse_el_torito(boot_record)
        root = pvd[156:190]
        self._walk(_both32(root, 2), _both32(root, 10), "", 0)

    def _parse_el_torito(self, sector):
        if len(sector) < 72:
            return
        catalog = self._sector(_both32(sector, 0x47))
        for off in range(0, len(catalog), 32):
            entry = catalog[off:off + 32]
            if len(entry) < 32 or entry[0] == 0:
                break
            indicator = entry[0]
            kind = indicator & 0x0F
            if kind == 3:
                # Validation entry: not a real boot image, so it is recorded
                # separately instead of being counted as a 0-byte payload.
                self.el_torito.append({"type": "validation", "sectors": 0, "bytes": 0})
            elif kind in (1, 2):
                bootable = "no-emul" if not indicator & 0x80 else "emul"
                if kind == 2:
                    bootable += " (bootable)"
                self.el_torito.append({
                    "type": bootable,
                    "sectors": _both16(entry, 2),
                    "bytes": _both16(entry, 2) * SECTOR,
                })

    def _walk(self, lba, size, prefix, depth):
        if size == 0 or depth > 24:
            return
        data = self._sector(lba, max(1, (size + SECTOR - 1) // SECTOR))[:size]
        pos = 0
        while pos < len(data):
            record_len = data[pos]
            if record_len == 0:
                nxt = ((pos // SECTOR) + 1) * SECTOR
                if nxt <= pos:
                    break
                pos = nxt
                continue
            record = data[pos:pos + record_len]
            if len(record) < record_len or record_len < 34:
                pos += record_len
                continue
            flags = record[25]
            name_len = record[32]
            if name_len == 1 and record[33] in (0, 1):
                pos += record_len
                continue
            is_dir = bool(flags & 0x02)
            name = record[33:33 + name_len].decode("latin-1").split(";")[0]
            path = prefix + name
            cursor = 33 + name_len + (name_len % 2)
            while cursor + 4 <= len(record):
                slen = record[cursor]
                if slen == 0 or cursor + slen > len(record):
                    break
                if record[cursor + 1:cursor + 2] == b"N":
                    name = record[cursor + 5:cursor + slen].decode("utf-8", "replace")
                    self.rock_ridge = True
                    path = prefix + name
                    break
                cursor += slen
            if is_dir:
                self.files.append((path + "/", 0, _both32(record, 2), True))
                self._walk(_both32(record, 2), _both32(record, 10), path + "/", depth + 1)
            else:
                self.files.append((path, _both32(record, 10), _both32(record, 2), False))
            pos += record_len

    def extract(self, entry) -> bytes:
        _name, size, lba, _isdir = entry
        self.handle.seek(lba * SECTOR)
        return self.handle.read(size)

    def find(self, *needles) -> object:
        """Locate a file by any case-insensitive path component.

        ISO 9660 mangles names unless Rock Ridge is present: everything is
        uppercased and a ``;1`` version suffix is appended, and images written
        with no version get a bare trailing ``.``. Matching on a normalised
        basename avoids reporting a present kernel as absent.
        """
        wanted = [n.upper() for n in needles]
        for entry in self.files:
            if entry[3]:
                continue
            base = entry[0].rsplit("/", 1)[-1]
            if base.endswith(";1"):
                base = base[:-2]
            base = base.rstrip(".").upper()
            if base in wanted:
                return entry
        return None


# --------------------------------------------------------------------------
# cpio (newc) + SquashFS readers
# --------------------------------------------------------------------------


def parse_newc(data: bytes) -> list:
    """Parse a SVR4 'newc' cpio archive into entry dicts.

    Used to inventory the rootfs the current ISO carries inside its initramfs,
    so the audit can report what actually ships rather than what the build
    scripts intended to ship.
    """
    entries = []
    index = 0
    total = len(data)
    while index < total - 110:
        if data[index:index + 6] != b"070701":
            index += 1
            continue
        base = index

        def field(offset, _b=base):
            return int(data[_b + offset:_b + offset + 8], 16)

        mode = field(14)
        file_size = field(54)
        name_size = field(94)
        name = data[base + 110:base + 110 + name_size - 1].decode("utf-8", "replace")
        header_end = 110 + name_size
        header_end += (-header_end) % 4
        file_start = base + header_end
        file_start += (-file_start) % 4
        entries.append({
            "name": name,
            "size": file_size,
            "mode": mode,
            "type": (mode & S_IFMT) >> 12,
        })
        index = file_start + file_size
        index += (-index) % 4
        if name == "TRAILER!!!":
            break
    return entries


def parse_squashfs(data: bytes) -> dict:
    """Read a SquashFS 4.0 little-endian superblock.

    Only the superblock is decoded, so a multi-gigabyte live image can be
    described in constant memory.
    """
    if len(data) < 96 or data[0:4] != b"hsqs":
        raise ValueError("not a little-endian SquashFS 4.0 image")
    fields = struct.unpack_from("<10I", data, 8)
    inode_count, mkfs_time, block_size, fragment_count, compression = fields[:5]
    block_log, flags, id_count, major, minor = fields[5:10]
    root_inode, bytes_used = struct.unpack_from("<2Q", data, 48)
    return {
        "version": "%d.%d" % (major, minor),
        "compression_id": compression,
        "compression": {1: "gzip", 2: "lzma", 3: "lzo", 4: "xz", 5: "lz4",
                        6: "zstd"}.get(compression, "unknown(%d)" % compression),
        "block_size": block_size,
        "block_log": block_log,
        "inode_count": inode_count,
        "fragment_count": fragment_count,
        "id_count": id_count,
        "bytes_used": bytes_used,
        "mkfs_time": mkfs_time,
    }


# --------------------------------------------------------------------------
# Root filesystem classification
# --------------------------------------------------------------------------

# Categories that decide whether a rootfs resembles a desktop distribution.
# Order matters: the first matching pattern wins, so specific patterns are
# listed before generic ones.
CATEGORIES = [
    ("static_archives", r"\.a$"),
    ("kernel_modules", r"\.ko(\.[a-z0-9]+)?$"),
    ("shared_objects", r"\.so(\.[0-9.]+)?$"),
    ("firmware", r"/lib/firmware/|\.fw$|\.bin$"),
    ("fonts", r"\.(ttf|otf|ttc|pcf|bdf|pfb|pfm|t1|type1)$"),
    ("desktop_entries", r"\.desktop$"),
    ("icons", r"/icons/|/pixmaps/"),
    ("man_pages", r"/man/"),
    ("documentation", r"/doc/|\.txt$|\.md$|/info/"),
    ("locale", r"/locale/"),
    ("zoneinfo", r"/zoneinfo/"),
    ("x11_modules", r"/xorg/modules/"),
    ("x11_libraries", r"/lib/X11/|/libxcb\."),
    ("shell_scripts", r"\.(sh|bash)$"),
    ("executables", r""),
]

# Binaries that a normal desktop distribution cannot boot without. Used to
# turn the audit into an actionable gap list rather than a file listing.
DESKTOP_REQUIREMENTS = [
    ("init_system", ["sbin/init", "usr/lib/systemd/systemd", "usr/bin/systemctl"]),
    ("shell", ["usr/bin/bash", "bin/bash"]),
    ("package_manager", ["usr/bin/lpm", "bin/lpm"]),
    ("account_database", ["etc/passwd", "etc/shadow", "etc/group"]),
    ("networking", ["usr/sbin/NetworkManager", "usr/bin/nmcli", "sbin/udhcpc",
                    "usr/bin/udhcpc"]),
    ("dns_resolver", ["usr/bin/systemd-resolved", "sbin/resolvconf"]),
    ("firewall", ["usr/sbin/nft", "sbin/nft"]),
    ("audio_server", ["usr/bin/pipewire", "usr/bin/pulseaudio"]),
    ("bluetooth", ["usr/libexec/bluetooth/bluetoothd", "usr/bin/bluetoothctl"]),
    ("graphics_server", ["usr/lib/xorg/Xorg", "usr/bin/X"]),
    ("vulkan_loader", ["usr/lib/libvulkan.so.1"]),
    ("mesa_driver", ["usr/lib/dri/swrast_dri.so", "usr/lib/dri/virtio_gpu_dri.so",
                     "usr/lib/dri/amdgpu_dri.so", "usr/lib/dri/i965_dri.so",
                     "usr/lib/dri/zink_dri.so"]),
    ("desktop_portal", ["usr/libexec/shree-xdg-desktop-portal",
                       "usr/libexec/xdg-desktop-portal"]),
    ("display_manager", ["usr/sbin/shreed-gdm", "usr/bin/shreed-login",
                         "sbin/getty", "usr/bin/getty"]),
    ("font_config", ["etc/fonts/fonts.conf"]),
    ("locale_archiver", ["usr/bin/locale-gen", "usr/bin/localedef"]),
    ("certificate_store", ["etc/ssl/certs/ca-certificates.crt"]),
    ("sudo", ["usr/bin/sudo"]),
    ("pam", ["lib/security/pam_unix.so", "usr/lib/security/pam_unix.so"]),
    ("kernel_modules_dir", ["lib/modules"]),
]


def classify_entry(name: str, size: int, mode: int) -> str:
    """Bucket a single rootfs file for the report."""
    path = "/" + name.lstrip("./")
    for label, pattern in CATEGORIES:
        if label == "executables":
            break
        if re.search(pattern, path):
            return label
    if (mode & S_IFMT) == S_IFREG and (mode & 0o111):
        return "executables"
    return "other"


def summarize_entries(entries: list) -> dict:
    """Aggregate cpio entries into the counts/sizes the report needs."""
    regular = [e for e in entries if e["type"] == (S_IFREG >> 12)]
    summary = {
        "total_entries": len(entries),
        "regular_files": len(regular),
        "directories": sum(1 for e in entries if e["type"] == (S_IFDIR >> 12)),
        "symlinks": sum(1 for e in entries if e["type"] == (S_IFLNK >> 12)),
        "device_nodes": sum(1 for e in entries
                           if e["type"] in ((S_IFCHR >> 12), (S_IFBLK >> 12))),
        "regular_bytes": sum(e["size"] for e in regular),
        "executables": sum(1 for e in regular if e["mode"] & 0o111),
        "categories": {},
        "largest": [],
        "present": set(),
    }
    buckets = collections.defaultdict(lambda: {"count": 0, "bytes": 0})
    present = set()
    for entry in entries:
        path = "/" + entry["name"].lstrip("./")
        present.add(path)
        if entry["type"] == (S_IFDIR >> 12):
            # Record every ancestor so directory-based probes (e.g. the
            # kernel module tree) resolve without unpacking the archive.
            parts = path.strip("/").split("/")
            for depth in range(1, len(parts) + 1):
                present.add("/" + "/".join(parts[:depth]))
    for entry in regular:
        label = classify_entry(entry["name"], entry["size"], entry["mode"])
        buckets[label]["count"] += 1
        buckets[label]["bytes"] += entry["size"]
    summary["present"] = present
    summary["categories"] = dict(sorted(buckets.items()))
    summary["largest"] = [
        {"path": "/" + e["name"].lstrip("./"), "bytes": e["size"]}
        for e in sorted(regular, key=lambda x: -x["size"])[:40]
    ]
    return summary


def audit_repo(root: str) -> dict:
    """Audit the ShreeOS source tree: pins, checksums, layout, CI wiring."""
    conf_path = os.path.join(root, "build.conf")
    conf = parse_build_conf(conf_path) if os.path.isfile(conf_path) else {}
    version_file = os.path.join(root, "VERSION")
    if os.path.isfile(version_file):
        conf.setdefault("DISTRO_VERSION", read_text(version_file).strip())

    # -- pinned sources with checksum status ------------------------------
    manifests = {}
    for name in ("base-system/packages.list", "desktop/graphics/packages.list",
                 "desktop/wm/sources.list", "kernel/sources.list"):
        path = os.path.join(root, name)
        entries = parse_manifest(path)
        if entries:
            manifests[name] = {
                "count": len(entries),
                "valid": sum(1 for e in entries if e["valid"]),
                "invalid": [e for e in entries if not e["valid"]],
            }

    # -- repository layout -----------------------------------------------
    # Build output (build/, out/) is gitignored scratch space, not source, so
    # counting it would make the report useless as a source-tree description.
    skip_dirs = {"build", "out", ".git", "__pycache__"}
    layout = {}
    for name in sorted(os.listdir(root)):
        full = os.path.join(root, name)
        if name.startswith(".") or name in skip_dirs:
            continue
        if os.path.isdir(full):
            files = 0
            for _dirpath, _dirnames, filenames in os.walk(full):
                files += len(filenames)
            layout[name] = {"type": "dir", "files": files}
        else:
            layout[name] = {"type": "file", "bytes": os.path.getsize(full)}

    # -- GitHub Actions ---------------------------------------------------
    workflows = []
    wf_dir = os.path.join(root, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for name in sorted(os.listdir(wf_dir)):
            if not name.endswith((".yml", ".yaml")):
                continue
            text = read_text(os.path.join(wf_dir, name))
            workflows.append({
                "name": name,
                "bytes": len(text),
                "jobs": len(re.findall(r"^  [A-Za-z0-9_-]+:$", text, re.M)),
                "continue_on_error": "continue-on-error" in text,
                "suppresses_failures": "|| true" in text,
            })

    # -- git provenance ---------------------------------------------------
    git = {}
    try:
        git["commit"] = subprocess.check_output(
            ["git", "-C", root, "rev-parse", "HEAD"], text=True,
            stderr=subprocess.DEVNULL).strip()
        git["branch"] = subprocess.check_output(
            ["git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD"], text=True,
            stderr=subprocess.DEVNULL).strip()
        git["describe"] = subprocess.check_output(
            ["git", "-C", root, "describe", "--tags", "--always"], text=True,
            stderr=subprocess.DEVNULL).strip()
    except Exception as exc:                       # not a git checkout
        git["error"] = str(exc)

    return {
        "kind": "repo",
        "distribution": {
            "name": conf.get("DISTRO_NAME"),
            "id": conf.get("DISTRO_ID"),
            "version": conf.get("DISTRO_VERSION"),
            "codename": conf.get("DISTRO_CODENAME"),
        },
        "toolchain": {
            "triplet": conf.get("SHREEOS_TARGET_TRIPLET"),
            "arch": conf.get("SHREEOS_ARCH"),
            "gcc": conf.get("VER_GCC"),
            "binutils": conf.get("VER_BINUTILS"),
            "glibc": conf.get("VER_GLIBC"),
        },
        "kernel": {
            "version": conf.get("VER_LINUX_KERNEL"),
            "series": conf.get("VER_LINUX_KERNEL"),
        },
        "pinned_sources": manifests,
        "layout": layout,
        "workflows": workflows,
        "git": git,
    }


def audit_rootfs(root: str) -> dict:
    """Audit an assembled target root filesystem directory tree."""
    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        prefix = "" if rel == "." else rel.replace(os.sep, "/") + "/"
        for name in dirnames + filenames:
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                entries.append({"name": prefix + name, "size": 0, "mode": S_IFLNK,
                                "type": S_IFLNK >> 12})
                continue
            try:
                st = os.lstat(full)
            except OSError:
                continue
            entries.append({"name": prefix + name, "size": st.st_size,
                            "mode": st.st_mode, "type": (st.st_mode & S_IFMT) >> 12})
    summary = summarize_entries(entries)
    present = summary.pop("present")

    # Kernel module tree, counted the way a user would count it.
    modules = sorted(p for p in present if p.endswith(".ko") or ".ko." in p)
    firmware = sorted(p for p in present
                      if p.startswith("/lib/firmware/") and
                      p.rsplit("/", 1)[-1].count(".") >= 1)

    # Dynamic-linker audit: catches missing /lib64/ld-linux and a rootfs that
    # only works because the build host's loader was copied in.
    loaders = sorted(p for p in present
                     if "ld-linux" in p or "ld-musl" in p)

    requirements = []
    for label, candidates in DESKTOP_REQUIREMENTS:
        found = [c for c in candidates if ("/" + c) in present]
        requirements.append({
            "component": label,
            "satisfied": bool(found),
            "found": found,
        })

    summary["kernel_modules"] = {"count": len(modules)}
    summary["firmware_files"] = {"count": len(firmware)}
    summary["dynamic_loaders"] = loaders
    return {
        "kind": "rootfs",
        "root": root,
        "uncompressed_bytes": summary["regular_bytes"],
        "summary": summary,
        "requirements": requirements,
    }


def audit_iso(path: str) -> dict:
    """Audit a built ISO, including a recursive inventory of its live root."""
    iso_bytes = os.path.getsize(path)
    report = {"kind": "iso", "path": path, "iso_bytes": iso_bytes}

    # The ISO name encodes the profile (`shreeos-<ver>-<profile>.iso`, or
    # `shreeos-<ver>.iso` for minimal). Coverage gaps are only meaningful
    # relative to the profile, so report it alongside the findings.
    stem = os.path.basename(path).rsplit(".", 1)[0]
    for profile in ("desktop", "server", "security", "minimal"):
        if stem.endswith("-" + profile):
            report["profile"] = profile
            break
    else:
        report["profile"] = "minimal"

    with IsoImage(path) as image:
        report["volume"] = {
            "id": image.volume_id,
            "publisher": image.publisher,
            "preparer": image.preparer,
            "application_id": image.app_id,
            "rock_ridge": image.rock_ridge,
            "el_torito": image.el_torito,
        }

        top = []
        for name, size, _lba, is_dir in image.files:
            if name.count("/") <= 1:
                top.append({"path": name, "bytes": size, "is_dir": is_dir})
        report["top_level"] = sorted(top, key=lambda e: e["path"])

        blobs = {
            "kernel": image.find("bzImage", "vmlinuz"),
            "squashfs": image.find("filesystem.squashfs", "squashfs.img", "rootfs.squashfs"),
        }
        # The live root currently ships inside the initramfs; a future live
        # layout moves it to SquashFS. Record whichever is present.
        blobs["initramfs"] = None
        for entry in image.files:
            if entry[3]:
                continue
            base = entry[0].rsplit("/", 1)[-1].upper()
            if base.startswith("INITRAMFS") or base.startswith("INITRD"):
                blobs["initramfs"] = entry
                break

        report["boot_assets"] = {
            key: ({"path": entry[0], "bytes": entry[1]} if entry else None)
            for key, entry in blobs.items()
        }

        # -- live rootfs: prefer a real SquashFS, else the initramfs blob ---
        live = {}
        if blobs["squashfs"]:
            raw_squash = image.extract(blobs["squashfs"])
            live["format"] = "squashfs"
            live["compressed_bytes"] = len(raw_squash)
            try:
                live["superblock"] = parse_squashfs(raw_squash)
            except ValueError as exc:
                live["format"] = "unreadable-squashfs"
                live["error"] = str(exc)
            del raw_squash
        elif blobs["initramfs"]:
            raw = image.extract(blobs["initramfs"])
            live["format"] = "initramfs-cpio"
            live["compressed_bytes"] = len(raw)
            data = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
            live["uncompressed_bytes"] = len(data)
            live["compression_ratio"] = round(len(raw) / float(len(data)), 3) \
                if data else 0
            summary = summarize_entries(parse_newc(data))
            present = summary.pop("present")
            live["summary"] = summary
            live["requirements"] = [
                {"component": label,
                 "satisfied": any(("/" + c) in present for c in candidates),
                 "found": [c for c in candidates if ("/" + c) in present]}
                for label, candidates in DESKTOP_REQUIREMENTS
            ]
            live["kernel_modules"] = {
                "count": sum(1 for p in present if p.endswith(".ko") or ".ko." in p)
            }
            live["firmware_files"] = {
                "count": sum(1 for p in present
                             if p.startswith("/lib/firmware/") and
                             p.rsplit("/", 1)[-1].count(".") >= 1)
            }
        report["live_rootfs"] = live

    report["sizes"] = {
        "iso_bytes": iso_bytes,
        "iso_human": human(iso_bytes),
    }
    if report.get("boot_assets", {}).get("kernel"):
        report["sizes"]["kernel_bytes"] = report["boot_assets"]["kernel"]["bytes"]
    return report


# --------------------------------------------------------------------------
# Human-readable rendering
# --------------------------------------------------------------------------


def rule(char: str = "=", width: int = 78) -> str:
    return char * width


def render_categories(categories: dict, indent: str = "  ") -> list:
    lines = []
    for label, info in sorted(categories.items(), key=lambda kv: -kv[1]["bytes"]):
        lines.append("%s%-18s %7d files  %12s" % (
            indent, label, info["count"], human(info["bytes"])))
    return lines


def render_requirements(requirements: list, indent: str = "  ") -> list:
    lines = []
    for req in requirements:
        mark = "present" if req["satisfied"] else "MISSING"
        lines.append("%s[%-7s] %-20s %s" % (
            indent, mark, req["component"], ", ".join(req["found"]) or "-"))
    return lines


def render(report: dict) -> str:
    out = [rule(), "ShreeOS audit: %s" % report.get("kind", "unknown"), rule()]

    if report["kind"] == "repo":
        dist = report["distribution"]
        out.append("Distribution : %s %s (%s) codename=%s" % (
            dist.get("name"), dist.get("version"), dist.get("id"),
            dist.get("codename")))
        tool = report["toolchain"]
        out.append("Toolchain    : %s / gcc %s / binutils %s / glibc %s" % (
            tool.get("triplet"), tool.get("gcc"), tool.get("binutils"),
            tool.get("glibc")))
        out.append("Kernel       : %s (%s)" % (
            report["kernel"].get("version"), report["kernel"].get("series")))
        git = report.get("git", {})
        if "commit" in git:
            out.append("Git          : %s (%s, %s)" % (
                git["commit"][:12], git.get("branch"), git.get("describe")))
        out += ["", "PINNED SOURCES"]
        for name, info in sorted(report["pinned_sources"].items()):
            flag = "OK" if not info["invalid"] else "PROBLEM"
            out.append("  %-34s %3d entries  %3d pinned  [%s]" % (
                name, info["count"], info["valid"], flag))
            for bad in info["invalid"]:
                out.append("      line %d: %s -- %s" % (
                    bad["line"], bad["name"], bad["problem"]))
        out += ["", "GITHUB ACTIONS"]
        for flow in report["workflows"]:
            out.append("  %-28s %2d jobs" % (flow["name"], flow["jobs"]))
        out += ["", "REPOSITORY LAYOUT"]
        for name, info in sorted(report["layout"].items()):
            if info["type"] == "dir":
                out.append("  %-30s %6d files" % (name + "/", info["files"]))
        return "\n".join(out)

    if report["kind"] == "rootfs":
        summary = report["summary"]
        out.append("Uncompressed : %s" % human(report["uncompressed_bytes"]))
        out.append("Entries      : %d total, %d regular, %d dirs, %d symlinks, %d devs"
                   % (summary["total_entries"], summary["regular_files"],
                      summary["directories"], summary["symlinks"],
                      summary["device_nodes"]))
        out.append("Executables  : %d" % summary["executables"])
        out.append("Kernel mods  : %d" % summary["kernel_modules"]["count"])
        out.append("Firmware     : %d" % summary["firmware_files"]["count"])
        out.append("Loaders      : %s" %
                   (", ".join(summary["dynamic_loaders"]) or "none"))
        out += ["", "BY CATEGORY"] + render_categories(summary["categories"])
        out += ["", "LARGEST FILES"]
        for item in summary["largest"][:20]:
            out.append("  %12s  %s" % (human(item["bytes"]), item["path"]))
        out += ["", "DESKTOP COMPONENT COVERAGE"] + \
            render_requirements(report["requirements"])
        return "\n".join(out)

    volume = report["volume"]
    out.append("ISO size     : %s" % human(report["iso_bytes"]))
    out.append("Profile      : %s" % report.get("profile", "unknown"))
    out.append("Volume ID    : %s" % volume["id"])
    out.append("Rock Ridge   : %s" % ("yes" if volume["rock_ridge"] else "no"))
    out.append("El Torito    : %s" % ", ".join(
        "%s (%d bytes)" % (e["type"], e["bytes"]) for e in volume["el_torito"]))
    out += ["", "BOOT ASSETS"]
    for key, asset in sorted(report["boot_assets"].items()):
        if asset:
            out.append("  %-10s %12s  %s" % (key, human(asset["bytes"]), asset["path"]))
        else:
            out.append("  %-10s %12s" % (key, "absent"))
    live = report.get("live_rootfs") or {}
    out += ["", "LIVE ROOTFS (%s)" % live.get("format", "none")]
    if live.get("format") == "squashfs":
        sb = live["superblock"]
        out.append("  compressed   : %s" % human(live["compressed_bytes"]))
        out.append("  uncompressed : %s (from superblock)" % human(sb["bytes_used"]))
        out.append("  compression  : %s" % sb["compression"])
        out.append("  inodes       : %d" % sb["inode_count"])
    elif live.get("format") == "initramfs-cpio":
        summary = live["summary"]
        out.append("  compressed   : %s" % human(live["compressed_bytes"]))
        out.append("  uncompressed : %s (ratio %.2fx)" % (
            human(live["uncompressed_bytes"]), live["compression_ratio"]))
        out.append("  entries      : %d total, %d regular, %d executables" % (
            summary["total_entries"], summary["regular_files"], summary["executables"]))
        out.append("  kernel mods  : %d" % live["kernel_modules"]["count"])
        out.append("  firmware     : %d" % live["firmware_files"]["count"])
        out += ["", "  BY CATEGORY"] + \
            render_categories(summary["categories"], indent="    ")
        out += ["", "  LARGEST FILES"]
        for item in summary["largest"][:20]:
            out.append("    %12s  %s" % (human(item["bytes"]), item["path"]))
        out += ["", "  DESKTOP COMPONENT COVERAGE"] + \
            render_requirements(live["requirements"], indent="    ")
    return "\n".join(out)


def main(argv=None) -> int:
    # The output flags are attached to both the top-level parser and every
    # subcommand so that `--json` works before or after the subcommand name.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true",
                        help="emit the report as JSON")
    common.add_argument("--text", action="store_true",
                        help="emit the human-readable summary (default)")
    common.add_argument("--out", help="write the report to this path")

    parser = argparse.ArgumentParser(
        prog="shreeos-audit", parents=[common],
        description="Machine-readable audit of the ShreeOS distribution.")
    sub = parser.add_subparsers(dest="command", required=True)

    repo = sub.add_parser("repo", parents=[common], help="audit the source tree")
    repo.add_argument("--root", default=".", help="repository root")

    rootfs = sub.add_parser("rootfs", parents=[common],
                            help="audit an assembled root filesystem")
    rootfs.add_argument("path", help="path to the root filesystem directory")

    iso = sub.add_parser("iso", parents=[common], help="audit a built ISO image")
    iso.add_argument("path", help="path to the ISO image")

    args = parser.parse_args(argv)

    if args.command == "repo":
        report = audit_repo(os.path.abspath(args.root))
    elif args.command == "rootfs":
        if not os.path.isdir(args.path):
            print("error: not a directory: %s" % args.path, file=sys.stderr)
            return 1
        report = audit_rootfs(os.path.abspath(args.path))
    else:
        if not os.path.isfile(args.path):
            print("error: not a file: %s" % args.path, file=sys.stderr)
            return 1
        report = audit_iso(args.path)

    # Output selection: --out always writes JSON; stdout gets the text summary
    # unless --json was requested. With neither flag, print both so a bare
    # invocation is useful interactively.
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, sort_keys=True, default=str)
            handle.write("\n")
    emit_json = args.json or (not args.text and not args.out)
    emit_text = args.text or (not args.json and not args.out)
    if emit_json:
        print(json.dumps(report, indent=2, sort_keys=True, default=str))
    if emit_text:
        print(render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
