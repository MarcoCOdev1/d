<#
  sevenauthapi.com local fake-auth installer (all-in-one, iex-safe)

  Run  : irm -useb https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1 | iex
  Undo : $env:SEVEN_UNINSTALL='1'; irm -useb <same url> | iex

  Builds C:\seven, installs cryptography, generates + trusts a root cert for
  sevenauthapi.com, points the domain to 127.0.0.1, starts the fake HTTPS server.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source = 'https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1'
$Uninstall = ($env:SEVEN_UNINSTALL -eq '1')

# ---------- self-elevate (hosts file + root store) ----------
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

# ================= UNINSTALL =================
if ($Uninstall) {
    Write-Host '>> Uninstall' -ForegroundColor Cyan
    (Get-Content $Hosts) | Where-Object { $_ -notmatch [regex]::Escape($Domain) } | Set-Content $Hosts
    Write-Host '   hosts entry removed'
    Get-ChildItem Cert:\CurrentUser\Root |
        Where-Object { $_.Subject -like "*CN=$Domain*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host '   root cert removed'
    ipconfig /flushdns | Out-Null
    if (Test-Path $Root) { Rename-Item $Root ("$Root.removed." + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    Write-Host '   done. Ila l server baqi kheddam, seddo b Ctrl+C.' -ForegroundColor Green
    return
}

# ================= 01 - fresh folder + dependency =================
Write-Host '>> 01 folder + dependency' -ForegroundColor Cyan
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'python ma kaynch f PATH' }
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

# ================= 04 - fake.py =================
Write-Host '>> 04 fake.py' -ForegroundColor Cyan
$fake = @(
'import ssl, json, base64, hashlib, time, uuid, secrets'
'from http.server import HTTPServer, BaseHTTPRequestHandler'
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
''
'ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)'
'ctx.load_cert_chain("cert.pem")'
's = HTTPServer(("0.0.0.0", 443), H)'
's.socket = ctx.wrap_socket(s.socket, server_side=True)'
'print("fake :443")'
's.serve_forever()'
) -join "`n"

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Root 'makecert.py'), $makecert, $utf8)
[IO.File]::WriteAllText((Join-Path $Root 'fake.py'),     $fake,     $utf8)

# ================= 03 - generate + trust =================
Write-Host '>> 03 generate + trust cert' -ForegroundColor Cyan
python makecert.py
if (-not (Test-Path $Cer)) { throw 'cert generation failed' }

Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Subject -like "*CN=$Domain*" } |
    Remove-Item -Force -ErrorAction SilentlyContinue
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
else     { Write-Host "   WARN: ma resoluich l 127.0.0.1 — 3awd ipconfig /flushdns" -ForegroundColor Red }

# ================= 06 - run =================
if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host '   WARN: port 443 deja msta3mal. L server y9der yfchel.' -ForegroundColor Red
}

Write-Host ''
Write-Host 'Kolchi wajed. cert.pem fih la cle privee — khelliha 3ndek.' -ForegroundColor Yellow
Write-Host 'Ctrl+C kay wqqef l server.' -ForegroundColor DarkGray
Read-Host 'Daght Enter bach tla3 l server'
python fake.py
