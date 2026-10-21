"""Upload one backup folder to Object Storage with the VM's own identity, and delete backups older
than BACKUP_KEEP_DAYS. Needs the policy in README「バックアップ」. Run by bin/backup.sh."""
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import sys

import oci

folder, prefix = Path(sys.argv[1]), sys.argv[2]
bucket = os.environ.get('BACKUP_BUCKET') or 'chuck-backups'
keep = timedelta(days=int(os.environ.get('BACKUP_KEEP_DAYS') or 14))
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
client = oci.object_storage.ObjectStorageClient(config={'region': signer.region}, signer=signer)
namespace = client.get_namespace().data
size = 0
for path in sorted(folder.iterdir()):
    with path.open('rb') as body:
        client.put_object(namespace, bucket, f'{prefix}/{path.name}', body)
    size += path.stat().st_size
old = datetime.now(timezone.utc) - keep
removed = 0
for item in oci.pagination.list_call_get_all_results(client.list_objects, namespace, bucket, fields='timeCreated').data.objects:
    if item.time_created < old:
        client.delete_object(namespace, bucket, item.name)
        removed += 1
print(f'uploaded {prefix} ({size / 1e6:.1f} MB) to {bucket}; removed {removed} objects older than {keep.days} days')
