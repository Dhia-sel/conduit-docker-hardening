param([string]$Variant = "naive")

New-Item -ItemType Directory -Force reports/trivy | Out-Null

foreach ($svc in "frontend","backend") {
  $image = "conduit-${svc}:${Variant}"
  docker run --rm `
    -v /var/run/docker.sock:/var/run/docker.sock `
    -v trivy-cache:/root/.cache/ `
    -v "${PWD}/reports/trivy:/out" `
    aquasec/trivy image --format json --output "/out/${svc}-${Variant}.json" $image
  docker run --rm `
    -v /var/run/docker.sock:/var/run/docker.sock `
    -v trivy-cache:/root/.cache/ `
    -v "${PWD}/reports/trivy:/out" `
    aquasec/trivy image --ignore-unfixed --format json --output "/out/${svc}-${Variant}-fixable.json" $image
}