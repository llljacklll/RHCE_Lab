#!/bin/bash
# Valida una entrada en crontab
local node="$1"; local job_str="$2"; local user="${3:-ansible}"
docker exec "$node" crontab -l -u "$user" 2>/dev/null | grep -qF "$job_str" && echo "OK" || echo "FAIL"
