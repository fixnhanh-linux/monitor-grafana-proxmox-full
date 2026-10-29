# FIX NHANH - pve_ceph_extra_exporter che do REMOTE trong Docker (1 container = 1 cluster)
# Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.
#
#   docker build -t fixnhanh/pve-ceph-exporter exporter/
#   docker run -d --name pve-FPT-HCM --restart unless-stopped -p 9830:9830 \
#       --env-file /etc/pve-ceph-extra-exporter/FPT-HCM.env fixnhanh/pve-ceph-exporter
FROM python:3.12-alpine
COPY pve_ceph_extra_exporter.py /app/pve_ceph_extra_exporter.py
ENV REMOTE=1 PORT=9830 INTERVAL=30 PYTHONUNBUFFERED=1
USER nobody
EXPOSE 9830
ENTRYPOINT ["python3", "/app/pve_ceph_extra_exporter.py", "--remote"]
