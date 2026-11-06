from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


def workspace(test: unittest.TestCase) -> Path:
    directory = Path(__file__).resolve().parents[1] / 'build/python-tests'
    directory.mkdir(parents=True, exist_ok=True)
    temporary = tempfile.TemporaryDirectory(dir=directory)
    test.addCleanup(temporary.cleanup)
    return Path(temporary.name)


class Repository:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.counter = 0
        root.mkdir()
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Release Tests')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'tag.gpgsign', 'false')
        self.git('config', 'core.hooksPath', '/dev/null')
        (root / '.gitignore').write_text('/build/\n', encoding='utf-8')
        self.commit()
        self.git('tag', '-a', '0.1.0', '-m', 'Release 0.1.0')

    def git(self, *arguments: str) -> str:
        result = subprocess.run(
            ['git', '-C', str(self.root), *arguments], check=True, capture_output=True, text=True,
        )
        return result.stdout.strip()

    def commit(self) -> None:
        self.counter += 1
        (self.root / 'source.txt').write_text(str(self.counter), encoding='utf-8')
        self.git('add', '.')
        environment = os.environ.copy()
        environment['GIT_AUTHOR_DATE'] = environment['GIT_COMMITTER_DATE'] = f'@{1700000000 + self.counter} +0000'
        subprocess.run(
            ['git', '-C', str(self.root), 'commit', '-qm', f'Commit {self.counter}'],
            check=True, capture_output=True, env=environment,
        )
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
