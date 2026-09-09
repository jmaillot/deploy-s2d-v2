# S2DCluster — Guide d'utilisation

> English version: [README.md](README.md).

Déploie un cluster Storage Spaces Direct (S2D) à deux nœuds sur Windows Server 2025 :
préparation réseau/stockage par nœud, puis création du cluster avec quorum,
activation S2D et volume CSV en miroir. PowerShell 5.1, français/anglais gérés.

## 0. Prérequis

- [ ] 2x Windows Server 2025 (Datacenter), rôles Failover-Clustering + Hyper-V
- [ ] **Cartes 10 GbE ou plus avec RDMA obligatoires sur le fabric de stockage** —
  le pré-contrôle refuse tout lien plus lent. En dessous de 10 GbE, le trafic de
  resynchronisation sature le lien.
- [ ] PERC/HBA en mode **pass-through (HBA), pas RAID** — le pré-contrôle refuse
  l'absence de disques agrégeables. Prévoir du SSD/NVMe pour le cache
  (tout-HDD = avertissement).
- [ ] Firmware/drivers des cartes à jour (le pré-contrôle affiche un tableau —
  vérifiez-le contre la matrice constructeur), virtualisation BIOS active pour SR-IOV
- [ ] 1x témoin : partage de fichiers (`\\serveur\partage$`) ou Cloud Witness Azure
- [ ] 1x IP statique de cluster ; IP statiques de stockage par nœud sur des
  **sous-réseaux différents**
- [ ] Console élevée **sur les nœuds eux-mêmes** — ne jamais lancer NodePrep depuis
  un poste de travail (il renomme les cartes *locales*)

Fiche à remplir avant de commencer (exemple) :

| Rôle | HV1 | HV2 |
|---|---|---|
| Cartes Mgmt | Mgmt01, Mgmt02 | Mgmt01, Mgmt02 |
| Cartes VM | Vm01, Vm02 | Vm01, Vm02 |
| StorageA carte / IP | Storage01 / 192.168.200.1 | Storage01 / 192.168.200.2 |
| StorageB carte / IP | Storage02 / 192.168.201.1 | Storage02 / 192.168.201.2 |
| LiveMig carte (+IP opt.) | Live01 | Live01 |
| Cluster | ClusterPDL / 192.168.1.240, témoin `\\NTSVR22\ClusterPDL$` | |

## 1. Préparer chaque nœud (en local, en admin, sur HV1 puis HV2)

Copiez d'abord le dossier sur le nœud — le sélecteur liste les cartes *locales*.

```powershell
Import-Module .\Deploy-S2D\Deploy-S2D.psm1
Start-S2DNodePrep -MgmtAdapters "Mgmt01","Mgmt02" -VMAdapters "Vm01","Vm02" -StorageA "Storage01" -StorageB "Storage02" -LiveMigrationAdapter "Live01" -StorageAIP "192.168.200.1" -StorageBIP "192.168.201.1"
```

Omettez un nom de carte pour le choisir dans un menu console numéroté — chaque
menu indique le rôle que votre choix **sera renommé** (`1/5` StorageA … `5/5` VM).
MGMT/VM acceptent des listes (`0,2`) ; vide = aucun ; `Q` = abandon. Les cartes
déjà choisies disparaissent des menus suivants ; une carte ne peut pas servir
deux rôles.

Ordre d'exécution : pré-contrôle (lecture seule — ≥4 cartes, 10 Gbps + RDMA
prouvé, disques agrégeables) → renommage (vérifié après coup) → MTU jumbo + IP
statiques → QoS/DCB + RDMA → vSwitch (équipe SET pour 2+ cartes VM, simple pour 1)
→ VMQ/RSS/RSC on + Jumbo off (VM), VMQ/RSC/EEE off + RSS on (storage), VMQ/EEE off (Mgmt) → liaison du réseau de migration (seulement avec `-LiveMigrationIP`,
sinon avertissement).

| Paramètre | Requis | Notes |
|---|---|---|
| `MgmtAdapters`, `VMAdapters` | non — sélecteur si omis | Nombre quelconque (1+) |
| `StorageA/B`, `LiveMigrationAdapter` | non — sélecteur si omis | Exactement **2 stockage** (les deux fabrics) et exactement **1 LiveMig** — par conception |
| `StorageAIP/BIP` | oui | IP de ce nœud ; doivent différer et être sur des **sous-réseaux différents** |
| `StoragePrefix` | non | Défaut `24` (plage 1–31) |
| `LiveMigrationIP/Prefix` | non | Lie *le* réseau de migration (`Add-VMMigrationNetwork`) ; omis = avertissement |
| `LogPath` | non | Défaut `C:\S2D_Deployment.log` |

Toujours répéter d'abord (`-WhatIf`). Le pré-contrôle s'exécute même en dry-run.

