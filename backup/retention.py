"""Which backups to delete. Each VM deletes only its own backups in the shared bucket:
an upload to '<folder>/<time>' (Nine-Gage's VM: 'ninegage/<time>') owns everything under '<folder>/';
an upload to '<time>' at the top (CHUCK's VM) owns only top-level '<time>/...' folders, never another VM's folder."""
from datetime import datetime
import re

TIME_FOLDER = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{6}Z/')


def scope_of(prefix: str) -> str:
    """The list prefix this upload owns: 'ninegage/' for 'ninegage/<time>', '' for a top-level '<time>'."""
    return prefix.rsplit('/', 1)[0] + '/' if '/' in prefix else ''


def expired(objects, scope: str, cutoff: datetime):
    """Names to delete: older than cutoff and owned by this scope. objects: (name, time_created) pairs."""
    out = []
    for name, created in objects:
        if not name.startswith(scope) or created >= cutoff:
            continue
        # The top-level scope owns only its own time folders, not 'ninegage/...' or anything else.
        if scope == '' and not TIME_FOLDER.match(name):
            continue
        out.append(name)
    return out
