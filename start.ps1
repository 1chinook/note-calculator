param(
    [switch]$NoBrowser,
    [switch]$StopOnly
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$ProjectName = 'not-hesaplama'
$OpenUrl = 'http://localhost:3003'
$ProjectDir = $PSScriptRoot

function Get-ListeningPids {
    param([Parameter(Mandatory = $true)][int]$Port)

    $pids = New-Object 'System.Collections.Generic.HashSet[int]'
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        foreach ($conn in $conns) {
            if ($conn.OwningProcess -gt 4 -and $conn.OwningProcess -ne $PID) {
                [void]$pids.Add([int]$conn.OwningProcess)
            }
        }
    } catch {}

    $prevEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $netstatLines = & netstat.exe -ano -p TCP 2>$null
    } finally {
        $ErrorActionPreference = $prevEap
    }

    foreach ($line in $netstatLines) {
        if ($line -match "^\s*TCP\s+\S+:$Port\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $foundPid = [int]$Matches[1]
            if ($foundPid -gt 4 -and $foundPid -ne $PID) {
                [void]$pids.Add($foundPid)
            }
        }
    }
    return @($pids)
}

function Stop-ProcessTreeSafe {
    param([Parameter(Mandatory = $true)][int]$TargetPid)
    $prevEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & taskkill.exe /F /T /PID $TargetPid *> $null
    } finally {
        $ErrorActionPreference = $prevEap
    }
    Stop-Process -Id $TargetPid -Force -ErrorAction SilentlyContinue
}

