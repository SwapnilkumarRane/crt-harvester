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
 │  [*] Version     : 1.0     | Alive/Dead + HTML   │
 │  [*] Recon Mode  : Passive Subdomain Enumeration │
 │  [*] Author      : Swapnilkumar Rane             │
 └──────────────────────────────────────────────────┘
 
\033[0;31m [!] For authorized Security testing Purpose only.\033[0m
"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Thread count for parallel host checking (adjustable)
THREADS=20

# Function: Help
Help() {
    echo "Options:"
    echo ""
    echo "  -h             Help"
    echo "  -d <domain>    Search Domain Name    | Example: $0 -d example.com"
    echo "  -o <org>       Search Organization   | Example: $0 -o example"
    echo "  -t <threads>   Thread count (default: 20)"
    echo ""
    echo "Features:"
    echo "  - Resolves subdomains to IP addresses"
    echo "  - Checks if hosts are alive or dead (multithreaded)"
    echo "  - Saves results to text files: <prefix>_ips.txt, _alive.txt, _dead.txt"
    echo "  - Generates a styled HTML report containing Domains, IPs, and Status for Easy sharing"
    echo ""
}

# Function: CleanResults
CleanResults() {
    sed 's/\\n/\n/g' | \
    sed 's/\*\.//g' | \
    sed -r 's/([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4})//g' | \
    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | \
    sort -u
}

# Function: CheckHost (used per-thread)
# Called as a subshell for each domain
CheckHost() {
    local domain="$1"
    local base_name="$2"
    local alive_file="output/${base_name}_alive.txt"
    local dead_file="output/${base_name}_dead.txt"
    local ips_file="output/${base_name}_ips.txt"

    local ip
    ip=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

    if [ -n "$ip" ]; then
        # Save IP resolution (file-level lock via flock)
        (
            flock -x 200
            echo "$domain $ip" >> "$ips_file"
        ) 200>"output/${base_name}_ips.lock"

        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            (
                flock -x 201
                echo "$domain $ip - ALIVE" >> "$alive_file"
            ) 201>"output/${base_name}_alive.lock"
            echo -e "${GREEN}ALIVE:${NC} $domain ($ip)"
        else
            (
                flock -x 202
                echo "$domain $ip - DEAD" >> "$dead_file"
            ) 202>"output/${base_name}_dead.lock"
            echo -e "${RED}DEAD:${NC} $domain ($ip)"
        fi
    else
        (
            flock -x 202
            echo "$domain - NO IP" >> "$dead_file"
        ) 202>"output/${base_name}_dead.lock"
        echo -e "${YELLOW}NO IP:${NC} $domain"
    fi
}

export -f CheckHost
export RED GREEN BLUE YELLOW NC

# Function: GenerateHTML
GenerateHTML() {
    local base_name="$1"
    local html_file="output/${base_name}_report.html"

    # Calculate metrics for the Executive Summary
    local count_alive=0
    local count_dead=0
    local count_noip=0

    if [[ -f "output/${base_name}_alive.txt" ]]; then
        # tr -d removes any hidden spaces added by macOS/BSD versions of wc
        count_alive=$(wc -l < "output/${base_name}_alive.txt" | tr -d ' ' || true)
        [[ -z "$count_alive" ]] && count_alive=0
    fi
    
    if [[ -f "output/${base_name}_dead.txt" ]]; then
        # '|| true' prevents the double-zero issue when grep finds 0 matches
        count_dead=$(grep -c " - DEAD" "output/${base_name}_dead.txt" || true)
        count_noip=$(grep -c " - NO IP" "output/${base_name}_dead.txt" || true)
        
        [[ -z "$count_dead" ]] && count_dead=0
        [[ -z "$count_noip" ]] && count_noip=0
    fi
    
    local count_total=$((count_alive + count_dead + count_noip))
    local scan_date=$(date "+%Y-%m-%d %H:%M:%S %Z")

    # Start HTML with Heredoc (cleaner than multiple echos)
    cat << EOF > "$html_file"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Recon Report: $base_name</title>
    <style>
        :root {
            --bg: #0f172a;
            --surface: #1e293b;
            --text: #f8fafc;
            --text-muted: #94a3b8;
            --border: #334155;
            --alive: #10b981;
            --dead: #ef4444;
            --noip: #f59e0b;
            --brand: #38bdf8;
        }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 20px; line-height: 1.5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { border-bottom: 2px solid var(--border); padding-bottom: 20px; margin-bottom: 30px; }
        .header h1 { margin: 0; color: var(--brand); font-size: 28px; }
        .header p { margin: 8px 0 0; color: var(--text-muted); font-size: 15px; }
        
        /* Executive Summary Cards (For Management) */
        .section-title { margin-bottom: 15px; border-bottom: 1px solid var(--border); padding-bottom: 10px; font-size: 20px; color: #fff; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; margin-bottom: 40px; }
        .card { background: var(--surface); padding: 20px; border-radius: 8px; border: 1px solid var(--border); text-align: center; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .card h3 { margin: 0 0 10px 0; font-size: 14px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; }
        .card .value { font-size: 38px; font-weight: bold; margin: 0; }
        .card.total .value { color: var(--brand); }
        .card.alive .value { color: var(--alive); }
        .card.dead .value { color: var(--dead); }
        .card.noip .value { color: var(--noip); }

        /* Technical Details Table (For Engineers) */
        table { width: 100%; border-collapse: collapse; background: var(--surface); border-radius: 8px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin-bottom: 40px; }
        th, td { padding: 14px 15px; text-align: left; border-bottom: 1px solid var(--border); }
        th { background-color: rgba(0,0,0,0.2); color: var(--brand); font-weight: 600; text-transform: uppercase; font-size: 13px; letter-spacing: 0.5px; }
        tr:last-child td { border-bottom: none; }
        tr:hover { background-color: rgba(255,255,255,0.02); }
        
        /* Status Badges */
        .badge { padding: 5px 10px; border-radius: 4px; font-size: 12px; font-weight: bold; letter-spacing: 0.5px; }
        .badge.alive { background-color: rgba(16, 185, 129, 0.1); color: var(--alive); border: 1px solid rgba(16, 185, 129, 0.2); }
        .badge.dead { background-color: rgba(239, 68, 68, 0.1); color: var(--dead); border: 1px solid rgba(239, 68, 68, 0.2); }
        .badge.noip { background-color: rgba(245, 158, 11, 0.1); color: var(--noip); border: 1px solid rgba(245, 158, 11, 0.2); }
        
        /* Print-friendly styles for PDF export */
        @media print {
            body { background: white; color: black; }
            .container { max-width: 100%; }
            .card, table, th, td { border: 1px solid #ddd; background: white !important; box-shadow: none; color: black; }
            .header h1, .section-title, th { color: #333; }
            .badge { border: 1px solid #333; color: #333 !important; background: transparent !important; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Target Reconnaissance Report</h1>
            <p><strong>Target Name:</strong> $base_name &nbsp;|&nbsp; <strong>Scan Date:</strong> $scan_date</p>
        </div>

        <h2 class="section-title">📊 Executive Summary</h2>
        <div class="summary-grid">
            <div class="card total">
                <h3>Total Subdomains</h3>
                <p class="value">$count_total</p>
            </div>
            <div class="card alive">
                <h3>Alive Hosts</h3>
                <p class="value">$count_alive</p>
            </div>
            <div class="card dead">
                <h3>Dead Hosts</h3>
                <p class="value">$count_dead</p>
            </div>
            <div class="card noip">
                <h3>Unresolved (No IP)</h3>
                <p class="value">$count_noip</p>
            </div>
        </div>

        <h2 class="section-title">💻 Technical Details</h2>
        <table>
            <tr>
                <th>Domain</th>
                <th>IP Address</th>
                <th>Status</th>
            </tr>
EOF

    # 1. Add ALIVE hosts first
    if [[ -f "output/${base_name}_alive.txt" ]]; then
        sort "output/${base_name}_alive.txt" | while read -r line; do
            domain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk '{print $2}')
            echo "            <tr><td>$domain</td><td>$ip</td><td><span class='badge alive'>ALIVE</span></td></tr>" >> "$html_file"
        done
    fi

    # 2. Add DEAD hosts next
    if [[ -f "output/${base_name}_dead.txt" ]]; then
        grep " - DEAD" "output/${base_name}_dead.txt" | sort | while read -r line; do
            domain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk '{print $2}')
            echo "            <tr><td>$domain</td><td>$ip</td><td><span class='badge dead'>DEAD</span></td></tr>" >> "$html_file"
        done

        # 3. Add NO IP hosts last
        grep " - NO IP" "output/${base_name}_dead.txt" | sort | while read -r line; do
            domain=$(echo "$line" | awk '{print $1}')
            echo "            <tr><td>$domain</td><td>-</td><td><span class='badge noip'>NO IP</span></td></tr>" >> "$html_file"
        done
    fi
    
    # Close HTML
    cat << EOF >> "$html_file"
        </table>
    </div>
</body>
</html>
EOF
    
    echo -e "${GREEN}[+]${NC} HTML report saved to: ${CYAN}$html_file${NC}"
}

# Function: ResolveAndCheck (multithreaded)
ResolveAndCheck() {
    local domains_file="$1"
    local base_name="$2"

    # Clear output files
    > "output/${base_name}_ips.txt"
    > "output/${base_name}_alive.txt"
    > "output/${base_name}_dead.txt"

    local total
    total=$(wc -l < "$domains_file")
    echo -e "${BLUE}[*] Checking $total hosts with $THREADS threads...${NC}"

    # Use xargs for parallel execution (no GNU parallel required)
    cat "$domains_file" | xargs -P "$THREADS" -I {} bash -c 'CheckHost "$@"' _ {} "$base_name"

    echo ""
    echo -e "${GREEN}[+]${NC} Alive hosts : ${GREEN}$(wc -l < "output/${base_name}_alive.txt")${NC}"
    echo -e "${GREEN}[+]${NC} Dead hosts  : ${RED}$(wc -l < "output/${base_name}_dead.txt")${NC}"
    echo -e "${GREEN}[+]${NC} IPs resolved: $(wc -l < "output/${base_name}_ips.txt")"
    echo -e "${GREEN}[+]${NC} Text results saved to output/${base_name}_alive.txt | _dead.txt | _ips.txt"
    
    # Generate HTML Report at the end
    GenerateHTML "$base_name"
}

# Create output directory
mkdir -p output

# Function: Domain
Domain() {
    if [ -z "$req" ]; then
        echo -e "${RED}[!] Error: Domain name is required.${NC}"
        exit 1
    fi

    echo -e "${BLUE}[*] Querying crt.sh for domain: $req${NC}"
    response=$(curl -s "https://crt.sh/?q=%25.$req&output=json")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        echo -e "${RED}[!] No results found for domain: $req${NC}"
        exit 1
    fi

    results=$(echo "$response" | jq -r '.[].common_name, .[].name_value' 2>/dev/null | CleanResults)

    if [ -z "$results" ]; then
        echo -e "${RED}[!] No valid subdomains extracted.${NC}"
        exit 1
    fi

    local output_file="output/domain.${req}.txt"
    echo "$results" > "$output_file"

    echo ""
    echo "$results"
    echo ""
    echo -e "${GREEN}[+]${NC} Total subdomains : ${RED}$(echo "$results" | wc -l)${NC}"
    echo -e "${GREEN}[+]${NC} Saved to         : $output_file"

    ResolveAndCheck "$output_file" "domain.${req}"
}

# Function: Organization
Organization() {
    if [ -z "$req" ]; then
        echo -e "${RED}[!] Error: Organization name is required.${NC}"
        exit 1
    fi

    echo -e "${BLUE}[*] Querying crt.sh for organization: $req${NC}"
    response=$(curl -s "https://crt.sh/?q=$req&output=json")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        echo -e "${RED}[!] No results found for organization: $req${NC}"
        exit 1
    fi

    results=$(echo "$response" | jq -r '.[].common_name' 2>/dev/null | CleanResults)

    if [ -z "$results" ]; then
        echo -e "${RED}[!] No valid results extracted.${NC}"
        exit 1
    fi

    local output_file="output/org.${req}.txt"
    echo "$results" > "$output_file"

    echo ""
    echo "$results"
    echo ""
    echo -e "${GREEN}[+]${NC} Total entries : ${RED}$(echo "$results" | wc -l)${NC}"
    echo -e "${GREEN}[+]${NC} Saved to      : $output_file"

    ResolveAndCheck "$output_file" "org.${req}"
}

# Main Script Logic
if [ -z "$1" ]; then
    Help
    exit 0
fi

while getopts ":hd:o:t:" option; do
    case $option in
        h) Help; exit 0 ;;
        d) req="$OPTARG"; Domain ;;
        o) req="$OPTARG"; Organization ;;
        t) THREADS="$OPTARG" ;;
        :) echo -e "${RED}[!] Option -$OPTARG requires an argument.${NC}"; exit 1 ;;
        \?) echo -e "${RED}[!] Unknown option: -$OPTARG${NC}"; Help; exit 1 ;;
    esac
done
