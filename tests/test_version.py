from __future__ import annotations

from pathlib import Path
import plistlib
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))

from release_fixtures import Repository, workspace
from version import SourceVersion, VersionError, check, source_version, stamp


class VersionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.work = workspace(self)
        self.repo = Repository(self.work / 'source')

    def test_exact_tag_and_commit_distance_ignore_other_tags(self) -> None:
        first = source_version(self.repo.root)
        self.assertEqual((first.version, first.build, first.dirty), ('0.1.0', 0, False))
        self.assertEqual(first.revision, self.repo.git('rev-parse', 'HEAD'))
        self.assertEqual(first.time, 1700000001)
        self.repo.commit()
        self.repo.commit()
        for tag in ['latest', '0.2.0-rc.1', 'v0.3.0']:
            self.repo.git('tag', '-a', tag, '-m', tag)
        nightly = source_version(self.repo.root)
        self.assertEqual((nightly.version, nightly.build), ('0.1.0', 2))
        self.repo.git('tag', '-a', '0.1.1', '-m', 'Release 0.1.1')
        stable = source_version(self.repo.root)
        self.assertEqual((stable.version, stable.build), ('0.1.1', 0))
        self.assertGreater(stable.order, nightly.order)

    def test_stamp_refreshes_after_commits_and_tags_without_rewriting_unchanged_files(self) -> None:
        plist = self.repo.root / 'build/SimStore.app/Contents/Info.plist'
        plist.parent.mkdir(parents=True)
        plist.write_bytes(plistlib.dumps({'CFBundleName': 'SimStore', 'LSMinimumSystemVersion': '14.0'}))
        stamp(self.repo.root, plist)
        check(self.repo.root, plist)
        first_mtime = plist.stat().st_mtime_ns
        stamp(self.repo.root, plist)
        self.assertEqual(plist.stat().st_mtime_ns, first_mtime)
        self.repo.commit()
        with self.assertRaisesRegex(VersionError, 'Stale bundle version'):
            check(self.repo.root, plist)
        stamp(self.repo.root, plist)
        self.assertEqual(plistlib.loads(plist.read_bytes())['CFBundleVersion'], '1')
        self.repo.git('tag', '-a', '0.1.1', '-m', 'Release 0.1.1')
        stamp(self.repo.root, plist)
        info = plistlib.loads(plist.read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], '0.1.1')
        self.assertEqual(info['CFBundleVersion'], '0')
        self.assertEqual(info['CFBundleName'], 'SimStore')
        self.assertEqual(info['LSMinimumSystemVersion'], '14.0')

    def test_uncommitted_source_is_recorded(self) -> None:
        (self.repo.root / 'untracked.txt').write_text('Uncommitted', encoding='utf-8')
        self.assertTrue(source_version(self.repo.root).dirty)

    def test_missing_tags_and_shallow_history_fail(self) -> None:
        self.repo.commit()
        clone = self.work / 'shallow'
        subprocess.run(
            ['git', 'clone', '-q', '--depth', '1', self.repo.root.as_uri(), str(clone)],
            check=True, capture_output=True,
        )
        with self.assertRaisesRegex(VersionError, 'Full Git history'):
            source_version(clone)
        self.repo.git('tag', '-d', '0.1.0')
        with self.assertRaisesRegex(VersionError, 'fetch --tags --force'):
            source_version(self.repo.root)

    def test_bundle_version_fields_are_validated(self) -> None:
        valid = source_version(self.repo.root).plist_values()
        for field, value in [
            ('CFBundleVersion', '0.1.0'), ('CFBundleVersion', '01'),
            ('CFBundleVersion', '-1'), ('SimStoreCommitTime', True),
            ('SimStoreRevision', 'main'), ('SimStoreSourceDirty', 'false'),
        ]:
            with self.subTest(field=field, value=value), self.assertRaises(VersionError):
                SourceVersion.from_plist({**valid, field: value})


if __name__ == '__main__':
    unittest.main()
