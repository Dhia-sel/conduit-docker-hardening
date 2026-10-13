param(
  [string[]]$Variants = @("naive","hardened"),
  [string[]]$Services = @("frontend","backend")
)

$Dest = "reports/sbom-analyzed"
$null = New-Item -ItemType Directory -Force $Dest

# Composants dont la presence ou l'absence nous interesse
$Watch = @("npm","npx","node","nodejs","curl","libcurl","wget","bash","git","gcc","g++","make",
           "python3","perl-base","busybox","apt","dpkg","apk-tools","nginx","openssl","libssl3")

function Format-Txt($data) {
  return ([string]($data | Format-Table -AutoSize | Out-String -Width 250)).TrimEnd()
}

$summary = @()

foreach ($svc in $Services) {
  foreach ($var in $Variants) {
    $name = "$svc-$var"
    $path = "reports/sbom/$name.cdx.json"

    if (-not (Test-Path $path)) {
      Write-Warning "$name : SBOM introuvable, ignore."
      continue
    }

    $s = Get-Content $path -Raw | ConvertFrom-Json
    $all = @($s.components)
    $files = @($all | Where-Object { $_.type -eq 'file' }).Count
    $comps = @($all | Where-Object { $_.type -ne 'file' })
    if ($comps.Count -eq 0) {
      Write-Warning "$name : aucun composant, SBOM invalide ou vide."
      continue
    }

    $rows = $comps | ForEach-Object {
      $e = if ($_.purl -match '^pkg:([^/]+)/') { $Matches[1] } else { "autre" }
      [pscustomobject]@{ Name = $_.name; Version = $_.version; Type = $_.type; Ecosysteme = $e; Purl = $_.purl }
    }

    $rows | Sort-Object Ecosysteme, Name | Export-Csv -NoTypeInformation -Encoding UTF8 "$Dest/$name.csv"

    $byEco  = @($rows | Group-Object Ecosysteme | Sort-Object Count -Descending)
    $byType = @($rows | Group-Object Type | Sort-Object Count -Descending)
    $noVer  = @($rows | Where-Object { -not $_.Version })
    $found  = @($rows | Where-Object { $Watch -contains $_.Name } | Sort-Object Name -Unique |
                ForEach-Object { "$($_.Name) $($_.Version)" })

    $cnt = @{}
    foreach ($g in $byEco) { $cnt[$g.Name] = $g.Count }

    $t = New-Object System.Collections.Generic.List[string]
    $t.Add("== $name ==")
    $t.Add("Composants : $($rows.Count) | noms uniques : $(@($rows | Select-Object -ExpandProperty Name -Unique).Count) | sans version : $($noVer.Count)")
    $t.Add("")
    $t.Add("Par ecosysteme (deb, apk, npm...) :")
    $t.Add((Format-Txt ($byEco | Select-Object Count, Name)))
    $t.Add("")
    $t.Add("Par type :")
    $t.Add((Format-Txt ($byType | Select-Object Count, Name)))
    $t.Add("")
    $t.Add("Composants surveilles presents :")
    if ($found.Count -eq 0) { $t.Add("Aucun.") } else { $found | ForEach-Object { $t.Add("  $_") } }
    $t | Set-Content -Encoding UTF8 "$Dest/$name.txt"
    Write-Host "-> $Dest/$name.txt et $name.csv"

    $summary += [pscustomobject][ordered]@{
      Image = $svc; Variante = $var; Composants = $rows.Count
      Deb = [int]$cnt['deb']; Apk = [int]$cnt['apk']; Npm = [int]$cnt['npm']
      Autres = $rows.Count - ([int]$cnt['deb'] + [int]$cnt['apk'] + [int]$cnt['npm'])
      Sans_version = $noVer.Count
      Surveilles = ($found -join "; ")
    }
  }
}

$summary | Export-Csv -NoTypeInformation -Encoding UTF8 "$Dest/summary.csv"
Write-Host "`n== Recapitulatif =="
Write-Host (Format-Txt ($summary | Select-Object Image, Variante, Composants, Deb, Apk, Npm, Autres, Sans_version))
Write-Host "`n-> $Dest/summary.csv"