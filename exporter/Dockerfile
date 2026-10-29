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
# /health tra 503 khi vong thu thap bi treo -> `docker ps` hien unhealthy
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
    CMD python3 -c "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','9830'), timeout=8)" || exit 1
ENTRYPOINT ["python3", "/app/pve_ceph_extra_exporter.py", "--remote"]
