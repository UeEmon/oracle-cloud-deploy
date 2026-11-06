import io
from pathlib import Path
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import unittest

class BackupTests(unittest.TestCase):
    def test_transient_points_excluded_without_changing_live_database(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);src=root/'src';src.mkdir();dbpath=src/'ocean.sqlite3'
            with sqlite3.connect(dbpath) as db:
                db.executescript("CREATE TABLE points(id TEXT);INSERT INTO points VALUES ('point_123');CREATE TABLE snapshots(area TEXT);INSERT INTO snapshots VALUES ('point_123'),('tokyo');CREATE TABLE schedule(area TEXT);INSERT INTO schedule VALUES ('point_123'),('tokyo');CREATE TABLE settings(kind TEXT);INSERT INTO settings VALUES ('weather');")
            script=Path(__file__).resolve().parents[1]/'backup/snapshot.py'
            raw=subprocess.check_output([sys.executable,str(script),str(src)])
            with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
                copy=root/'copy.sqlite3';copy.write_bytes(archive.extractfile('ocean.sqlite3').read())
            with sqlite3.connect(copy) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM points').fetchone()[0],0)
                self.assertEqual(db.execute('SELECT area FROM snapshots').fetchall(),[('tokyo',)])
                self.assertEqual(db.execute('SELECT kind FROM settings').fetchall(),[('weather',)])
            with sqlite3.connect(dbpath) as db:self.assertEqual(db.execute('SELECT count(*) FROM points').fetchone()[0],1)

if __name__=='__main__':unittest.main()
