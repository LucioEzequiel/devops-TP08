#!/bin/bash
set -uo pipefail
ERRORS=0
ok()   { echo "  [OK]   $1"; }
fail() { echo "  [FAIL] $1"; ERRORS=$((ERRORS+1)); }

check_http() {
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$1" 2>/dev/null || echo "000")
    [ "$CODE" = "200" ] && ok "$2 -> HTTP $CODE" || fail "$2 -> HTTP $CODE"
}

echo "=== Verificacion del stack de monitoreo ==="
echo ""
echo "--- Servicios ---"
for svc in notes-db notes-backend notes-frontend prometheus grafana node-exporter cadvisor; do
    ST=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "no encontrado")
    [ "$ST" = "running" ] && ok "$svc" || fail "$svc -> $ST"
done
echo ""
echo "--- Endpoints ---"
check_http "http://localhost:9091/-/healthy" "Prometheus"
check_http "http://localhost:3000/api/health" "Grafana"
check_http "http://localhost:9100/metrics" "Node-Exporter"
check_http "http://localhost:5000/metrics" "Backend /metrics"
echo ""
echo "--- Targets en Prometheus ---"
python3 - << 'PYEOF'
import urllib.request, json
try:
    with urllib.request.urlopen("http://localhost:9091/api/v1/targets", timeout=5) as r:
        data = json.loads(r.read())
    for t in data["data"]["activeTargets"]:
        job = t["labels"].get("job", "?")
        health = t["health"]
        icon = "[OK]  " if health == "up" else "[FAIL]"
        print(f"  {icon} {job} -> {health}")
except Exception as e:
    print(f"  [FAIL] No se pudo consultar Prometheus: {e}")
PYEOF
echo ""
[ "$ERRORS" -eq 0 ] && echo "Stack de monitoreo OK" || echo "$ERRORS servicios con problemas"
