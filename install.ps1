<#
  sevenauthapi.com local fake-auth installer (all-in-one, iex-safe, autostart)

  Run  : irm -useb https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1 | iex
  Undo : irm -useb https://raw.githubusercontent.com/MarcoCOdev1/d/main/uninstall.ps1 | iex

  Builds C:\seven, installs cryptography, generates + trusts a root cert for
  sevenauthapi.com, points the domain to 127.0.0.1, w kay sajjel Scheduled Task
  kay tle3 l server f kol logon (pythonw, bla console, restart automatique).
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source = 'https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1'
$Uninstall = ($env:SEVEN_UNINSTALL -eq '1')

# ---------- self-elevate ----------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
         [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    $self = $PSCommandPath
    if (-not $self) {
        $self = Join-Path $env:TEMP 'seven-install.ps1'
        Invoke-WebRequest -UseBasicParsing $Source -OutFile $self
    }
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
    Start-Process powershell -Verb RunAs -ArgumentList $a
    Write-Host 'UAC tlob — 9bel w kemmel f l window jdida.' -ForegroundColor Yellow
    return
}

$Root   = 'C:\seven'
$Cert   = Join-Path $Root 'cert.pem'
$Cer    = Join-Path $Root 'seven.cer'
$Hosts  = Join-Path $env:windir 'System32\drivers\etc\hosts'
$Domain = 'sevenauthapi.com'
$Task   = 'sevenauthapi-fake'

# ================= 00 - n9i ay install qdim =================
Write-Host '>> 00 cleanup qdim' -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'fake\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*CN=$Domain*" } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ================= 01 - folder + dependency =================
Write-Host '>> 01 folder + dependency' -ForegroundColor Cyan
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { throw 'python ma kaynch f PATH' }
$pyw = Join-Path (Split-Path $py.Source) 'pythonw.exe'
if (-not (Test-Path $pyw)) { $pyw = $py.Source }

if (Test-Path $Root) {
    $bak = "$Root.bak." + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Rename-Item $Root $bak
    Write-Host "   $Root lqdim tnaqel l $bak" -ForegroundColor DarkYellow
}
New-Item -ItemType Directory -Path $Root | Out-Null
Set-Location $Root
python -m pip install cryptography --disable-pip-version-check

# ================= 02 - makecert.py =================
Write-Host '>> 02 makecert.py' -ForegroundColor Cyan
$makecert = @(
'from cryptography import x509'
'from cryptography.x509.oid import NameOID'
'from cryptography.hazmat.primitives import hashes, serialization'
'from cryptography.hazmat.primitives.asymmetric import rsa'
'import datetime'
''
'k = rsa.generate_private_key(public_exponent=65537, key_size=2048)'
'n = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "sevenauthapi.com")])'
'now = datetime.datetime.now(datetime.timezone.utc)'
''
'c = (x509.CertificateBuilder().subject_name(n).issuer_name(n)'
'     .public_key(k.public_key()).serial_number(x509.random_serial_number())'
'     .not_valid_before(now - datetime.timedelta(days=1))'
'     .not_valid_after(now + datetime.timedelta(days=3650))'
'     .add_extension(x509.SubjectAlternativeName(['
'         x509.DNSName("sevenauthapi.com"), x509.DNSName("*.sevenauthapi.com")]), False)'
'     .add_extension(x509.BasicConstraints(ca=True, path_length=None), True)'
'     .sign(k, hashes.SHA256()))'
''
'open("cert.pem","wb").write('
'    k.private_bytes(serialization.Encoding.PEM,'
'        serialization.PrivateFormat.TraditionalOpenSSL,'
'        serialization.NoEncryption()) + c.public_bytes(serialization.Encoding.PEM))'
'open("seven.cer","wb").write(c.public_bytes(serialization.Encoding.DER))'
'print("OK")'
) -join "`n"

# ================= 02b - run.py (redirect log) =================
Write-Host '>> 02b run.py' -ForegroundColor Cyan
$runner = @(
'import os, sys, time'
''
'os.chdir(os.path.dirname(os.path.abspath(__file__)))'
'log = "server.log"'
'try:'
'    if os.path.getsize(log) > 2 * 1024 * 1024:'
'        os.replace(log, "server.old.log")'
'except OSError:'
'    pass'
''
'f = open(log, "a", encoding="utf-8", buffering=1)'
'sys.stdout = f'
'sys.stderr = f'
'print("")'
'print("=== start", time.strftime("%Y-%m-%d %H:%M:%S"), "pid", os.getpid(), "===")'
''
'src = open("fake.py", encoding="utf-8").read()'
'exec(compile(src, "fake.py", "exec"), {"__name__": "__main__"})'
) -join "`n"

