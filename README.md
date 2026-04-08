# 🌐 crt-harvester

<pre>
 ██████╗██████╗ ████████╗       ██╗  ██╗ █████╗ ██████╗ ██╗   ██╗███████╗███████╗████████╗███████╗██████╗ 
██╔════╝██╔══██╗╚══██╔══╝█████╗ ██║  ██║██╔══██╗██╔══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██║     ██████╔╝   ██║   ╚════╝ ███████║███████║██████╔╝██║   ██║█████╗  ███████╗   ██║   █████╗  ██████╔╝
██║     ██╔══██╗   ██║          ██╔══██║██╔══██║██╔══██╗╚██╗ ██╔╝██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗
╚██████╗██║  ██║   ██║          ██║  ██║██║  ██║██║  ██║ ╚████╔╝ ███████╗███████║   ██║   ███████╗██║  ██║
 ╚═════╝╚═╝  ╚═╝   ╚═╝          ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
</pre>

**crt-harvester** is a fast, multithreaded passive reconnaissance tool designed for bug bounty hunters and penetration testers. It fetches TLS/SSL certificate transparency logs directly from the **[crt.sh](https://crt.sh/)** database to enumerate subdomains, resolves their IP addresses, performs alive/dead checking, and generates beautifully styled HTML reports.

<img width="1250" height="735" alt="image" src="https://github.com/user-attachments/assets/401e7457-36bb-427a-9057-ef73afdbaf8d" />

---

## 🚀 Features

- **Passive Subdomain Enumeration:** Extracts common names and alternate names securely and passively via the `crt.sh` JSON API.
- **Multithreaded Resolution:** Quickly resolves subdomains to IP addresses using parallel threading (default: 20 threads).
- **Alive/Dead Host Checking:** Pings resolved IPs to verify if the host is actively responding.
- **Sharable HTML Reports:** Automatically compiles the text results into a clean, color-coded HTML table for easy viewing.
- **Clean Output:** Auto-filters wildcard certificates (`*.`), invalid email strings, and duplicates.

## 📋 Prerequisites

Ensure you have the following standard Linux utilities installed before running the script:

- `curl` (for making HTTP requests to crt.sh)
- `jq` (for parsing the JSON response)
- `dig` (usually part of `dnsutils` or `bind-utils`, for IP resolution)
- `ping` (for host discovery)

**To install dependencies on Debian/Ubuntu:**
```bash
sudo apt update
sudo apt install curl jq dnsutils iputils-ping -y
```

## 🛠️ Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/SwapnilkumarRane/crt-harvester.git
cd crt-harvester
chmod +x crt-harvester.sh
```

## 💻 Usage

```text
Options:

  -h             Help
  -d <domain>    Search by Domain Name    | Example: ./crt-harvester.sh -d example.com
  -o <org>       Search by Organization   | Example: ./crt-harvester.sh -o example+inc
  -t <threads>   Thread count             | Example: ./crt-harvester.sh -d example.com -t 50
```

<img width="864" height="503" alt="image" src="https://github.com/user-attachments/assets/03d99372-ea5d-4a47-bf14-b0cd788bec7c" />


### Examples

**Search for a specific domain:**
```bash
./crt-harvester.sh -d example.com
```

**Search by Organization name with 40 threads:**
```bash
./crt-harvester.sh -o "Example Inc" -t 40
```

## 📂 Output Structure

All findings are automatically saved into an `output/` directory created in your current working path. After a successful run, you will find:

- `domain.example.com.txt` - The raw, deduplicated list of subdomains.
- `domain.example.com_ips.txt` - Subdomains mapped to their resolved IPv4 addresses.
- `domain.example.com_alive.txt` - Hosts that successfully responded to ICMP echo requests.
- `domain.example.com_dead.txt` - Hosts that resolved to an IP but did not respond to ping, or failed to resolve.
- **`domain.example.com_report.html`** - A styled, interactive HTML table presenting all findings in a single dashboard.

## 🛠️ Troubleshooting

"No valid results extracted" Error
Because this tool relies on the public crt.sh API, you may occasionally run into temporary server timeouts. If you see the following output:

[*] Querying crt.sh for domain: example.com
[!] No valid results extracted.
Solution: This is a known hiccup with the crt.sh database and not a bug in the script. Simply re-run your command after a few minutes and it should fetch the data successfully.


## ⚠️ Disclaimer

This tool is designed **strictly for authorized security testing, educational purposes, and bug bounty programs**. Do not use this tool against infrastructure you do not own or have explicit permission to test. The author is not responsible for any misuse of this tool.