## 2. Créer le cluster (une fois, depuis un nœud)

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
```

Valide (`Test-Cluster`, français d'abord/anglais sinon), crée le cluster, configure
le quorum, active S2D, crée le(s) volume(s) CSV (ReFS) avec la résilience choisie,
contraint SMB Multichannel à StorageA/B, renomme les réseaux du cluster. Témoin cloud :

```powershell
$key = Read-Host -AsSecureString
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "Cloud" -AzStorageAccount "acc" -AzStorageKey $key -SizingMode "Auto"
```

La clé est `SecureString` de bout en bout — déchiffrée uniquement pour l'appel
quorum, effacée ensuite, jamais journalisée.

### Stockage : résilience, volumes et dimensionnement

| `-Resiliency` | Utile (part du pool brut) | Survit à | Quand l'utiliser |
|---|---|---|---|
| `Mirror` (défaut) | 50 % | 1 panne (disque ou nœud) | Labo, vitesse max, volumes SSD |
| `NestedMirror` | 25 % | 2 pannes | 2 nœuds en production, sécurité max |
| `NestedParity` | ~35-40 % | 2 pannes | 2 nœuds en production, équilibré (choix Microsoft) |

Utile = la part du pool brut disponible pour les données : 50 % transforment
10 To bruts en 5 To de volumes. Les volumes imbriqués ne se convertissent
pas après coup — à choisir dès le départ.
`-NestedMirrorPercent` (10-30, défaut 20) règle la part rapide des
volumes `NestedParity` : plus haut favorise les rafales d'écriture, plus bas
la capacité.

**Volumes.** `-VolumeCount` (1-64, défaut 1) crée `Nom_01`, `Nom_02`… à
partir de `-VolumeName` comme préfixe (1 conserve le nom exact). Au moins un
volume par nœud pour répartir la propriété. Une seule valeur `-Resiliency` /
`-StorageTier` s'applique à tous ; une par volume pour mixer (voir les cas
ci-dessous). Note : S2D déclare les disques SAS rotatifs avec le type de
média `HDD`, donc la valeur `-StorageTier` pour SAS reste `HDD`.

### Vos disques décident de tout

S2D réserve automatiquement le média le plus rapide comme cache. Le cache
sert les données chaudes mais n'apporte aucune capacité utile. Quatre cas :

**Cas A — SSD + SAS, sans NVMe (un seul tier SAS).** Les SSD deviennent le
cache lecture/écriture ; tous les volumes sont sur SAS. Impossible de créer
des volumes SSD — mais les données chaudes des VM restent servies depuis le
SSD automatiquement : dimensionnez le cache pour l'ensemble de travail
(~10 % de la capacité SAS : 4x 4 To SAS par serveur → 2x 800 Go de cache
SSD). Gardez `-StorageTier` sur `Auto` (prend SAS) ; forcer `SSD` avertit.
La réserve plancher ne compte que SAS. Exemple : pool SAS brut de 32 To
avec plancher de 8 To (2 nœuds x disque 4 To) → utile `Mirror` ≈
(libres − 8 To) x 50 %.

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV_S2D" -SizingMode "Auto"
```

**Cas B — NVMe + SSD + SAS (deux tiers).** NVMe devient le cache ; SSD et
SAS sont tous deux capacitatifs, donc les volumes peuvent se répartir des
deux côtés (lectures SSD directes, cache lecture/écriture pour SAS). Le
montage pour VM chaudes sur SSD et données froides sur SAS — épinglez par
volume :

```powershell
New-S2DCluster -ClusterName "ClusterPDL" -ClusterNodes "HV1","HV2" -ClusterIP "192.168.1.240" -WitnessType "FileShare" -FileShareWitness "\\NTSVR22\ClusterPDL$" -VolumeName "CSV" -VolumeCount 2 -StorageTier SSD,HDD -Resiliency Mirror,NestedParity -SizingMode "Auto"
# -> CSV_01 : Mirror sur SSD (VM chaudes) | CSV_02 : NestedParity sur SAS (froid)
```

2x NVMe par serveur suffisent (dimensionnés pour l'ensemble de travail,
pas pour la capacité). La réserve plancher compte un SSD plus un SAS par
serveur.

**Cas C — SSD seuls (tout-flash).** Pas de tier cache (cache écriture seule
en option) ; tout est de la capacité SSD rapide. Le montage le plus simple :
`-StorageTier` `Auto` prend SSD, la réserve compte SSD, aucune décision
d'épinglage.

**Cas D — SAS seuls (disques rotatifs, sans flash).** Configuration S2D
invalide à elle seule — chaque serveur a besoin de flash pour le cache (au
moins 2 disques cache SSD/NVMe à côté de 4+ disques capacitatifs). Ajoutez
des SSD (devient cas A) ou du NVMe (devient cas B une fois des SSD présents,
sinon SAS cachés par NVMe).

