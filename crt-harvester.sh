#!/bin/bash
echo -e "
\033[0;32m
 ██████╗██████╗ ████████╗       ██╗  ██╗ █████╗ ██████╗ ██╗   ██╗███████╗███████╗████████╗███████╗██████╗ 
██╔════╝██╔══██╗╚══██╔══╝█████╗ ██║  ██║██╔══██╗██╔══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██║     ██████╔╝   ██║   ╚════╝ ███████║███████║██████╔╝██║   ██║█████╗  ███████╗   ██║   █████╗  ██████╔╝
██║     ██╔══██╗   ██║          ██╔══██║██╔══██║██╔══██╗╚██╗ ██╔╝██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗
╚██████╗██║  ██║   ██║          ██║  ██║██║  ██║██║  ██║ ╚████╔╝ ███████╗███████║   ██║   ███████╗██║  ██║
 ╚═════╝╚═╝  ╚═╝   ╚═╝          ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
\033[0m\033[1;33m
 ┌──────────────────────────────────────────────────┐
 │  [*] Certificate  Transparency  Recon  Tool      │
 │  [*] Source      : crt.sh  | TLS/SSL Harvester   │
 │  [*] Version     : 2.4     | Alive/Dead + HTML   │
 │  [*] Recon Mode  : Passive Subdomain Enumeration │
 │  [*] Author      : Swapnilkumar Rane             │
 └──────────────────────────────────────────────────┘

\033[0;31m [!] For authorized Security testing Purpose only.\033[0m
"

# ─── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m'

# ─── Globals ─────────────────────────────────────────────────
THREADS=20
MONITOR_MODE=0
PDF_OUTPUT=0
MONITOR_PID=""
TOOL_NAME="CRT-Harvester"
TOOL_VERSION="2.4"
TOOL_AUTHOR="Swapnilkumar Rane"

# ─── Monitor internals ───────────────────────────────────────
MON_INTERVAL=2
MON_CSV_FILE="output/perf_monitor.csv"
MON_HTML_FILE="output/perf_report.html"

# ─── Help ────────────────────────────────────────────────────
Help() {
    echo "Options:"
    echo ""
    echo "  -h             Help"
    echo "  -d <domain>    Search Domain Name    | Example: $0 -d example.com"
    echo "  -t <threads>   Thread count (default: 20)"
    echo "  -m             Monitor CPU/Memory in background while scanning"
    echo "                   Generates: output/perf_report.html + output/perf_monitor.csv"
    echo "                   Summary printed at end of scan"
    echo "  -P             Generate PDF output for all HTML reports"
    echo "                   Requires: chromium-browser, chromium, or google-chrome"
    echo ""
    echo "Features:"
    echo "  - Merges crt.sh + subfinder (-all -silent) results, deduplicates"
    echo "  - Resolves subdomains to IP addresses"
    echo "  - Dual-validates with ping + httpx-toolkit (multithreaded)"
    echo "    ALIVE       = both ping and httpx confirm active (2xx/3xx)"
    echo "    UNCONFIRMED = one check active, one not"
    echo "    DEAD        = ping failed, no 2xx/3xx HTTP response"
    echo "    NO IP       = no DNS resolution"
    echo "  - httpx-toolkit probes both http:// and https://"
    echo "  - Saves results: _alive.txt, _dead.txt, _unconfirmed.txt, _ips.txt"
    echo "  - Generates styled HTML report  (-P also generates PDF)"
    echo "  - Cleans up all intermediate temp files after output is ready"
    echo ""
    echo "Examples:"
    echo "  $0 -d example.com"
    echo "  $0 -d example.com -t 50 -m"
    echo "  $0 -d example.com -P"
    echo "  $0 -d example.com -t 200 -m -P"
    echo ""
}

# ─── CleanResults ────────────────────────────────────────────
CleanResults() {
    sed 's/\\n/\n/g' | \
    sed 's/\*\.//g' | \
    sed -r 's/([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4})//g' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | \
    sort -u
}

# ════════════════════════════════════════════════════════════
#  INTEGRATED MONITOR ENGINE
#  Runs entirely in a background subshell when -m is passed.
#  Silently collects CPU/RSS/Threads every MON_INTERVAL seconds.
#  On SIGINT from StopMonitor → generates HTML/CSV report.
#  Summary is printed to the user ONLY after scan completes.
# ════════════════════════════════════════════════════════════

_mon_sample() {
    local pid="$1"
    local csv_file="$2"
    local start_epoch="$3"

    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    local now elapsed cpu rss_kb rss_mb vsz_kb vsz_mb threads
    now=$(date "+%Y-%m-%d %H:%M:%S")
    elapsed=$(( $(date +%s) - start_epoch ))

    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
    [ -z "$cpu" ] && cpu="0.0"

    rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ')
    rss_mb=$(awk "BEGIN{printf \"%.1f\", ${rss_kb:-0}/1024}")

    vsz_kb=$(ps -p "$pid" -o vsz= 2>/dev/null | tr -d ' ')
    vsz_mb=$(awk "BEGIN{printf \"%.1f\", ${vsz_kb:-0}/1024}")

    threads=1
    [ -f "/proc/$pid/status" ] && \
        threads=$(grep -i "^Threads:" "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
    [ -z "$threads" ] && threads=1

    echo "$now,$elapsed,$cpu,$rss_mb,$vsz_mb,$threads" >> "$csv_file"
    return 0
}

_mon_generate_report() {
    local pid="$1"
    local csv_file="$2"
    local html_file="$3"

    local scan_date avg_cpu max_cpu peak_rss avg_rss total_samples
    local labels cpu_data rss_data threads_data
    scan_date=$(date "+%Y-%m-%d %H:%M:%S %Z")

    avg_cpu=$(tail -n +2 "$csv_file" | awk -F',' '{s+=$3;c++} END{if(c>0)printf "%.1f",s/c; else print "0.0"}')
    max_cpu=$(tail -n +2 "$csv_file" | awk -F',' 'BEGIN{m=0}{if($3+0>m+0)m=$3}END{print m}')
    peak_rss=$(tail -n +2 "$csv_file" | awk -F',' 'BEGIN{m=0}{if($4+0>m+0)m=$4}END{print m}')
    avg_rss=$(tail -n +2 "$csv_file" | awk -F',' '{s+=$4;c++} END{if(c>0)printf "%.1f",s/c; else print "0.0"}')
    total_samples=$(tail -n +2 "$csv_file" | wc -l | tr -d ' ')

    labels=$(tail -n +2 "$csv_file" | awk -F',' '{printf "\"%s\",",$1}' | sed 's/,$//')
    cpu_data=$(tail -n +2 "$csv_file" | awk -F',' '{printf "%s,",$3}' | sed 's/,$//')
    rss_data=$(tail -n +2 "$csv_file" | awk -F',' '{printf "%s,",$4}' | sed 's/,$//')
    threads_data=$(tail -n +2 "$csv_file" | awk -F',' '{printf "%s,",$6}' | sed 's/,$//')

    local table_rows=""
    while IFS=',' read -r ts elapsed cpu rss vsz thr; do
        local cpu_class="lo-cpu"
        local cpu_int=${cpu%.*}
        [ "${cpu_int:-0}" -ge 50 ] 2>/dev/null && cpu_class="med-cpu"
        [ "${cpu_int:-0}" -ge 80 ] 2>/dev/null && cpu_class="hi-cpu"
        table_rows+="    <tr><td>$ts</td><td>${elapsed}s</td><td class='$cpu_class'>${cpu}%</td><td>${rss}</td><td>${vsz}</td><td>$thr</td></tr>\n"
    done < <(tail -n +2 "$csv_file")

    cat > "$html_file" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CRT-Harvester Performance Report</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  :root{--bg:#0f172a;--surface:#1e293b;--border:#334155;--text:#f8fafc;--muted:#94a3b8;--brand:#38bdf8;--green:#10b981;--red:#ef4444;--orange:#f97316;--yellow:#f59e0b;}
  *{box-sizing:border-box;margin:0;padding:0;}
  body{font-family:'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);padding:24px;line-height:1.5;}
  .container{max-width:1200px;margin:0 auto;}
  .header{border-bottom:2px solid var(--border);padding-bottom:20px;margin-bottom:30px;}
  .header h1{color:var(--brand);font-size:26px;margin-bottom:6px;}
  .header p{color:var(--muted);font-size:14px;}
  .section-title{font-size:18px;color:#fff;border-bottom:1px solid var(--border);padding-bottom:8px;margin-bottom:16px;margin-top:28px;}
  .grid-4{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-bottom:36px;}
  .card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:20px;text-align:center;}
  .card h3{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:1px;margin-bottom:8px;}
  .card .val{font-size:36px;font-weight:700;}
  .chart-grid{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-bottom:36px;}
  .chart-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:20px;}
  .chart-card h3{font-size:14px;color:var(--muted);margin-bottom:16px;text-transform:uppercase;letter-spacing:.5px;}
  .chart-full{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:20px;margin-bottom:36px;}
  .chart-full h3{font-size:14px;color:var(--muted);margin-bottom:16px;text-transform:uppercase;letter-spacing:.5px;}
  table{width:100%;border-collapse:collapse;background:var(--surface);border-radius:8px;overflow:hidden;margin-bottom:36px;font-size:13px;}
  th,td{padding:10px 14px;text-align:left;border-bottom:1px solid var(--border);}
  th{background:rgba(0,0,0,.2);color:var(--brand);font-weight:600;text-transform:uppercase;font-size:12px;letter-spacing:.5px;}
  tr:last-child td{border-bottom:none;}
  tr:hover{background:rgba(255,255,255,.02);}
  .lo-cpu{color:var(--green);}
  .med-cpu{color:var(--orange);}
  .hi-cpu{color:var(--red);}
  .footer{margin-top:40px;padding-top:16px;border-top:1px solid var(--border);text-align:center;color:var(--muted);font-size:12px;}
  .footer span{color:var(--brand);}
  @media(max-width:768px){.chart-grid{grid-template-columns:1fr;}}
  @media print{
    body{background:#fff;color:#000;}
    .card,.chart-card,.chart-full,table,th,td{background:#fff!important;color:#000!important;border:1px solid #ccc!important;}
    .footer{color:#555!important;}
  }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>⚡ CRT-Harvester — Performance Report</h1>
    <p><strong>PID Monitored:</strong> $pid &nbsp;|&nbsp; <strong>Report Generated:</strong> $scan_date &nbsp;|&nbsp; <strong>Total Samples:</strong> $total_samples &nbsp;|&nbsp; <strong>Interval:</strong> ${MON_INTERVAL}s</p>
  </div>
  <h2 class="section-title">📊 Summary</h2>
  <div class="grid-4">
    <div class="card"><h3>Avg CPU</h3><p class="val" style="color:var(--brand)">${avg_cpu}%</p></div>
    <div class="card"><h3>Peak CPU</h3><p class="val" style="color:var(--red)">${max_cpu}%</p></div>
    <div class="card"><h3>Peak RSS</h3><p class="val" style="color:var(--orange)">${peak_rss} MB</p></div>
    <div class="card"><h3>Avg RSS</h3><p class="val" style="color:var(--yellow)">${avg_rss} MB</p></div>
  </div>
  <div class="chart-full">
    <h3>🔥 CPU % Over Time</h3>
    <canvas id="cpuChart" height="100"></canvas>
  </div>
  <div class="chart-grid">
    <div class="chart-card">
      <h3>🧠 Memory RSS (MB) Over Time</h3>
      <canvas id="rssChart" height="200"></canvas>
    </div>
    <div class="chart-card">
      <h3>🧵 Thread Count Over Time</h3>
      <canvas id="thrChart" height="200"></canvas>
    </div>
  </div>
  <h2 class="section-title">📋 Sample Log</h2>
  <table>
    <tr><th>Timestamp</th><th>Elapsed (s)</th><th>CPU %</th><th>RSS (MB)</th><th>VSZ (MB)</th><th>Threads</th></tr>
$(echo -e "$table_rows")
  </table>
  <div class="footer">
    <p>Generated by <span>$TOOL_NAME v$TOOL_VERSION</span> &nbsp;|&nbsp; Author: <span>$TOOL_AUTHOR</span> &nbsp;|&nbsp; $scan_date</p>
  </div>
</div>
<script>
const labels = [$labels];
const cpuData = [$cpu_data];
const rssData = [$rss_data];
const thrData = [$threads_data];
const chartDefaults = {
  responsive: true,
  plugins: { legend: { labels: { color: '#94a3b8', font: { size: 12 } } } },
  scales: {
    x: { ticks: { color: '#64748b', maxTicksLimit: 12, maxRotation: 45 }, grid: { color: 'rgba(51,65,85,0.5)' } },
    y: { ticks: { color: '#64748b' }, grid: { color: 'rgba(51,65,85,0.5)' }, beginAtZero: true }
  }
};
new Chart(document.getElementById('cpuChart'), {
  type: 'line',
  data: { labels, datasets: [{ label: 'CPU %', data: cpuData, borderColor: '#ef4444', backgroundColor: 'rgba(239,68,68,0.1)', fill: true, tension: 0.3, pointRadius: 2 }] },
  options: { ...chartDefaults }
});
new Chart(document.getElementById('rssChart'), {
  type: 'line',
  data: { labels, datasets: [{ label: 'RSS MB', data: rssData, borderColor: '#f97316', backgroundColor: 'rgba(249,115,22,0.1)', fill: true, tension: 0.3, pointRadius: 2 }] },
  options: { ...chartDefaults }
});
new Chart(document.getElementById('thrChart'), {
  type: 'bar',
  data: { labels, datasets: [{ label: 'Threads', data: thrData, backgroundColor: 'rgba(56,189,248,0.5)', borderColor: '#38bdf8', borderWidth: 1 }] },
  options: { ...chartDefaults }
});
</script>
</body>
</html>
HTMLEOF
}

# ─── Monitor background loop ─────────────────────────────────
# Entire loop runs as a subshell. No output to terminal at all.
# Writes only to CSV file. Report generated on exit.
_mon_run_loop() {
    local pid="$1"
    local csv_file="$2"
    local html_file="$3"
    local start_epoch
    start_epoch=$(date +%s)

    mkdir -p output
    echo "timestamp,elapsed_sec,cpu_percent,mem_rss_mb,mem_vsz_mb,threads" > "$csv_file"

    trap '_mon_generate_report '"$pid"' '"$csv_file"' '"$html_file"'; exit 0' INT TERM

    while true; do
        _mon_sample "$pid" "$csv_file" "$start_epoch" || {
            _mon_generate_report "$pid" "$csv_file" "$html_file"
            exit 0
        }
        sleep "$MON_INTERVAL"
    done
}

# ─── StartMonitor ────────────────────────────────────────────
StartMonitor() {
    export MON_INTERVAL MON_CSV_FILE MON_HTML_FILE TOOL_NAME TOOL_VERSION TOOL_AUTHOR
    export RED GREEN BLUE YELLOW CYAN ORANGE NC
    # Launch fully silently — no stdout/stderr from background loop
    ( _mon_run_loop $$ "$MON_CSV_FILE" "$MON_HTML_FILE" ) >/dev/null 2>&1 &
    MONITOR_PID=$!
}

# ─── StopMonitor ─────────────────────────────────────────────
# Stops background monitor and prints summary to user on stdout.
StopMonitor() {
    if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        # Signal monitor to generate report and exit
        kill -INT "$MONITOR_PID" 2>/dev/null
        wait "$MONITOR_PID" 2>/dev/null

        # Print summary to user only after scan is fully done
        if [ -f "$MON_CSV_FILE" ] && [ "$(wc -l < "$MON_CSV_FILE")" -gt 1 ]; then
            local avg_cpu max_cpu peak_rss avg_rss total_samples elapsed_total
            avg_cpu=$(tail -n +2 "$MON_CSV_FILE" | awk -F',' '{s+=$3;c++} END{if(c>0)printf "%.1f",s/c; else print "0.0"}')
            max_cpu=$(tail -n +2 "$MON_CSV_FILE" | awk -F',' 'BEGIN{m=0}{if($3+0>m+0)m=$3}END{print m}')
            peak_rss=$(tail -n +2 "$MON_CSV_FILE" | awk -F',' 'BEGIN{m=0}{if($4+0>m+0)m=$4}END{print m}')
            avg_rss=$(tail -n +2 "$MON_CSV_FILE" | awk -F',' '{s+=$4;c++} END{if(c>0)printf "%.1f",s/c; else print "0.0"}')
            total_samples=$(tail -n +2 "$MON_CSV_FILE" | wc -l | tr -d ' ')
            elapsed_total=$(tail -n +2 "$MON_CSV_FILE" | tail -1 | awk -F',' '{print $2}')

            echo ""
            echo -e "${CYAN}#####################################################${NC}"
            echo -e "${CYAN}#        ⚡ Performance Monitor Summary             #${NC}"
            echo -e "${CYAN}#####################################################${NC}"
            echo -e "${CYAN}Total Duration : ${YELLOW}${elapsed_total}s ${NC}"
            echo -e "${CYAN}Total Samples  : ${YELLOW}${total_samples} ${NC}"
            echo -e "${CYAN}Avg CPU Usage  : ${GREEN}${avg_cpu}% ${NC}"
            echo -e "${CYAN}Peak CPU Usage : ${RED}${max_cpu}% ${NC}"
            echo -e "${CYAN}Avg RSS Memory : ${YELLOW}${avg_rss} MB ${NC}"
            echo -e "${CYAN}Peak RSS Memory: ${ORANGE}${peak_rss} MB ${NC}"
            echo -e "${CYAN}#####################################################${NC}"
            echo ""
        fi

        # PDF for perf report if -P is set
        if [ "$PDF_OUTPUT" -eq 1 ] && [ -f "$MON_HTML_FILE" ]; then
            GeneratePDF "$MON_HTML_FILE"
        fi
    fi
}

# ─── GeneratePDF ─────────────────────────────────────────────
GeneratePDF() {
    local html_file="$1"
    local pdf_file="${html_file%.html}.pdf"

    local browser=""
    for b in chromium-browser chromium google-chrome google-chrome-stable; do
        command -v "$b" &>/dev/null && browser="$b" && break
    done

    if [ -z "$browser" ]; then
        echo -e "${YELLOW}[!] PDF skipped: no headless browser found (install chromium-browser).${NC}"
        return 1
    fi

    echo -e "${BLUE}[*]${NC} Generating PDF: ${CYAN}$pdf_file${NC}"
    "$browser" \
        --headless \
        --disable-gpu \
        --no-sandbox \
        --disable-dev-shm-usage \
        --print-to-pdf="$pdf_file" \
        --print-to-pdf-no-header \
        "file://$(realpath "$html_file")" \
        2>/dev/null

    if [ -f "$pdf_file" ]; then
        echo -e "${GREEN}[+]${NC} PDF saved → ${CYAN}$pdf_file${NC}"
    else
        echo -e "${RED}[!] PDF generation failed for: $html_file${NC}"
    fi
}

# ─── CleanupTempFiles ────────────────────────────────────────
CleanupTempFiles() {
    local base_name="$1"
    echo -e "${BLUE}[*]${NC} Cleaning up intermediate files..."
    rm -f "output/${base_name}_ips.lock"
    rm -f "output/${base_name}_alive.lock"
    rm -f "output/${base_name}_dead.lock"
    rm -f "output/${base_name}_unconfirmed.lock"
    rm -f "output/${base_name}_crtsh.txt"
    rm -f "output/${base_name}.txt"
    echo -e "${GREEN}[+]${NC} Cleanup done."
}

# ─── CheckHost (per-thread subshell) ─────────────────────────
CheckHost() {
    local domain="$1"
    local base_name="$2"
    local alive_file="output/${base_name}_alive.txt"
    local dead_file="output/${base_name}_dead.txt"
    local unconfirmed_file="output/${base_name}_unconfirmed.txt"
    local ips_file="output/${base_name}_ips.txt"

    local ip
    ip=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

    if [ -n "$ip" ]; then
        (flock -x 200; echo "$domain $ip" >> "$ips_file") 200>"output/${base_name}_ips.lock"

        local ping_alive=0
        ping -c 1 -W 2 "$ip" &>/dev/null && ping_alive=1

        local httpx_alive=0
        local httpx_result
        httpx_result=$(echo "$domain" | httpx-toolkit \
            -silent -status-code \
            -mc 200,201,204,301,302,303,307,308 \
            -timeout 5 2>/dev/null)
        [[ -n "$httpx_result" ]] && httpx_alive=1

        if [ "$ping_alive" -eq 1 ] && [ "$httpx_alive" -eq 1 ]; then
            (flock -x 201; echo "$domain $ip - ALIVE" >> "$alive_file") 201>"output/${base_name}_alive.lock"
        elif [ "$ping_alive" -eq 1 ] || [ "$httpx_alive" -eq 1 ]; then
            local ping_status="ping:$([ $ping_alive -eq 1 ] && echo YES || echo NO)"
            local httpx_status="httpx:$([ $httpx_alive -eq 1 ] && echo YES || echo NO)"
            (flock -x 203; echo "$domain $ip - UNCONFIRMED [$ping_status $httpx_status]" >> "$unconfirmed_file") 203>"output/${base_name}_unconfirmed.lock"
        else
            (flock -x 202; echo "$domain $ip - DEAD" >> "$dead_file") 202>"output/${base_name}_dead.lock"
        fi
    else
        (flock -x 202; echo "$domain - NO IP" >> "$dead_file") 202>"output/${base_name}_dead.lock"
    fi
}

export -f CheckHost
export RED GREEN BLUE YELLOW CYAN ORANGE NC

# ─── GenerateHTML ────────────────────────────────────────────
GenerateHTML() {
    local base_name="$1"
    local html_file="output/${base_name}_report.html"

    local count_alive=0 count_dead=0 count_noip=0 count_unconfirmed=0

    [[ -f "output/${base_name}_alive.txt" ]] && \
        count_alive=$(wc -l < "output/${base_name}_alive.txt" | tr -d ' ')
    [[ -f "output/${base_name}_dead.txt" ]] && \
        count_dead=$(grep -c " - DEAD" "output/${base_name}_dead.txt" || true)
    [[ -f "output/${base_name}_dead.txt" ]] && \
        count_noip=$(grep -c " - NO IP" "output/${base_name}_dead.txt" || true)
    [[ -f "output/${base_name}_unconfirmed.txt" ]] && \
        count_unconfirmed=$(wc -l < "output/${base_name}_unconfirmed.txt" | tr -d ' ')

    [[ -z "$count_alive" ]]       && count_alive=0
    [[ -z "$count_dead" ]]        && count_dead=0
    [[ -z "$count_noip" ]]        && count_noip=0
    [[ -z "$count_unconfirmed" ]] && count_unconfirmed=0

    local count_total=$(( count_alive + count_dead + count_noip + count_unconfirmed ))
    local scan_date
    scan_date=$(date "+%Y-%m-%d %H:%M:%S %Z")

    cat << EOF > "$html_file"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Recon Report: $base_name</title>
    <style>
        :root {
            --bg:#0f172a; --surface:#1e293b; --text:#f8fafc;
            --text-muted:#94a3b8; --border:#334155;
            --alive:#10b981; --dead:#ef4444; --noip:#f59e0b;
            --unconfirmed:#f97316; --brand:#38bdf8;
        }
        body{font-family:'Segoe UI',system-ui,sans-serif;background-color:var(--bg);color:var(--text);margin:0;padding:20px;line-height:1.5;}
        .container{max-width:1200px;margin:0 auto;}
        .header{border-bottom:2px solid var(--border);padding-bottom:20px;margin-bottom:30px;}
        .header h1{margin:0;color:var(--brand);font-size:28px;}
        .header p{margin:8px 0 0;color:var(--text-muted);font-size:15px;}
        .section-title{margin-bottom:15px;border-bottom:1px solid var(--border);padding-bottom:10px;font-size:20px;color:#fff;margin-top:30px;}
        .summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin-bottom:40px;}
        .card{background:var(--surface);padding:20px;border-radius:8px;border:1px solid var(--border);text-align:center;box-shadow:0 4px 6px rgba(0,0,0,0.1);}
        .card h3{margin:0 0 10px 0;font-size:14px;color:var(--text-muted);text-transform:uppercase;letter-spacing:1px;}
        .card .value{font-size:38px;font-weight:bold;margin:0;}
        .card.total .value{color:var(--brand);}
        .card.alive .value{color:var(--alive);}
        .card.dead .value{color:var(--dead);}
        .card.noip .value{color:var(--noip);}
        .card.unconfirmed .value{color:var(--unconfirmed);}
        table{width:100%;border-collapse:collapse;background:var(--surface);border-radius:8px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,0.1);margin-bottom:40px;}
        th,td{padding:14px 15px;text-align:left;border-bottom:1px solid var(--border);}
        th{background-color:rgba(0,0,0,0.2);color:var(--brand);font-weight:600;text-transform:uppercase;font-size:13px;letter-spacing:0.5px;}
        tr:last-child td{border-bottom:none;}
        tr:hover{background-color:rgba(255,255,255,0.02);}
        .badge{padding:5px 10px;border-radius:4px;font-size:12px;font-weight:bold;letter-spacing:0.5px;}
        .badge.alive{background-color:rgba(16,185,129,0.1);color:var(--alive);border:1px solid rgba(16,185,129,0.2);}
        .badge.dead{background-color:rgba(239,68,68,0.1);color:var(--dead);border:1px solid rgba(239,68,68,0.2);}
        .badge.noip{background-color:rgba(245,158,11,0.1);color:var(--noip);border:1px solid rgba(245,158,11,0.2);}
        .badge.unconfirmed{background-color:rgba(249,115,22,0.15);color:var(--unconfirmed);border:1px solid rgba(249,115,22,0.3);}
        .note{font-size:11px;color:var(--text-muted);margin-top:4px;}
        .footer{margin-top:40px;padding-top:16px;border-top:1px solid var(--border);text-align:center;color:var(--text-muted);font-size:12px;}
        .footer span{color:var(--brand);}
        @media print{
            body{background:white;color:black;}
            .container{max-width:100%;}
            .card,table,th,td{border:1px solid #ddd;background:white!important;box-shadow:none;color:black;}
            .header h1,.section-title,th{color:#333;}
            .badge{border:1px solid #333;color:#333!important;background:transparent!important;}
            .footer{color:#555!important;}
        }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>🔍 Target Reconnaissance Report</h1>
        <p><strong>Target:</strong> $base_name &nbsp;|&nbsp; <strong>Scan Date:</strong> $scan_date &nbsp;|&nbsp; <strong>Sources:</strong> crt.sh + subfinder</p>
        <p>Generated by <span>$TOOL_NAME v$TOOL_VERSION</span> &nbsp;|&nbsp; Author: <span>$TOOL_AUTHOR</span> &nbsp;|&nbsp; $scan_date</p>
    </div>

    <h2 class="section-title">📊 Executive Summary</h2>
    <div class="summary-grid">
        <div class="card total"><h3>Total Subdomains</h3><p class="value">$count_total</p></div>
        <div class="card alive"><h3>Alive</h3><p class="value">$count_alive</p></div>
        <div class="card unconfirmed"><h3>Unconfirmed</h3><p class="value">$count_unconfirmed</p></div>
        <div class="card dead"><h3>Dead</h3><p class="value">$count_dead</p></div>
        <div class="card noip"><h3>No IP</h3><p class="value">$count_noip</p></div>
    </div>

    <h2 class="section-title">✅ Alive Subdomains</h2>
    <table>
        <thead><tr><th>Domain</th><th>IP Address</th><th>Status</th><th>Validation Detail</th></tr></thead>
        <tbody>
EOF

    if [[ -f "output/${base_name}_alive.txt" ]] && [[ -s "output/${base_name}_alive.txt" ]]; then
        while IFS= read -r line; do
            local domain ip
            domain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk '{print $2}')
            echo "        <tr><td>$domain</td><td>$ip</td><td><span class='badge alive'>ALIVE</span></td><td>ping ✅ httpx ✅</td></tr>" >> "$html_file"
        done < "output/${base_name}_alive.txt"
    else
        echo "        <tr><td colspan='4' style='text-align:center;color:var(--text-muted)'>No alive hosts found.</td></tr>" >> "$html_file"
    fi

    cat << EOF >> "$html_file"
        </tbody>
    </table>

    <h2 class="section-title">⚠️ Unconfirmed Subdomains</h2>
    <table>
        <thead><tr><th>Domain</th><th>IP Address</th><th>Status</th><th>Validation Detail</th></tr></thead>
        <tbody>
EOF

    if [[ -f "output/${base_name}_unconfirmed.txt" ]] && [[ -s "output/${base_name}_unconfirmed.txt" ]]; then
        while IFS= read -r line; do
            local domain ip ping_icon httpx_icon
            domain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk '{print $2}')
            ping_icon="❌"; httpx_icon="❌"
            echo "$line" | grep -q "ping:YES"  && ping_icon="✅"
            echo "$line" | grep -q "httpx:YES" && httpx_icon="✅"
            echo "        <tr><td>$domain</td><td>$ip</td><td><span class='badge unconfirmed'>UNCONFIRMED</span></td><td>ping $ping_icon httpx $httpx_icon</td></tr>" >> "$html_file"
        done < "output/${base_name}_unconfirmed.txt"
    else
        echo "        <tr><td colspan='4' style='text-align:center;color:var(--text-muted)'>No unconfirmed hosts.</td></tr>" >> "$html_file"
    fi

    cat << EOF >> "$html_file"
        </tbody>
    </table>
    <p class="note">⚠️ UNCONFIRMED = one validation method returned active, the other did not. Manual verification recommended.</p>

    <h2 class="section-title">❌ Dead / No IP Subdomains</h2>
    <table>
        <thead><tr><th>Domain</th><th>IP Address</th><th>Status</th><th>Validation Detail</th></tr></thead>
        <tbody>
EOF

    if [[ -f "output/${base_name}_dead.txt" ]] && [[ -s "output/${base_name}_dead.txt" ]]; then
        while IFS= read -r line; do
            local domain ip
            domain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk '{print $2}')
            if echo "$line" | grep -q " - NO IP"; then
                echo "        <tr><td>$domain</td><td>-</td><td><span class='badge noip'>NO IP</span></td><td>DNS ❌</td></tr>" >> "$html_file"
            else
                echo "        <tr><td>$domain</td><td>$ip</td><td><span class='badge dead'>DEAD</span></td><td>ping ❌ httpx ❌</td></tr>" >> "$html_file"
            fi
        done < "output/${base_name}_dead.txt"
    else
        echo "        <tr><td colspan='4' style='text-align:center;color:var(--text-muted)'>No dead hosts.</td></tr>" >> "$html_file"
    fi

    cat << EOF >> "$html_file"
        </tbody>
    </table>

    <div class="footer">
        <p>Generated by <span>$TOOL_NAME v$TOOL_VERSION</span> &nbsp;|&nbsp; Author: <span>$TOOL_AUTHOR</span> &nbsp;|&nbsp; $scan_date</p>
    </div>
</div>
</body>
</html>
EOF

    echo -e "${GREEN}[+]${NC} HTML report saved → ${CYAN}$html_file${NC}"

    if [ "$PDF_OUTPUT" -eq 1 ]; then
        GeneratePDF "$html_file"
    fi
}

# ─── ResolveAndCheck ─────────────────────────────────────────
ResolveAndCheck() {
    local domainsfile="$1"
    local basename="$2"
    local pids=() # Array to track only the scanning subshells

    # Initialize output files
    >"output/${basename}_ips.txt"
    >"output/${basename}_alive.txt"
    >"output/${basename}_dead.txt"
    >"output/${basename}_unconfirmed.txt"

    local total
    total=$(wc -l < "$domainsfile")
    echo -e "${BLUE}[*]${NC} Checking $total hosts with $THREADS threads..."

    # Create a named pipe as a token pool for threading
    local tmpfifo
    tmpfifo=$(mktemp -u)
    mkfifo "$tmpfifo"
    exec 9<>"$tmpfifo"
    rm -f "$tmpfifo"

    # Fill the pipe with exactly THREADS tokens
    for ((i=0; i<THREADS; i++)); do
        echo >&9
    done

    local counterfile
    counterfile=$(mktemp)
    echo 0 > "$counterfile"

    while IFS= read -r domain; do
        # Acquire a token (blocks if pool is empty)
        read -r -u 9

        {
            # Ensure the token is released even if the inner logic fails
            trap 'echo >&9' EXIT
            
            CheckHost "$domain" "$basename" >/dev/null 2>&1

            # Progress counter (atomic via flock)
            flock -x 210
            local n
            n=$(cat "$counterfile")
            n=$((n + 1))
            echo "$n" > "$counterfile"
            local pct=$(( n * 100 / total ))
            printf "\r${CYAN}[*] Progress: %d / %d (%d%%)${NC}" "$n" "$total" "$pct"
            flock -u 210
        } 210>"${counterfile}.lock" &
        
        # Capture the PID of the subshell we just backgrounded
        pids+=($!)

    done < "$domainsfile"

    # CRITICAL FIX: Wait specifically for scanner PIDs. 
    # A bare 'wait' would wait for the background Monitor PID indefinitely.
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # Close the token file descriptor
    exec 9>&-
    rm -f "$counterfile" "${counterfile}.lock"

    printf "\n"
    echo -e "${GREEN}[+]${NC} Alive:        $(wc -l < "output/${basename}_alive.txt")"
    echo -e "${GREEN}[+]${NC} Unconfirmed:  $(wc -l < "output/${basename}_unconfirmed.txt")"
    echo -e "${GREEN}[+]${NC} Dead:         $(grep -c -- '- DEAD' "output/${basename}_dead.txt" || true)"
    echo -e "${GREEN}[+]${NC} No IP:        $(grep -c -- '- NO IP' "output/${basename}_dead.txt" || true)"
    echo -e "${GREEN}[+]${NC} IPs resolved: $(wc -l < "output/${basename}_ips.txt")"
    echo -e "${GREEN}[+]${NC} Text results: output/${basename}{_alive,_unconfirmed,_dead,_ips}.txt"

    GenerateHTML "$basename"
    StopMonitor
    CleanupTempFiles "$basename"
}

mkdir -p output

# ─── Domain ──────────────────────────────────────────────────
Domain() {
    if [ -z "$req" ]; then
        echo -e "${RED}[!] Error: Domain name is required.${NC}"
        exit 1
    fi

    local crtsh_file="output/domain.${req}_crtsh.txt"
    local merged_file="output/domain.${req}.txt"
    local crtsh_results=""

    # ── crt.sh query (retry up to 3x, graceful fallback on failure) ──
    echo -e "${BLUE}[*]${NC} Querying crt.sh for domain: $req"
    local response=""
    local retry=0
    while [ $retry -lt 3 ]; do
        response=$(curl -s --max-time 20 --connect-timeout 10 \
            "https://crt.sh/?q=%25.$req&output=json" 2>/dev/null)
        [ -n "$response" ] && [ "$response" != "[]" ] && break
        retry=$(( retry + 1 ))
        echo -e "${YELLOW}[!] crt.sh attempt $retry/3 failed or empty — retrying...${NC}"
        sleep 2
    done

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        echo -e "${YELLOW}[!] crt.sh unreachable or returned no results — continuing with subfinder only.${NC}"
    else
        crtsh_results=$(echo "$response" | jq -r '.[].common_name, .[].name_value' 2>/dev/null | CleanResults)
        if [ -z "$crtsh_results" ]; then
            echo -e "${YELLOW}[!] crt.sh response had no valid subdomains — continuing with subfinder only.${NC}"
        else
            echo "$crtsh_results" > "$crtsh_file"
            echo -e "${GREEN}[+]${NC} crt.sh found: ${CYAN}$(wc -l < "$crtsh_file" | tr -d ' ')${NC} subdomains"
        fi
    fi

    # ── subfinder (inline, always runs regardless of crt.sh result) ──
    echo -e "${BLUE}[*]${NC} Running subfinder -d $req -all -silent ..."
    local subfinder_results=""
    if command -v subfinder &>/dev/null; then
        subfinder_results=$(subfinder -d "$req" -all -silent 2>/dev/null | \
            grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | sort -u)
        local sf_count
        sf_count=$(echo "$subfinder_results" | grep -c . 2>/dev/null || echo 0)
        echo -e "${GREEN}[+]${NC} subfinder found: ${CYAN}${sf_count}${NC} subdomains"
    else
        echo -e "${YELLOW}[!] subfinder not found in PATH — skipping subfinder step.${NC}"
    fi

    # ── Merge + deduplicate both sources ──
    {
        [ -f "$crtsh_file" ] && cat "$crtsh_file"
        echo "$subfinder_results"
    } | grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | sort -u > "$merged_file"

    local merged_count
    merged_count=$(wc -l < "$merged_file" | tr -d ' ')

    if [ "$merged_count" -eq 0 ]; then
        echo -e "${RED}[!] No subdomains found from crt.sh or subfinder. Exiting.${NC}"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}[+]${NC} Total unique subdomains: ${RED}${merged_count}${NC}"

    # Start monitor silently in background before CPU-intensive phase
    [ "$MONITOR_MODE" -eq 1 ] && StartMonitor

    ResolveAndCheck "$merged_file" "domain.${req}"
}

# ─── Organization ────────────────────────────────────────────
Organization() {
    if [ -z "$req" ]; then
        echo -e "${RED}[!] Error: Organization name is required.${NC}"
        exit 1
    fi

    echo -e "${BLUE}[*]${NC} Querying crt.sh for organization: $req"
    local response
    response=$(curl -s "https://crt.sh/?q=$req&output=json")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        echo -e "${RED}[!] No results found for organization: $req${NC}"
        exit 1
    fi

    local results
    results=$(echo "$response" | jq -r '.[].common_name' 2>/dev/null | CleanResults)

    if [ -z "$results" ]; then
        echo -e "${RED}[!] No valid results extracted.${NC}"
        exit 1
    fi

    local output_file="output/org.${req}.txt"
    echo "$results" > "$output_file"
    echo -e "${GREEN}[+]${NC} Total entries : ${RED}$(echo "$results" | wc -l)${NC}"

    [ "$MONITOR_MODE" -eq 1 ] && StartMonitor

    ResolveAndCheck "$output_file" "org.${req}"
}

# ─── Main Script Logic ───────────────────────────────────────
if [ -z "$1" ]; then
    Help
    exit 0
fi

req=""
mode=""

while getopts ":hd:t:mP" option; do
    case $option in
        h) Help; exit 0 ;;
        d) req="$OPTARG"; mode="domain" ;;
        t) THREADS="$OPTARG" ;;
        m) MONITOR_MODE=1 ;;
        P) PDF_OUTPUT=1 ;;
        :) echo -e "${RED}[!] Option -$OPTARG requires an argument.${NC}"; exit 1 ;;
        \?) echo -e "${RED}[!] Unknown option: -$OPTARG${NC}"; Help; exit 1 ;;
    esac
done

# Early warning if -P but no browser available
if [ "$PDF_OUTPUT" -eq 1 ]; then
    browser_found=0
    for b in chromium-browser chromium google-chrome google-chrome-stable; do
        command -v "$b" &>/dev/null && browser_found=1 && break
    done
    if [ "$browser_found" -eq 0 ]; then
        echo -e "${YELLOW}[!] Warning: -P requested but no headless browser found.${NC}"
        echo -e "${YELLOW}    PDF output will be skipped. Install chromium-browser to enable.${NC}"
        echo ""
    fi
fi

case "$mode" in
    domain) Domain ;;
    *) Help; exit 0 ;;
esac
