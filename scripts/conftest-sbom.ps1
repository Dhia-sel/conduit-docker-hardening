param(
  [string[]]$Variants = @("naive","hardened"),
  [string[]]$Services = @("frontend","backend")
)

$Dest = "reports/conftest"
$null = New-Item -ItemType Directory -Force $Dest

foreach ($svc in $Services) {
  foreach ($var in $Variants) {
    $name = "$svc-$var"
    $sbom = "reports/sbom/$name.cdx.json"
    if (-not (Test-Path $sbom)) { Write-Warning "$name : SBOM introuvable."; continue }

    Write-Host "== Conftest : $name =="
    $out = docker run --rm -v "${PWD}:/project" openpolicyagent/conftest test $sbom -p policy/common -p policy/$svc | Out-String
    $out | Set-Content -Encoding UTF8 "$Dest/$name.txt"
    Write-Host $out
  }
}
Write-Host "-> $Dest/"