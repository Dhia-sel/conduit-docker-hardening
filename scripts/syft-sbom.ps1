param([string]$Variant = "naive")

$null = New-Item -ItemType Directory -Force reports/sbom

foreach ($svc in "frontend","backend") {
  $image = "conduit-${svc}:${Variant}"

  docker image inspect $image *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Image $image introuvable, on passe."
    continue
  }

  Write-Host "== Syft : $image =="

  docker run --rm `
    -v /var/run/docker.sock:/var/run/docker.sock `
    -v "${PWD}/reports/sbom:/out" `
    anchore/syft $image -o "cyclonedx-json=/out/${svc}-${Variant}.cdx.json"

  $sbom = Get-Content "reports/sbom/${svc}-${Variant}.cdx.json" -Raw | ConvertFrom-Json
  $count = @($sbom.components).Count
  Write-Host "-> $count composant(s) pour $svc ($Variant)`n"
}