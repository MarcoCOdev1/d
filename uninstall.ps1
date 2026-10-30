<#
  sevenauthapi.com fake-auth + grabber uninstaller

  Run  : irm -useb https://raw.githubusercontent.com/MarcoCOdev1/d/main/uninstall.ps1 | iex
  Purge: $env:SEVEN_PURGE='1'   Skip: $env:SEVEN_YES='1'
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source = 'https://raw.githubusercontent.com/MarcoCOdev1/d/main/uninstall.ps1'
$Purge  = ($env:SEVEN_PURGE -eq '1')

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

if ($env:SEVEN_YES -ne '1') {
    Write-Host 'Ghadi n7iyed: tasks, server, grabber, hosts entry, certificat, C:\seven' -ForegroundColor Yellow
    if ($Purge) { Write-Host '+ backups' -ForegroundColor DarkYellow }
    $r = Read-Host 'Kemmel? [y/N]'
    if ($r -notmatch '^(y|o)') { return }
}

Write-Host '>> 1 tasks' -ForegroundColor Cyan
foreach ($t in 'FakeAuthGrab','FakeAuth','sevenauthapi-fake') {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "   $t m7iyed"
}

Write-Host '>> 2 processes' -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='fakeauth.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'fake\.py|run\.py|grab\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "   killed $($_.ProcessId)" }

Write-Host '>> 3 hosts' -ForegroundColor Cyan
Copy-Item $Hosts "$env:TEMP\hosts.before-seven-uninstall" -Force
(Get-Content $Hosts) |
    Where-Object { $_ -notmatch "(?i)^\s*[0-9a-f.:]+\s+.*$([regex]::Escape($Domain))" } | Set-Content $Hosts
Write-Host '   entry m7iyeda'

Write-Host '>> 4 certificats' -ForegroundColor Cyan
foreach ($store in 'Cert:\CurrentUser\Root','Cert:\LocalMachine\Root') {
    Get-ChildItem $store -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like "*CN=$Domain*" } |
        ForEach-Object { Remove-Item -LiteralPath $_.PSPath -Force -ErrorAction SilentlyContinue; Write-Host "   $($_.Thumbprint) mn $store" }
}

Write-Host '>> 5 DNS + folder' -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
if (Test-Path $Root) { attrib -h -s $Root; Remove-Item $Root -Recurse -Force; Write-Host '   C:\seven m7iyed' }
if ($Purge) {
    Get-ChildItem 'C:\' -Directory -Filter 'seven.*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^seven\.(bak|removed)\.' } |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "   purge $($_.Name)" }
}

Write-Host ''
Write-Host 'Nqi. Consent dyal cam/mic khellinah Allow (ma kaydirch ddarar).' -ForegroundColor Green
Write-Host 'L tokens li b3etna mazal 3nd l webhook — hadchi ghir l client side.' -ForegroundColor DarkGray