function Stop-PortProcess {
    param([Parameter(Mandatory = $true)][int]$Port)

    $pidFile = Join-Path $env:TEMP ("projects-launcher-port-{0}.pid" -f $Port)
    if (Test-Path -LiteralPath $pidFile) {
        $rawPidLine = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($rawPidLine) {
            $parts = $rawPidLine.Trim().Split('|')
            $wrapperPid = 0
            [long]$expectedTicks = 0
            if ([int]::TryParse($parts[0], [ref]$wrapperPid) -and $wrapperPid -gt 4 -and $wrapperPid -ne $PID) {
                if ($parts.Length -gt 1) { [void][long]::TryParse($parts[1], [ref]$expectedTicks) }
                $proc = Get-Process -Id $wrapperPid -ErrorAction SilentlyContinue
                if ($proc -and $proc.ProcessName -match '^(powershell|pwsh)$') {
                    $matchesStart = $true
                    if ($expectedTicks -gt 0) {
                        try { $matchesStart = ($proc.StartTime.ToFileTimeUtc() -eq $expectedTicks) } catch { $matchesStart = $false }
                    }
                    if ($matchesStart) {
                        Write-Host "  [Temizlik] Onceki baslatici penceresi kapatiliyor (PID: $wrapperPid, Port: $Port)..." -ForegroundColor Yellow
                        Stop-ProcessTreeSafe -TargetPid $wrapperPid
                    }
                }
            }
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }

    $listeningPids = Get-ListeningPids -Port $Port
    foreach ($targetPid in $listeningPids) {
        $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        $procName = if ($proc) { $proc.ProcessName } else { 'bilinmeyen' }
        Write-Host "  [Temizlik] Port $Port uzerindeki eski surec sonlandiriliyor ($procName, PID: $targetPid)..." -ForegroundColor Yellow
        Stop-ProcessTreeSafe -TargetPid $targetPid
    }

    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline) {
        if ((Get-ListeningPids -Port $Port).Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 200
    }

    $remaining = Get-ListeningPids -Port $Port
    if ($remaining.Count -gt 0) {
        throw "Port $Port bosaltilamadi. Kalan PID'ler: $($remaining -join ', ')"
    }
}

function Test-TcpPort {
    param([Parameter(Mandatory = $true)][int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        return ($task.Wait(300) -and $client.Connected)
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Wait-ServiceReady {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$HealthUrl,
        [int]$TimeoutSec = 30,
        [System.Diagnostics.Process]$WrapperProcess = $null
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($null -ne $WrapperProcess -and $WrapperProcess.HasExited -and -not (Test-TcpPort -Port $Port)) {
            throw "$Name servisi beklenmedik sekilde kapandi (Cikis kodu: $($WrapperProcess.ExitCode))."
        }
        if (Test-TcpPort -Port $Port) {
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 2 -ErrorAction Stop
                if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                    return
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 350
    }
    throw "$Name servisi $TimeoutSec saniye icinde hazir olmadi ($HealthUrl)."
}

function Resolve-WorkingPython {
    $candidates = @()
    $pyCmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pyCmd) { $candidates += @{ Exe = $pyCmd.Source; Prefix = @() } }
    $pyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyLauncher) { $candidates += @{ Exe = $pyLauncher.Source; Prefix = @('-3') } }
    foreach ($glob in @("$env:LOCALAPPDATA\Programs\Python\Python*\python.exe", "C:\Python*\python.exe")) {
        foreach ($match in (Get-Item -Path $glob -ErrorAction SilentlyContinue)) {
            $candidates += @{ Exe = $match.FullName; Prefix = @() }
        }
    }

    foreach ($cand in $candidates) {
        $prevEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $argsList = @($cand.Prefix) + @('-c', 'import http.server, sys; sys.exit(0)')
            & $cand.Exe @argsList *> $null
            if ($LASTEXITCODE -eq 0) {
                return $cand
            }
        } catch {
        } finally {
            $ErrorActionPreference = $prevEap
        }
    }
    return $null
}

try {
    Write-Host "=== $ProjectName ===" -ForegroundColor Cyan

    Stop-PortProcess -Port 3003
    if ($StopOnly) {
        Write-Host "[OK] $ProjectName durduruldu (Port: 3003)." -ForegroundColor Green
        exit 0
    }

    $pythonInfo = Resolve-WorkingPython
    $startCmd = $null

    if ($null -ne $pythonInfo) {
        $pyExeEsc = $pythonInfo.Exe.Replace("'", "''")
        $prefixArgs = ($pythonInfo.Prefix | ForEach-Object { "'$_'" }) -join ' '
        $startCmd = "& '$pyExeEsc' $prefixArgs -m http.server 3003 --bind 127.0.0.1".Trim()
        Write-Host "[Sunucu] Python http.server kullanilacak." -ForegroundColor Gray
    } else {
        $nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($nodeCmd) {
            $nodeStaticJs = @'
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const root = process.cwd();
const port = Number(process.env.PORT || 3003);
const mime = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
  ".webmanifest": "application/manifest+json"
};
http.createServer((req, res) => {
  const reqPath = decodeURIComponent((req.url || "/").split("?")[0]);
  const rel = reqPath === "/" ? "index.html" : reqPath.replace(/^\/+/, "");
  const full = path.resolve(root, rel);
  const check = path.relative(root, full);
  if (check.startsWith("..") || path.isAbsolute(check)) {
    res.writeHead(403).end("Forbidden");
    return;
  }
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404).end("Not found"); return; }
    res.writeHead(200, { "Content-Type": mime[path.extname(full).toLowerCase()] || "application/octet-stream", "Cache-Control": "no-cache" });
    res.end(data);
  });
}).listen(port, "127.0.0.1", () => console.log("Not Hesaplama: http://127.0.0.1:" + port));
'@
            $jsB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nodeStaticJs))
            $nodeEsc = $nodeCmd.Source.Replace("'", "''")
            $startCmd = "& '$nodeEsc' -e `"eval(Buffer.from('$jsB64','base64').toString('utf8'))`""
            Write-Host "[Sunucu] Calisan Python bulunamadi; yerlesik Node.js statik sunucu kullanilacak." -ForegroundColor Gray
        } else {
            $npxCmd = Get-Command npx.cmd -ErrorAction SilentlyContinue
            if (-not $npxCmd) {
                throw "Statik HTML sunucusu baslatmak icin Python, Node.js veya npx bulunamadi."
            }
            $npxEsc = $npxCmd.Source.Replace("'", "''")
            $startCmd = "& '$npxEsc' --yes serve -l tcp://127.0.0.1:3003 ."
        }
    }

    $Services = @(
        @{
            Name         = 'Not Hesaplama Static Web'
            Port         = 3003
            WorkDir      = $ProjectDir
            HealthUrl    = 'http://127.0.0.1:3003/'
            WindowTitle  = 'not-hesaplama [Port 3003]'
            TimeoutSec   = 30
            StartCommand = $startCmd
        }
    )

    $launched = @()
    foreach ($svc in $Services) {
        $titleEscaped = $svc.WindowTitle.Replace("'", "''")
        $dirEscaped = $svc.WorkDir.Replace("'", "''")
        $childScript = @"
try { `$Host.UI.RawUI.WindowTitle = '$titleEscaped' } catch {}
Set-Location -LiteralPath '$dirEscaped'
`$env:PORT = '$($svc.Port)'
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  $titleEscaped' -ForegroundColor Green
Write-Host '  URL: $OpenUrl' -ForegroundColor Cyan
Write-Host '  Kapatmak icin Ctrl+C veya pencereyi kapatin.' -ForegroundColor DarkGray
Write-Host '========================================' -ForegroundColor Cyan
$($svc.StartCommand)
"@
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childScript))
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -WorkingDirectory $svc.WorkDir -PassThru
        $pidFile = Join-Path $env:TEMP ("projects-launcher-port-{0}.pid" -f $svc.Port)
        $startTicks = try { $proc.StartTime.ToFileTimeUtc() } catch { 0 }
        Set-Content -LiteralPath $pidFile -Value ("{0}|{1}" -f $proc.Id, $startTicks) -Encoding ASCII
        $launched += @{ Service = $svc; Process = $proc }
        Write-Host "[Baslatildi] $($svc.Name) -> Port $($svc.Port) (Pencere PID: $($proc.Id))" -ForegroundColor Green
    }

    foreach ($item in $launched) {
        $svc = $item.Service
        Write-Host "[Bekleniyor] $($svc.Name) saglik kontrolu ($($svc.HealthUrl))..." -ForegroundColor Cyan
        Wait-ServiceReady -Name $svc.Name -Port $svc.Port -HealthUrl $svc.HealthUrl -TimeoutSec $svc.TimeoutSec -WrapperProcess $item.Process
        Write-Host "[Hazir] $($svc.Name) -> $($svc.HealthUrl)" -ForegroundColor Green
    }

    if (-not $NoBrowser) {
        Write-Host "[Tarayici] Aciliyor: $OpenUrl" -ForegroundColor Cyan
        Start-Process $OpenUrl
    }
    exit 0
} catch {
    Write-Host "[HATA] $($_.Exception.Message)" -ForegroundColor Red
    if (-not $NoBrowser -and [Environment]::UserInteractive) {
        try { $null = Read-Host 'Cikmak icin Enter tusuna basin' } catch {}
    }
    exit 1
}
