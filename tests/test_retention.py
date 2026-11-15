from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backup'))
from retention import expired, scope_of  # noqa: E402

NOW = datetime(2026, 11, 16, tzinfo=timezone.utc)
OLD = NOW - timedelta(days=30)
NEW = NOW - timedelta(days=1)
CUTOFF = NOW - timedelta(days=14)
OBJECTS = [
    ('2026-10-01T180000Z/arn.pgdump', OLD),
    ('2026-11-15T180000Z/arn.pgdump', NEW),
    ('ninegage/2026-10-01T183000Z/ninegage.ngbak', OLD),
    ('ninegage/2026-11-15T183000Z/ninegage.ngbak', NEW),
    ('manual/keep-me.tar.gz', OLD),
]


class RetentionTests(unittest.TestCase):
    def test_scope(self):
        self.assertEqual(scope_of('ninegage/2026-11-15T183000Z'), 'ninegage/')
        self.assertEqual(scope_of('2026-11-15T180000Z'), '')

    def test_ninegage_deletes_only_its_own_folder(self):
        self.assertEqual(expired(OBJECTS, 'ninegage/', CUTOFF), ['ninegage/2026-10-01T183000Z/ninegage.ngbak'])

    def test_chuck_deletes_only_top_level_time_folders(self):
        self.assertEqual(expired(OBJECTS, '', CUTOFF), ['2026-10-01T180000Z/arn.pgdump'])


if __name__ == '__main__':
    unittest.main()
