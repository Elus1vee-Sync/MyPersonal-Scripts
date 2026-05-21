##If it won't let you run it, write beforehand. --> Set-ExecutionPolicy -Scope Process Bypass
## This script is intended and designed primarily for when you are pivoting or are on a local network from another computer.

param(
    [string]$Target
)

########################################
# COLORS
########################################

$RED     = "Red"
$GREEN   = "Green"
$YELLOW  = "Yellow"
$BLUE    = "Blue"
$MAGENTA = "Magenta"
$CYAN    = "Cyan"

########################################
# PERFORMANCE
########################################

$THREADS = 50

## 100 FAST LAN
## 300 NORMAL LAN
## 1000 WAN

$TIMEOUT = 2

########################################
# TOP PORTS
########################################

$TopPorts = @(
21,22,23,25,53,80,110,111,135,139,
143,443,445,993,995,1723,3306,
3389,5900,5985,5986,8080,8443
)

########################################
# STORAGE
########################################

$AliveHosts = @()
$OpenPorts  = @{}
$HostOS     = @{}

########################################
# BANNER
########################################

function Show-Banner {

    Write-Host ""

    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "             FAST NETWORK SCANNER               " -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan

    Write-Host ""

    Write-Host "[*] High Performance TCP Scanner" -ForegroundColor Green
    Write-Host "[*] GitHub: https://github.com/Elus1vee-Sync/" -ForegroundColor Yellow
    Write-Host "[*] Threads: $THREADS" -ForegroundColor Magenta
    Write-Host "[*] Timeout: $TIMEOUT ms" -ForegroundColor Magenta

    Write-Host ""
}

########################################
# OS DETECTION
########################################

function Detect-OS {

    param($TTL)

    if ($TTL -le 64) {

        return "LINUX"

    }
    elseif ($TTL -le 128) {

        return "WINDOWS"

    }
    else {

        return "NETWORK DEVICE"
    }
}

########################################
# HOST DISCOVERY
########################################

function Test-Alive {

    param($IP)

    ####################################
    # ICMP
    ####################################

    try {

        $Ping = Test-Connection -ComputerName $IP -Count 1 -ErrorAction Stop

        if ($Ping) {

            $TTL = $Ping[0].ReplyOptions.Ttl

            $OS = Detect-OS $TTL

            $HostOS[$IP] = $OS

            Write-Host "[+] Host Alive -> $IP [$OS | TTL=$TTL]" -ForegroundColor Green

            return $true
        }

    }
    catch {}

    ####################################
    # ARP FALLBACK
    ####################################

    try {

        arp -a | Out-Null

        $ArpEntry = arp -a | Select-String $IP

        if ($ArpEntry) {

            $HostOS[$IP] = "UNKNOWN"

            Write-Host "[+] Host Alive -> $IP [ARP ONLY]" -ForegroundColor Yellow

            return $true
        }

    }
    catch {}

    return $false
}

########################################
# DISCOVER HOSTS
########################################

function Discover-Hosts {

    $Base = ($Target.Split('/')[0] -split '\.')[0..2] -join '.'

    Write-Host ""
    Write-Host "[*] Discovering alive hosts..." -ForegroundColor Magenta
    Write-Host ""

    1..254 | ForEach-Object {

        $IP = "$Base.$_"

        if (Test-Alive $IP) {

            $Global:AliveHosts += $IP
        }
    }
}

########################################
# PORT SCAN
########################################

function Scan-Ports {

    param($IP)

    Write-Host ""
    Write-Host "[*] Scanning ports on $IP" -ForegroundColor Magenta
    Write-Host ""

    $OpenPorts[$IP] = @()

    $Count = 0
    $Total = $TopPorts.Count

    foreach ($Port in $TopPorts) {

        ####################################
        # PROGRESS BAR
        ####################################

        $Count++

        $Percent = [int](($Count / $Total) * 100)

        Write-Progress `
            -Activity "Scanning $IP" `
            -Status "Port $Port ($Count / $Total)" `
            -PercentComplete $Percent

        ####################################
        # TEST PORT
        ####################################

        try {

            $Result = Test-NetConnection `
                -ComputerName $IP `
                -Port $Port `
                -WarningAction SilentlyContinue

            if ($Result.TcpTestSucceeded) {

                Write-Host ("[+] {0}:{1} OPEN" -f $IP, $Port) -ForegroundColor Green

                $OpenPorts[$IP] += $Port
            }

        }
        catch {}
    }

    Write-Progress `
        -Activity "Scanning $IP" `
        -Completed

    Write-Host ""
    Write-Host "[*] Finished scanning $IP" -ForegroundColor Magenta
    Write-Host ""
}

########################################
# MAIN
########################################

Show-Banner

if (-not $Target) {

    Write-Host ""
    Write-Host "Usage: .\Scanr_ports.ps1 [IP | CIDR]"
    Write-Host ""

    exit
}

########################################
# SINGLE HOST
########################################

if ($Target -notmatch "/") {

    if (Test-Alive $Target) {

        $AliveHosts += $Target

    }
    else {

        Write-Host ""
        Write-Host "[-] Host appears down" -ForegroundColor Red
        Write-Host ""

        exit
    }

}
else {

    ####################################
    # NETWORK MODE
    ####################################

    Discover-Hosts
}

########################################
# SCANNING
########################################

Write-Host ""
Write-Host "[*] Starting port scans..." -ForegroundColor Magenta
Write-Host ""

foreach ($IP in $AliveHosts) {

    Scan-Ports $IP
}

########################################
# SUMMARY
########################################

Write-Host ""
Write-Host "[*] Scan Summary" -ForegroundColor Magenta
Write-Host ""

Write-Host "HOST                 OS                 OPEN PORTS" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------" -ForegroundColor Cyan

foreach ($IP in $AliveHosts) {

    $Ports = $OpenPorts[$IP] -join " "

    if (-not $Ports) {

        $Ports = "NONE"
    }

    $OS = $HostOS[$IP]

    switch ($OS) {

        "LINUX" {
            $Color = "Yellow"
        }

        "WINDOWS" {
            $Color = "Blue"
        }

        default {
            $Color = "Magenta"
        }
    }

    Write-Host -NoNewline ($IP.PadRight(21)) -ForegroundColor Cyan
    Write-Host -NoNewline ($OS.PadRight(19)) -ForegroundColor $Color
    Write-Host $Ports -ForegroundColor Red
}

Write-Host ""