$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source = 'https://raw.githubusercontent.com/MarcoCOdev1/d/main/uninstall.ps1'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
         [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $PSCommandPath) {
    $tmp = Join-Path $env:TEMP 'seven-uninstall.ps1'
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

Write-Host '>> 1 tasks' -ForegroundColor Cyan
foreach ($t in 'FakeAuthGrab','FakeAuth') {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host '>> 2 processes' -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='fakeauth.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'fake\.py|run\.py|agent\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host '>> 3 hosts' -ForegroundColor Cyan
Copy-Item $Hosts "$env:TEMP\hosts.before-seven-uninstall" -Force
(Get-Content $Hosts) |
    Where-Object { $_ -notmatch "(?i)^\s*[0-9a-f.:]+\s+.*$([regex]::Escape($Domain))" } | Set-Content $Hosts

Write-Host '>> 4 cert' -ForegroundColor Cyan
foreach ($store in 'Cert:\CurrentUser\Root','Cert:\LocalMachine\Root') {
    Get-ChildItem $store -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*CN=$Domain*" } |
        ForEach-Object { Remove-Item -LiteralPath $_.PSPath -Force -ErrorAction SilentlyContinue }
}

Write-Host '>> 5 folder' -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
if (Test-Path $Root) { attrib -h -s $Root; Remove-Item $Root -Recurse -Force }
if ($env:SEVEN_PURGE -eq '1') {
    Get-ChildItem 'C:\' -Directory -Filter 'seven.*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^seven\.bak\.' } |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host 'OK' -ForegroundColor Green
Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
