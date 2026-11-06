"""Write a .tar.gz of one Docker volume to stdout. SQLite files are copied with the backup API, so a
database that is being written is still saved consistently. Run by bin/backup.sh with the volume at /src."""
from pathlib import Path
import sqlite3
import sys
import tarfile
import tempfile

SQLITE_SUFFIXES = {'.sqlite3', '.sqlite', '.db'}
SKIP_SUFFIXES = ('-wal', '-shm', '-journal')

src = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp, tarfile.open(fileobj=sys.stdout.buffer, mode='w|gz') as tar:
    for path in sorted(src.rglob('*')):
        name = str(path.relative_to(src))
        if path.is_dir() or path.name.endswith(SKIP_SUFFIXES):
            continue
        if path.suffix in SQLITE_SUFFIXES:
            copy = Path(tmp) / 'copy'
            with sqlite3.connect(path, timeout=30) as source, sqlite3.connect(copy) as target:
                source.backup(target)
                # Public query points are transient cache, not personal settings or durable config.
                # Keep them out of long-lived backups as well as the running TTL store.
                tables={r[0] for r in target.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if path.name == 'ocean.sqlite3' and 'points' in tables:
                    for table in ('snapshots','schedule'):
                        if table in tables:
                            target.execute(f"DELETE FROM {table} WHERE area GLOB 'point_*'")
                    target.execute('DELETE FROM points')
            tar.add(copy, arcname=name)
            copy.unlink()
        else:
            tar.add(path, arcname=name)
