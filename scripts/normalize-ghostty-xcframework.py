#!/usr/bin/env python3
"""Normalize AgentStudio's copied archive names for SwiftPM; never edit vendors."""
import pathlib
import plistlib
import subprocess

framework = pathlib.Path(__file__).resolve().parent.parent / "Frameworks/GhosttyKit.xcframework"
if framework.parent.is_symlink() or framework.is_symlink():
    raise SystemExit("Refusing to normalize a shared framework symlink")
framework_root = framework.resolve(strict=True)
plist_path = framework / "Info.plist"
if plist_path.is_symlink():
    raise SystemExit("Refusing a symlinked framework manifest")
with plist_path.open("rb") as stream:
    metadata = plistlib.load(stream)
for library in metadata["AvailableLibraries"]:
    identifier = library["LibraryIdentifier"]
    if identifier in (".", "..") or pathlib.Path(identifier).name != identifier:
        raise SystemExit(f"Unexpected library identifier: {identifier}")
    directory = framework / identifier
    if directory.is_symlink() or not directory.resolve(strict=True).is_relative_to(framework_root):
        raise SystemExit("Library directory escapes copied framework")
    original = library["LibraryPath"]
    if pathlib.Path(original).name != original or not original.endswith(".a"):
        raise SystemExit(f"Unexpected static archive name: {original}")
    normalized = original if original.startswith("lib") else f"lib{original}"
    archive = directory / original
    destination = directory / normalized
    if archive.is_symlink() or destination.is_symlink():
        raise SystemExit("Refusing a symlinked archive")
    if not archive.resolve(strict=True).is_relative_to(framework_root):
        raise SystemExit("Archive escapes copied framework")
    if normalized != original:
        if destination.exists():
            raise SystemExit("Normalized archive destination already exists")
        archive.rename(destination)
        library["LibraryPath"] = normalized
        if library.get("BinaryPath") == original:
            library["BinaryPath"] = normalized
    subprocess.run(["xcrun", "strip", "-S", str(directory / normalized)], check=True)
with plist_path.open("wb") as stream:
    plistlib.dump(metadata, stream, sort_keys=False)