# ================= 04 - fake.py =================
Write-Host '>> 04 fake.py' -ForegroundColor Cyan
$fake = @(
'import ssl, json, base64, hashlib, time, uuid, secrets'
'from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler'
''
'YEAR = 365 * 24 * 3600 * 1000'
''
'def token(hwid):'
'    now = int(time.time() * 1000)'
'    p = {"k": secrets.token_hex(12),'
'         "h": hashlib.sha256(hwid.encode()).hexdigest()[:24],'
'         "c": secrets.token_hex(8),'
'         "e": now + 10 * YEAR}'
'    b = base64.urlsafe_b64encode(json.dumps(p, separators=(",", ":")).encode()).decode().rstrip("=")'
'    sig = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")'
'    return b + "." + sig'
''
'class H(BaseHTTPRequestHandler):'
'    daemon_threads = True'
'    def do_GET(self): self.x()'
'    def do_POST(self): self.x()'
'    def x(self):'
'        n = int(self.headers.get("Content-Length") or 0)'
'        raw = self.rfile.read(n)'
'        print(">>>", self.path, raw)'
'        try: req = json.loads(raw or b"{}")'
'        except: req = {}'
'        now = int(time.time() * 1000)'
'        body = {"success": True, "message": "Authorized", "data": {'
'            "product": {"id": "6ac401b8ca0d96ab19f8c388", "name": "FPS Unlocker",'
'                        "hash": req.get("productHash", "")},'
'            "username": req.get("username", "user"),'
'            "sessionToken": token(req.get("hwid", "")),'
'            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime((now + 10 * YEAR) / 1000)),'
'            "expiresAtUnix": now + 10 * YEAR,'
'            "daysLeft": 3650,'
'            "serverTimeUnix": now,'
'            "secondsLeft": 10 * YEAR // 1000,'
'            "config": None},'
'            "requestId": str(uuid.uuid4()),'
'            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now / 1000))}'
'        b = json.dumps(body).encode()'
'        self.send_response(200)'
'        self.send_header("Content-Type", "application/json; charset=utf-8")'
'        self.send_header("x-censor-enabled", "1")'
'        self.send_header("Content-Length", str(len(b)))'
'        self.end_headers()'
'        self.wfile.write(b)'
'    def log_message(self, fmt, *a): pass'
''
'ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)'
'ctx.load_cert_chain("cert.pem")'
's = ThreadingHTTPServer(("0.0.0.0", 443), H)'
's.socket = ctx.wrap_socket(s.socket, server_side=True)'
'print("fake :443")'
's.serve_forever()'
) -join "`n"

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Root 'makecert.py'), $makecert, $utf8)
[IO.File]::WriteAllText((Join-Path $Root 'run.py'),     $runner,  $utf8)
[IO.File]::WriteAllText((Join-Path $Root 'fake.py'),    $fake,    $utf8)

# ================= 03 - generate + trust =================
Write-Host '>> 03 generate + trust cert' -ForegroundColor Cyan
python makecert.py
if (-not (Test-Path $Cer)) { throw 'cert generation failed' }
$c = Import-Certificate -FilePath $Cer -CertStoreLocation 'Cert:\CurrentUser\Root'
Write-Host "   trusted: $($c.Thumbprint)" -ForegroundColor Green

# ================= 05 - hosts =================
Write-Host '>> 05 hosts' -ForegroundColor Cyan
Copy-Item $Hosts (Join-Path $Root 'hosts.bak') -Force
(Get-Content $Hosts) | Where-Object { $_ -notmatch [regex]::Escape($Domain) } | Set-Content $Hosts
Add-Content -Path $Hosts -Value "127.0.0.1 $Domain"
ipconfig /flushdns | Out-Null

$ok = $false
foreach ($t in (Test-Connection -ComputerName $Domain -Count 1 -ErrorAction SilentlyContinue)) {
    if ("$($t.Address)" -eq '127.0.0.1') { $ok = $true }
}
if ($ok) { Write-Host "   $Domain -> 127.0.0.1 OK" -ForegroundColor Green }
else     { Write-Host "   WARN: ma resoluich — 3awd ipconfig /flushdns" -ForegroundColor Red }

# ================= 06 - autostart task =================
Write-Host '>> 06 autostart' -ForegroundColor Cyan
$action  = New-ScheduledTaskAction -Execute $pyw -Argument 'run.py' -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
             -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DontStopOnIdleEnd
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Settings $set `
    -Principal $principal -Description 'sevenauthapi.com local fake auth server' -Force | Out-Null
Write-Host "   task '$Task' msajjel (AtLogOn)" -ForegroundColor Green

Start-ScheduledTask -TaskName $Task
Start-Sleep -Seconds 4

# ================= verification =================
Write-Host ''
Write-Host '--- verification ---' -ForegroundColor Cyan
$st = (Get-ScheduledTask -TaskName $Task).State
Write-Host "   task: $st"
if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host '   port 443: LISTEN' -ForegroundColor Green
} else {
    Write-Host '   port 443: MA KAYCHTACH — chouf C:\seven\server.log' -ForegroundColor Red
}
if (Test-Path (Join-Path $Root 'server.log')) {
    Write-Host '   log: C:\seven\server.log' -ForegroundColor DarkGray
    Get-Content (Join-Path $Root 'server.log') -Tail 5 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host 'Wajed. L server kaytle3 bo7do f kol logon — bla terminal.' -ForegroundColor Green
Write-Host 'Controle:  Get-ScheduledTask sevenauthapi-fake   |   log: C:\seven\server.log' -ForegroundColor DarkGray
