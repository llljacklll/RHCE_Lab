# core/wait.sh -- 'lab.sh wait': poll SSH desde control (leccion F8/F9)
# En arranque frio el sshd de los nodos tarda y la bateria a los 8s
# fallaba. Poll rotando usuario ''/root@/ansible@ contra node1..node3
# hasta que todos aceptan SSH. RC 0=listos. Def presupuesto: 120s.
function lab_wait() {
    local timeout="${RHCE_WAIT_TIMEOUT:-120}"
    local nodes="node1 node2 node3"
    local users="node root ansible"
    local pend="$nodes" rest n u tgt ok t=0
    echo "[i] Esperando SSH en nodos (presupuesto ${timeout}s)..."
    while [ -n "$pend" ] && [ "$t" -lt "$timeout" ]; do
        rest=""
        for n in $pend; do
            ok=""
            for u in $users; do
                tgt="$n"
                [ "$u" != "node" ] && tgt="${u}@${n}"
                if docker exec control ssh -o StrictHostKeyChecking=no \
                    -o BatchMode=yes -o ConnectTimeout=3 "$tgt" true \
                    2>/dev/null; then
                    ok="$tgt"; break
                fi
            done
            if [ -n "$ok" ]; then
                echo "[+] $n listo via $ok (${t}s)"
            else
                rest="$rest $n"
            fi
        done
        pend="${rest# }"
        [ -n "$pend" ] && { sleep 2; t=$((t+2)); }
    done
    if [ -n "$pend" ]; then
        echo "[X] SSH NO listo en: ${pend} tras ${t}s (mira 'docker ps')"
        return 1
    fi
    echo "[+] Todos los nodos aceptan SSH (${t}s)"
}
