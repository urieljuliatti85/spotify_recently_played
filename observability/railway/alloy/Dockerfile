# Deploy this as its own Railway service with Root Directory set to
# observability/railway/alloy — see ../README.md for the full walkthrough
# and the env vars it needs. grafana/alloy's own image already runs
# `alloy run /etc/alloy/config.alloy` by default, so all this adds is the
# config file.
FROM grafana/alloy:v1.5.1
COPY config.alloy /etc/alloy/config.alloy
