"""Configure signed stable repositories in the target selected by Calamares."""

from pathlib import Path
import os
import tempfile


def atomic_write(path, content):
    fd, name = tempfile.mkstemp(prefix=".shreeos-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def configure_sources(root_mount):
    if not isinstance(root_mount, str) or not root_mount:
        raise ValueError("Calamares did not provide a target root")
    root = Path(root_mount)
    if not root.is_absolute():
        raise ValueError("The installation target must be absolute")
    root = root.resolve(strict=True)
    if root == Path(root.anchor):
        raise ValueError("Refusing to configure repositories on the running root")

    # All paths must resolve inside the target, including parent directories.
    def target(relative):
        path = root / relative
        resolved = path.resolve()
        if not resolved.is_relative_to(root):
            raise ValueError(f"Target path escapes the installation: {relative}")
        if path.is_symlink():
            raise ValueError(f"Unexpected target symlink: {relative}")
        return path

    apt = target("etc/apt")
    if not apt.is_dir():
        raise ValueError("The installation has no APT configuration")
    policy = target("etc/shreeos/firmware-policy").read_text().strip()
    areas = {"free": "main", "standard": "main non-free-firmware"}.get(policy)
    if areas is None:
        raise ValueError("Unknown image firmware policy")
    keyring = target("usr/share/keyrings/debian-archive-keyring.gpg")
    if not keyring.is_file() or not keyring.stat().st_size:
        raise ValueError("The Debian signing keyring is missing")

    sources_dir = target("etc/apt/sources.list.d")
    sources_dir.mkdir(exist_ok=True)
    destination = target("etc/apt/sources.list.d/debian.sources")
    # Disable the build/live-media sources while preserving them for diagnosis.
    # This module runs only on a freshly unpacked installation.
    previous = [target("etc/apt/sources.list")]
    previous.extend(target(str(p.relative_to(root))) for p in sources_dir.iterdir()
                    if p.suffix in (".list", ".sources") and p != destination)
    content = (
        "Types: deb\nURIs: https://deb.debian.org/debian\n"
        "Suites: trixie trixie-updates\n"
        f"Components: {areas}\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n\n"
        "Types: deb\nURIs: https://security.debian.org/debian-security\n"
        "Suites: trixie-security\n"
        f"Components: {areas}\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n"
    )
    # Write the replacement before disabling any old source. A full disk or
    # failed write must not leave the target without its existing repositories.
    atomic_write(destination, content)
    for path in previous:
        if path.exists():
            path.replace(path.with_name(path.name + ".shreeos-install-backup"))


def pretty_name():
    return "Configure ShreeOS software updates"


def run():
    import libcalamares

    try:
        configure_sources(libcalamares.globalstorage.value("rootMountPoint"))
    except (OSError, ValueError) as error:
        return ("Could not configure software updates", str(error))
    return None
