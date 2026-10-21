# Uploads backups with the VM's own identity (instance principal). Built by bin/backup.sh.
FROM python:3.12-slim
RUN pip install --no-cache-dir 'oci>=2.130,<3'
COPY upload.py /upload.py
USER nobody
ENTRYPOINT ["python", "-I", "/upload.py"]
