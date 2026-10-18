<#
.SYNOPSIS
  Teste une pile Compose (naive ou hardened) : tests fonctionnels puis tests d'exposition.
  Cible uniquement tes propres conteneurs locaux.
.EXAMPLE
  .\scripts\test-compose.ps1 -Stack naive
  .\scripts\test-compose.ps1 -Stack hardened
  .\scripts\test-compose.ps1 -Compare
#>
param(
  [ValidateSet("naive", "hardened")][string]$Stack,
  [switch]$Compare
)

# Script volontairement en ASCII (sans accents) pour eviter les problemes d'encodage de Windows PowerShell 5.1
$outDir = Join-Path $PSScriptRoot "..\reports\compose-tests"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ---------- Mode comparaison ----------
if ($Compare) {
  $nf = Join-Path $outDir "naive.csv"
  $hf = Join-Path $outDir "hardened.csv"
  if (-not (Test-Path $nf) -or -not (Test-Path $hf)) {
    Write-Host "Lance d'abord le script avec -Stack naive puis avec -Stack hardened."
    return
  }
  $n = Import-Csv $nf
  $h = Import-Csv $hf
  $rows = foreach ($t in $n) {
    $o = $h | Where-Object { $_.Id -eq $t.Id } | Select-Object -First 1
    [pscustomobject]@{ Id = $t.Id; Test = $t.Test; Naive = $t.Observed; Hardened = $o.Observed; Verdict = $o.Status }
  }
  $rows | Format-Table -AutoSize -Wrap
  $rows | Export-Csv (Join-Path $outDir "comparison.csv") -NoTypeInformation -Encoding UTF8
  return
}

if (-not $Stack) {
  Write-Host "Usage : .\scripts\test-compose.ps1 -Stack naive|hardened   ou   -Compare"
  return
}

# ---------- Configuration de la pile ----------
if ($Stack -eq "naive") {
  $project  = "conduit-naive"
  $apiBase  = "http://localhost:3001/api"
  $webBase  = "http://localhost:3000"
  $webCheck = "$webBase/"
  $imgBack  = "conduit-backend:naive"
} else {
  $project  = "conduit-hardened"
  $apiBase  = "http://localhost:8080/api"
  $webBase  = "http://localhost:8080"
  $webCheck = "$webBase/healthz"
  $imgBack  = "conduit-backend:hardened"
}
$db = "$project-db"; $be = "$project-backend"; $fe = "$project-frontend"
Write-Host "Test de la pile $Stack : conteneurs $db, $be, $fe"

$running = "$(docker inspect --format '{{.State.Running}}' $be 2>$null)".Trim()
if ($running -ne "true") {
  Write-Host "La pile $Stack ne tourne pas. Lance d'abord : docker compose -f docker-compose.$Stack.yml up -d"
  return
}

$results = New-Object System.Collections.ArrayList

function Add-Func($id, $test, $ok) {
  $obs = if ($ok) { "OK" } else { "ECHEC" }
  [void]$script:results.Add([pscustomobject]@{ Id = $id; Type = "Fonctionnel"; Test = $test; Observed = $obs; Status = $obs })
}

# $exposed = $true quand la faiblesse est presente
function Add-Sec($id, $test, $exposed) {
  $obs = if ($exposed) { "EXPOSE" } else { "EN SECURITE"}
  if ($Stack -eq "hardened") { $status = if ($exposed) { "ECHEC" } else { "OK" } } else { $status = "reference" }
  [void]$script:results.Add([pscustomobject]@{ Id = $id; Type = "Securite"; Test = $test; Observed = $obs; Status = $status })
}

function Test-Port($port) {
  $c = New-Object Net.Sockets.TcpClient
  try {
    $iar = $c.BeginConnect("127.0.0.1", $port, $null, $null)
    return ($iar.AsyncWaitHandle.WaitOne(2000, $false) -and $c.Connected)
  } catch { return $false } finally { $c.Close() }
}

function Get-Code($url) { "$(& curl.exe -s -m 5 -o NUL -w '%{http_code}' $url 2>$null)".Trim() }
function Get-Body($url) { "$(& curl.exe -s -m 5 $url 2>$null)" }

Add-Func "F1" "API /api/tags repond 200" ((Get-Code "$apiBase/tags") -eq "200")
Add-Func "F2" "Frontend repond 200" ((Get-Code $webCheck) -eq "200")

$dbHealth = "$(docker inspect --format '{{.State.Health.Status}}' $db 2>$null)".Trim()
Add-Func "F3" "Base de donnees healthy" ($dbHealth -eq "healthy")

$run = @(docker inspect --format '{{.State.Running}}' $db $be $fe 2>$null)
Add-Func "F4" "Les 3 conteneurs tournent" (@($run | Where-Object { $_ -eq "true" }).Count -eq 3)

