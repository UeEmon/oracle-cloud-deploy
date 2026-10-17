# Reads the tenancy bill with the VM's own identity (instance principal). Built by bin/update-cost.sh.
FROM python:3.12-slim
RUN pip install --no-cache-dir 'oci>=2.130,<3'
COPY oracle_cost.py /oracle_cost.py
USER nobody
ENTRYPOINT ["python", "-I", "/oracle_cost.py"]
