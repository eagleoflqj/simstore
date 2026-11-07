from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')


class VersionError(ValueError):
    pass


def version_key(value: str) -> tuple[int, int, int]:
    if not isinstance(value, str) or VERSION.fullmatch(value) is None:
        raise VersionError(f'Expected an X.Y.Z version, got {value!r}')
    major, minor, patch = value.split('.')
    return int(major), int(minor), int(patch)


def git(source: Path, *arguments: str) -> str:
    result = subprocess.run(
        ['git', '-C', str(source), *arguments], check=False, capture_output=True, text=True,
    )
    if result.returncode:
        raise VersionError(result.stderr.strip() or 'Git command failed')
    return result.stdout.strip()


def write_if_changed(path: Path, data: bytes) -> None:
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def write_json(path: Path, value: object) -> None:
    write_if_changed(path, (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))


@dataclass(frozen=True)
class SourceVersion:
    version: str
    build: int
    revision: str
    time: int
    dirty: bool

    def __post_init__(self) -> None:
        version_key(self.version)
        for name, value in [('build', self.build), ('time', self.time)]:
            if type(value) is not int or value < 0:
                raise VersionError(f'Expected a nonnegative integer for {name}')
        if not isinstance(self.revision, str) or re.fullmatch(r'[0-9a-f]{40}', self.revision) is None:
            raise VersionError('Expected a full Git commit SHA')
        if type(self.dirty) is not bool:
            raise VersionError('Expected a boolean dirty flag')

    @property
    def order(self) -> tuple[int, int, int, int]:
        return (*version_key(self.version), self.build)

    def plist_values(self) -> dict[str, object]:
        return {
            'CFBundleShortVersionString': self.version,
            'CFBundleVersion': str(self.build),
            'SimStoreRevision': self.revision,
            'SimStoreCommitTime': self.time,
            'SimStoreSourceDirty': self.dirty,
        }

    @classmethod
    def from_plist(cls, info: dict[str, Any]) -> SourceVersion:
        try:
            build = info['CFBundleVersion']
            if not isinstance(build, str) or re.fullmatch(r'0|[1-9][0-9]*', build) is None:
                raise VersionError('Expected a commit count in CFBundleVersion')
            return cls(
                info['CFBundleShortVersionString'], int(build), info['SimStoreRevision'],
                info['SimStoreCommitTime'], info['SimStoreSourceDirty'],
            )
        except KeyError as error:
            raise VersionError(f'Missing bundle version field: {error.args[0]}') from error


def source_version(source: Path) -> SourceVersion:
    if git(source, 'rev-parse', '--is-shallow-repository') == 'true':
        raise VersionError('Full Git history is required; fetch the history and tags before building')
    tags = [tag for tag in git(source, 'tag', '--list').splitlines() if VERSION.fullmatch(tag)]
    if not tags:
        raise VersionError('No stable X.Y.Z tag found; run git fetch --tags --force')
    revision = git(source, 'rev-parse', 'HEAD')
    matches = [argument for tag in tags for argument in ('--match', tag)]
    description = git(source, 'describe', '--tags', '--long', *matches, revision)
    tag, count, _ = description.rsplit('-', 2)
    return SourceVersion(
        tag, int(count), revision, int(git(source, 'show', '-s', '--format=%ct', revision)),
        bool(git(source, 'status', '--porcelain', '--untracked-files=normal')),
    )


def stamp(source: Path, plist: Path) -> None:
    info = plistlib.loads(plist.read_bytes())
    info.update(source_version(source).plist_values())
    write_if_changed(plist, plistlib.dumps(info, sort_keys=False))


def check(source: Path, plist: Path) -> None:
    actual = SourceVersion.from_plist(plistlib.loads(plist.read_bytes()))
    expected = source_version(source)
    if actual != expected:
        raise VersionError(f'Stale bundle version: expected {expected}, got {actual}')


def main() -> int:
    parser = argparse.ArgumentParser(description='Derive bundle versions from stable Git tags.')
    parser.add_argument('command', choices=['describe', 'stamp', 'check'])
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--plist', type=Path)
    args = parser.parse_args()
    if args.command != 'describe' and args.plist is None:
        parser.error('--plist is required for stamp and check')
    try:
        if args.command == 'describe':
            print(json.dumps(asdict(source_version(args.source))))
        elif args.command == 'stamp':
            stamp(args.source, args.plist)
        else:
            check(args.source, args.plist)
    except (VersionError, OSError, plistlib.InvalidFileException) as error:
        print(f'Version error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