$rand = Get-Random -Maximum 999999
$user = @{ user = @{ username = "test$rand"; email = "test$rand@example.com"; password = "Passw0rd-$rand" } }
try {
  Invoke-RestMethod -Method Post -Uri "$apiBase/users" -ContentType "application/json" -Body ($user | ConvertTo-Json) -TimeoutSec 8 | Out-Null
  $okReg = $true
} catch { $okReg = $false }
Add-Func "F5" "Inscription d'un utilisateur (ecriture en base)" $okReg

$login = @{ user = @{ email = "test$rand@example.com"; password = "Passw0rd-$rand" } }
try {
  Invoke-RestMethod -Method Post -Uri "$apiBase/users/login" -ContentType "application/json" -Body ($login | ConvertTo-Json) -TimeoutSec 8 | Out-Null
  $okLog = $true
} catch { $okLog = $false }
Add-Func "F6" "Connexion de cet utilisateur (JWT)" $okLog

# ---------- Tests d'exposition ----------
Add-Sec "S1" "Port PostgreSQL 5432 joignable depuis l'hote" (Test-Port 5432)
Add-Sec "S2" "Port API 3001 joignable depuis l'hote" (Test-Port 3001)

$dbImage = "$(docker inspect --format '{{.Config.Image}}' $db 2>$null)".Trim()
$o = docker run --rm -e PGPASSWORD=postgres -e PGCONNECT_TIMEOUT=3 $dbImage psql -h host.docker.internal -p 5432 -U postgres -d database_production -tAc "select 1" 2>$null
Add-Sec "S3" "Connexion a la base depuis l'hote avec postgres/postgres" ("$o".Trim() -eq "1")

$uid = "$(docker exec $be id -u 2>$null)".Trim()
Add-Sec "S4" "Backend execute en root" (-not ($uid -match "^[1-9][0-9]*$"))

$w = "$(docker exec $be sh -c 'touch /usr/local/bin/pwned 2>/dev/null && echo yes' 2>$null)".Trim()
if ($w -eq "yes") { docker exec $be rm -f /usr/local/bin/pwned 2>$null | Out-Null }
Add-Sec "S5" "Ecriture possible dans le systeme de fichiers du backend" ($w -eq "yes")

$cap = "$(docker exec $be sh -c 'grep CapEff /proc/self/status' 2>$null)"
$hex = if ($cap -match "CapEff:\s+([0-9a-f]+)") { $Matches[1] } else { "" }
Add-Sec "S6" "Capabilities Linux actives dans le backend" ($hex -ne "0000000000000000")

$imgEnv = "$(docker image inspect --format '{{json .Config.Env}}' $imgBack 2>$null)"
Add-Sec "S7" "Secret ecrit en clair dans les variables ENV de l'image backend" ($imgEnv -match "SECRET|PASSWORD|PASSWD|TOKEN|PRIVATE")

$vite = Get-Body "$webBase/@vite/client"
Add-Sec "S8" "Serveur de dev Vite expose (/@vite/client)" ($vite -match "createHotContext")

$nets = ("$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' $db 2>$null)").Trim().Split(" ")
$internal = $false
foreach ($nw in $nets) {
  if ($nw -and ("$(docker network inspect $nw --format '{{.Internal}}' 2>$null)".Trim() -eq "true")) { $internal = $true }
}
Add-Sec "S9" "Base de donnees sur un reseau non isole (non internal)" (-not $internal)

$mem = "$(docker inspect --format '{{.HostConfig.Memory}}' $be 2>$null)".Trim()
Add-Sec "S10" "Aucune limite de memoire sur le backend" ($mem -eq "0")

$so = "$(docker inspect --format '{{.HostConfig.SecurityOpt}}' $be 2>$null)"
Add-Sec "S11" "no-new-privileges absent sur le backend" ($so -notmatch "no-new-privileges")

$results | Format-Table Id, Type, Test, Observed, Status -AutoSize -Wrap
$results | Export-Csv (Join-Path $outDir "$Stack.csv") -NoTypeInformation -Encoding UTF8
$results | Format-Table Id, Type, Test, Observed, Status -AutoSize -Wrap | Out-String -Width 200 | Set-Content (Join-Path $outDir "$Stack.txt") -Encoding UTF8

$funcFail = @($results | Where-Object { $_.Type -eq "Fonctionnel" -and $_.Status -eq "ECHEC" }).Count
$secExposed = @($results | Where-Object { $_.Type -eq "Securite" -and $_.Observed -eq "EXPOSE" }).Count
Write-Host "Pile $Stack : $funcFail test(s) fonctionnel(s) en echec, $secExposed faiblesse(s) exposee(s)."
if ($Stack -eq "hardened" -and ($funcFail -gt 0 -or $secExposed -gt 0)) { exit 1 }