**Dimensionnement.** `Auto` (défaut) répartit la capacité utile — chaque
volume reçoit une part égale d'empreinte pool fois son rendement.
`Fixed` exige `-VolumeSize` par volume (ex. `2TB`) et valide l'empreinte
totale contre l'espace libre. Les deux gardent une réserve sauf
`-UseFullPool` : un disque capacitif par serveur (max 4, selon le cas
ci-dessus) contre `-CapacityReservePercent` (défaut 20) — le plus grand
gagne. Avant toute création, le script affiche les Gio utiles par option
de résilience. Volumes plafonnés à 64 To (10 To pour sauvegardes
VSS/Volsnap) ; avertissement sous 4 disques capacitatifs par serveur.

## 3. Valider le déploiement

```powershell
Get-VirtualDisk | Format-Table FriendlyName, HealthStatus, OperationalStatus
Get-StorageJob
Get-StoragePool -FriendlyName "S2D on ClusterPDL" | Select-Object Size, AllocatedSize
```

Plus le Gestionnaire de cluster de basculement : réseaux StorageA/StorageB/Mgmt,
témoin en ligne, CSV monté. Lancez un vrai `Test-Cluster` avant la mise en
production (les dry-runs `-WhatIf` le sautent par conception).

## 4. Opérations courantes

Redémarrage sûr (depuis l'*autre* nœud ; `-Force -WhatIf` pour répéter) :

```powershell
.\Scripts\Reboot-S2D.ps1 -NodeName "HV1"
```

Drapeaux de santé des disques (helper Don MacGregor, tel quel) :

Efface les drapeaux persistants (*Intent*/*Policy*) que le Health Service de
Windows conserve sur les disques après un incident. À utiliser quand : un disque
remplacé reste affiché malsain/retiré (état fantôme), un disque sain est refusé
à tort pour l'agrégation (`CanPool = False`) après un incident transitoire
(câble, baie, firmware) déjà corrigé, ou vous recyclez des disques de lab
porteurs des drapeaux d'un ancien pool.

Règle d'or : **d'abord vérifier la santé réelle, ensuite effacer — jamais pour
masquer du matériel mourant.** Effacer sur un disque vraiment en panne le fait
juste retomber en erreur au cycle suivant, avec un pool dégradé entre-temps.

```powershell
# 1. D'abord la santé réelle (SMART, LED, statut opérationnel)
Get-PhysicalDisk -SerialNumber <sn> | Format-List FriendlyName, HealthStatus, OperationalStatus
# 2. Seulement si le matériel est sain et le flag obsolète :
Get-PhysicalDisk -UniqueId <id> | Clear-PhysicalDiskHealthData -Intent -Policy -Force
```

## Dépannage

| Symptôme | Cause / correctif |
|---|---|
| `found 3 physical NIC(s), minimum 4` | Pas un nœud (ou cartes manquantes). NodePrep exige StorageA/B + LiveMig + ≥1 VM. |
| `link is 1 Gbps, 10 Gbps minimum required` | Carte/switch/câble sous la spec. Corrigez le matériel, relancez. |
| `not RDMA-capable` / `RDMA capability unproven` | Activez la pile RDMA / installez le driver constructeur d'abord. |
| `no poolable disks (CanPool)` | PERC en RAID — basculez le contrôleur en HBA/pass-through. |
| `resolves to N adapter(s)` après renommage | Collision d'un run partiel — nettoyez le doublon, relancez. |
| Pas d'invite Mandatory / comportement figé | Vieux module en session — `Import-Module ... -Force` à chaque console. |
| `Test-Cluster` incompatible | FR puis EN intégrés ; autres locales : étendez la liste. |

## Référence

- Module `Deploy-S2D/` (v1.6.0, publiable) : `Start-S2DNodePrep`,
  `New-S2DCluster`, `Start-S2DDeployment` (wrapper de compat). `Public/` = une
  fonction par fichier, `Private/` = helpers, `en-US/` = aide conceptuelle.
  `Scripts/` = runbook de redémarrage, helper tiers, one-shots. `archive/` = retiré.
- Tests : `Tests/` (Pester 5) + `.github/workflows/ci.yml` (erreurs d'analyse + Pester).
  En local : `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Error`
  puis `Invoke-Pester -Path ./Tests -Output Detailed`.
- Notes de conception : exactement 2 cartes stockage (deux fabrics) et exactement
  1 LiveMig par conception ; aucune valeur d'environnement en défaut dans le code
  partagé (le moteur invite à la place) ; chaque chemin destructeur gère `-WhatIf` ;
  reprise unique, après resynchronisation.

## Tests & lint (fin de checklist)

```powershell
Import-Module .\Deploy-S2D\Deploy-S2D.psm1 -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./Tests -Output Detailed
```

L'analyseur doit rapporter zéro `Error` (les avertissements s'affichent pour info ;
`Write-Host` est exclu par conception — la sortie console, c'est l'UX de déploiement).
Pester lance 15 tests : manifeste, contrats de paramètres, gardes aux limites, deux
runs NodePrep mockés. GitHub Actions lance les deux à chaque push/PR
(`windows-latest`, PowerShell 5.1).
