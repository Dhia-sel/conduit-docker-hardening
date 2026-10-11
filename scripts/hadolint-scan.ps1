param([string]$Variant = "naive")

$null = New-Item -ItemType Directory -Force reports/hadolint

foreach ($svc in "frontend","backend") {
  $dockerfile = if ($Variant -eq "naive") { "$svc/Dockerfile.naive" } else { "$svc/Dockerfile" }

  if (-not (Test-Path $dockerfile)) {
    Write-Warning "$dockerfile introuvable, on passe."
    continue
  }

  Write-Host "== Hadolint : $dockerfile =="

  Get-Content $dockerfile -Raw |
    docker run --rm -i hadolint/hadolint /bin/hadolint --format tty - |
    Tee-Object -FilePath "reports/hadolint/${svc}-${Variant}.txt"

  $json = Get-Content $dockerfile -Raw |
    docker run --rm -i hadolint/hadolint /bin/hadolint --format json - |
    Out-String
  $json | Set-Content -Encoding UTF8 "reports/hadolint/${svc}-${Variant}.json"

  try {
    $count = @($json | ConvertFrom-Json -ErrorAction Stop).Count
    Write-Host "-> $count alerte(s) pour $svc ($Variant)`n"
  } catch {
    Write-Warning "Sortie Hadolint illisible pour $svc ($Variant) : voir reports/hadolint/${svc}-${Variant}.json"
  }

}
