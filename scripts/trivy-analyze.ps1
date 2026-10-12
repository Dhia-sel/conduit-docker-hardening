param(
  [string[]]$Variants = @("naive","hardened"),
  [string[]]$Services = @("frontend","backend")
)

$Dest = "reports/trivy-analyzed"
$null = New-Item -ItemType Directory -Force $Dest
$Order = @{ CRITICAL = 0; HIGH = 1; MEDIUM = 2; LOW = 3; UNKNOWN = 4 }

function Get-Vulns([string]$Path) {
  if (-not (Test-Path $Path)) { return $null }
  $r = Get-Content $Path -Raw | ConvertFrom-Json
  if (-not $r.Results) { return $null }
  $list = @()
  foreach ($res in $r.Results) {
    foreach ($v in @($res.Vulnerabilities)) {
      if ($v) {
        $list += [pscustomobject]@{
          Severity  = $v.Severity
          Target    = $res.Target
          Package   = $v.PkgName
          Installed = $v.InstalledVersion
          Fixed     = $v.FixedVersion
          Fixable   = [bool]$v.FixedVersion
          CVE       = $v.VulnerabilityID
          Title     = $v.Title
        }
      }
    }
  }
  return ,$list
}

function Format-Txt($data) {
  return ([string]($data | Format-Table -AutoSize | Out-String -Width 250)).TrimEnd()
}

$summary = @()

foreach ($svc in $Services) {
  foreach ($var in $Variants) {
    $name = "$svc-$var"
    $v  = Get-Vulns "reports/trivy/$name.json"
    $fx = Get-Vulns "reports/trivy/$name-fixable.json"

    if ($null -eq $v) {
      Write-Warning "$name : scan introuvable ou invalide (pas de Results), ignore."
      continue
    }

    $sorted = @($v | Sort-Object @{Expression={ $Order[$_.Severity] }}, Package)
    $sorted | Export-Csv -NoTypeInformation -Encoding UTF8 "$Dest/$name.csv"

    $row = [ordered]@{ Image = $svc; Variante = $var; Total = $sorted.Count }
    foreach ($s in "CRITICAL","HIGH","MEDIUM","LOW") {
      $row[$s] = @($sorted | Where-Object { $_.Severity -eq $s }).Count
    }
    $fixAll = @($sorted | Where-Object { $_.Fixable })
    $fixCH  = @($fixAll | Where-Object { $_.Severity -in "CRITICAL","HIGH" })
    $row["Corrigeables"] = $fixAll.Count
    $row["Corr_C_H"] = $fixCH.Count
    if ($null -ne $fx) { $row["Fichier_fixable"] = @($fx).Count } else { $row["Fichier_fixable"] = "n/a" }
    $summary += [pscustomobject]$row

    $ch = @($sorted | Where-Object { $_.Severity -in "CRITICAL","HIGH" })
    $t = New-Object System.Collections.Generic.List[string]
    $t.Add("== $name ==")
    $t.Add("Total : $($row['Total']) | CRITICAL $($row['CRITICAL']) | HIGH $($row['HIGH']) | MEDIUM $($row['MEDIUM']) | LOW $($row['LOW'])")
    $t.Add("Corrigeables : $($row['Corrigeables']) (dont CRITICAL/HIGH : $($row['Corr_C_H'])) | fichier -fixable : $($row['Fichier_fixable'])")
    $t.Add("")
    $t.Add("Par cible :")
    $t.Add((Format-Txt ($sorted | Group-Object Target | Sort-Object Count -Descending | Select-Object Count, Name)))
    $t.Add("")
    $t.Add("A traiter en priorite (CRITICAL/HIGH avec correctif) :")
    if ($fixCH.Count -eq 0) { $t.Add("Aucune.") }
    else { $t.Add((Format-Txt ($fixCH | Select-Object Severity, Target, Package, Installed, Fixed, CVE))) }
    $t.Add("")
    $t.Add("A documenter (CRITICAL/HIGH sans correctif) :")
    $noFix = @($ch | Where-Object { -not $_.Fixable })
    if ($noFix.Count -eq 0) { $t.Add("Aucune.") }
    else { $t.Add((Format-Txt ($noFix | Select-Object Severity, Target, Package, Installed, CVE))) }

    $t | Set-Content -Encoding UTF8 "$Dest/$name.txt"
    Write-Host "-> $Dest/$name.txt et $name.csv"
  }
}

$summary | Export-Csv -NoTypeInformation -Encoding UTF8 "$Dest/summary.csv"
Write-Host "`n== Recapitulatif =="
Write-Host (Format-Txt $summary)
Write-Host "`n-> $Dest/summary.csv"