# Journal du projet 1 : résultats des tests

> À placer dans `docs/JOURNAL.md`. Dernière mise à jour : 2026-10-15.
> `à relever` : valeur non encore mesurée.

## 1. Résultats

| Mesure | frontend naïve | frontend durcie | backend naïve | backend durcie |
|---|---|---|---|---|
| Taille (disk usage / content size) | 2,12 Go / 536 Mo | **98,9 Mo / 27,8 Mo** | 2,12 Go / 536 Mo | **378 Mo / 86,7 Mo** |
| Couches | 16 | 36 | 16 | 19 |
| Utilisateur à l'exécution | root | **101** | root | **1000** |
| Failles Trivy (total) | 4 199 | **0** | 4 199 | **234** |
| CRITICAL / HIGH | 21 / 379 | 0 / 0 | 21 / 379 | **1 / 48** |
| MEDIUM / LOW | 2 291 / 1 453 | 0 / 0 | 2 291 / 1 453 | 100 / 84 |
| Corrigeables (dont C/H) | 1 540 (110) | 0 | 1 540 (110) | 6 (0) |
| Paquets (SBOM) | 911 | **22** (apk) | 911 | **208** (88 deb, 120 npm) |
| Alertes Hadolint | 2 | **0** | 2 | **0** |
| Règles Conftest | 10 échecs / 11 tests | **0 échec / 5** | 9 échecs / 10 tests | **0 échec / 4** |

Les deux images naïves ont les mêmes couches (`COPY . .` embarque tout le monorepo), donc des chiffres identiques.
Le nombre de couches n'est pas un indicateur de durcissement (36 pour le frontend durci contre 16 pour la naïve).

Variations : frontend -98 % de paquets et -95 % de taille ; backend -77 % de paquets, -94 % de failles, 400 vers 49 en CRITICAL/HIGH.

## 2. Méthode des tests

| Outil | Ce qui est testé | Lancement | Détail |
|---|---|---|---|
| Trivy | Failles des images (système et paquets npm) | `scripts/trivy-scan.ps1 <naive\|hardened>` | `--skip-db-update` et volume `trivy-cache` : même base pour toutes les images. **Date de la base : à relever.** |
| Hadolint | Dockerfiles (analyse statique) | `scripts/hadolint-scan.ps1 <variante>` | Naïves : `DL3007` (tag `latest`) et `DL3064` (donnée sensible dans `ENV`/`ARG`, faux secret volontaire). Durcies : 0 après correction de `DL3066` (utilisateur non numérique) et `DL3025` (`HEALTHCHECK` en forme shell). |
| Syft | Inventaire des composants (SBOM CycloneDX) | `scripts/syft-sbom.ps1 <variante>` | Paquets comptés sur le type `library` ; les fichiers catalogués, le système et l'application sont exclus. |
| Conftest (OPA) | Règles de composition sur les SBOM | `scripts/conftest-sbom.ps1` | Voir ci-dessous. **Version de Conftest : à relever** (lancé en `:latest`). |
| Docker | Taille, couches, utilisateur | `docker images`, `docker history -q`, `docker image inspect --format "{{.Config.User}}"` | Utilisateur vide = root. |

Analyse des résultats : `scripts/trivy-analyze.ps1` (rapports dans `reports/trivy-analyzed/`) et `scripts/sbom-analyze.ps1` (`reports/sbom-analyzed/`).

Règles Conftest (`policy/`) :
- composants interdits dans une image finale : `npm`, `gcc`, `g++`, `make`, `git`, `python3`, `wget`, `curl`, `libcurl` ;
- `node` interdit dans le frontend ;
- seuils de paquets : 40 (frontend), 250 (backend) ;
- paquet sans version (règle présente, jamais exercée).

Chaque règle a été vue échouer sur une image naïve et passer sur la durcie.

## 3. Failles restantes (backend durci)

49 lignes CRITICAL/HIGH, soit **11 CVE uniques**, aucune avec correctif publié à la date de la base :

| Source | CVE | Paquets |
|---|---|---|
| `util-linux` | 5 | 8 (`mount`, `bsdutils`, `libblkid1`, `libmount1`, `libsmartcols1`, `libuuid1`, `util-linux`, `util-linux-extra`) |
| `ncurses` | 1 | 3 |
| `systemd` | 1 | 2 |
| `zlib` (CRITICAL) | 1 | 1 |
| `gzip`, `acl`, `perl` | 1 chacune | 1 chacun |

Il reste aussi 6 failles Node.js MEDIUM/LOW corrigeables.

## 4. Limites des mesures

- Les naïves sont sur Debian 13 et Node 26.10 ; les durcies sur Debian 12 et Node 22.23.3 (backend) ou Alpine (frontend) : une partie de l'écart vient du changement de base.
- Les failles dépendent de la base de vulnérabilités à une date donnée : le zéro du frontend n'est pas permanent.
- Conftest prouve l'absence des composants listés, pas la sécurité de l'image.
- Pas encore testé en fonctionnement : le backend durci avec PostgreSQL (migration, `/api/tags`, healthcheck) et les tests d'attaque.