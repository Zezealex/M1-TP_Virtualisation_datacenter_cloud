# TP1 — Pré-lab Proxmox VE dans VMware Workstation Pro 26H1

Formateur : Gaëtan
Contexte : VM Proxmox VE déjà créée et installée dans VMware Workstation avant la séance. Ce document trace les vérifications et corrections faites en amont, avec preuves à l'appui.

---

## 1. Vérification des ressources de l'hôte Windows

Commande exécutée (PowerShell) :

```powershell
Get-CimInstance Win32_Processor |
Select Name,NumberOfCores,NumberOfLogicalProcessors,VirtualizationFirmwareEnabled

Get-CimInstance Win32_ComputerSystem |
Select @{N="RAM_GB";E={[math]::Round($_.TotalPhysicalMemory/1GB,1)}}
```

**Résultat obtenu :**

```
Name                                 NumberOfCores NumberOfLogicalProcessors VirtualizationFirmwareEnabled
----                                 ------------- ------------------------- -----------------------------
12th Gen Intel(R) Core(TM) i7-12700H            14                        20                          True

RAM_GB
------
  31,7
```

**Analyse :** cible du pré-lab = 16 Go RAM / 8 threads logiques / virtualisation active. Résultat largement au-dessus (14 cœurs / 20 threads, 31,7 Go RAM, `VirtualizationFirmwareEnabled = True`). Aucun point bloquant côté hôte.

Point de vigilance noté : le i7-12700H est un CPU hybride (P-cores + E-cores). Pas de blocage constaté sur Workstation Pro 26H1, mais à garder en tête comme première piste en cas d'instabilité une fois la virtualisation imbriquée (nested) active dans Proxmox.

---

## 2. Configuration du réseau virtuel (Éditeur de réseau virtuel)

Logiciel : VMware Workstation Pro 26H1 — Edit → Virtual Network Editor.

### 2.1 Problème rencontré

Tentative de passer **VMnet2** en type **Pont**, avec le message d'erreur :

> Impossible de modifier le réseau pour ajouter un pont : il n'y a pas de carte réseau hôte sans pont.

**Cause :** VMnet0 était en pontage **Automatique**, ce qui capte par défaut toutes les cartes réseau physiques bridgeables de l'hôte — il ne restait donc aucune carte libre à assigner à VMnet2.

![Erreur lors de la tentative de pont sur VMnet2](preuves/01_erreur_bridge_vmnet2.png)

### 2.2 Correction appliquée

Dans les **Paramètres de pontage automatique** de VMnet0, décoché la carte **Intel(R) Ethernet Connection (16) I219-LM** (l'unique carte Ethernet physique du PC) pour la retirer du pool automatique et la réserver à VMnet2. Les autres adaptateurs (Wi-Fi AX211, Wi-Fi Direct, Bluetooth PAN) restent cochés et inchangés pour ne pas impacter le reste du réseau de l'hôte.

![Carte Ethernet I219-LM décochée du pontage automatique](preuves/02_parametres_pontage_auto_vmnet0.png)

### 2.3 Résultat

VMnet2 configuré en **Pont**, explicitement sur **Intel(R) Ethernet Connection (16) I219-LM** (plus sur "Automatique"). VMnet1 (Hôte uniquement, 192.168.205.0/24) et VMnet8 (NAT, 192.168.124.0/24) restent inchangés.

![VMnet2 ponté avec succès sur I219-LM](preuves/03_vmnet2_ponte_ok.png)

| Réseau | Type | Connexion externe | Sous-réseau |
|---|---|---|---|
| VMnet0 | Ponté | Pontage automatique | — |
| VMnet1 | Hôte uniquement | Connecté | 192.168.205.0 |
| VMnet2 | Ponté | Intel(R) Ethernet Connection (16) I219-LM | — |
| VMnet8 | NAT | Connecté | 192.168.124.0 |

**Rollback identifié (non utilisé) :** en cas de problème, recocher la carte I219-LM dans les Paramètres automatiques de VMnet0 — retour instantané à l'état initial, sans redémarrage.

---

## 3. Vérification de la VM Proxmox

VM : `Proxmox_ve`, VM Settings → onglet Matériel.

**Résumé des périphériques :**

![Résumé des périphériques de la VM Proxmox](preuves/04_vm_proxmox_peripheriques.png)

**Détail Processeurs (moteur de virtualisation) :**

![Case VT-x/EPT cochée sur la VM Proxmox](preuves/05_vm_proxmox_processeurs_vtx.png)

| Paramètre | Valeur trouvée | Cible pré-lab | Statut |
|---|---|---|---|
| Processeurs | 2 processeurs × 2 cœurs = 4 cœurs | 4 vCPU | ✅ |
| Virtualiser Intel VT-x/EPT ou AMD-V/RVI | Cochée | Cochée | ✅ |
| Mémoire | 8 Go | 6-7 Go | ✅ (léger dépassement, sans impact) |
| Disque dur (SCSI) | 64 Go | 64 Go (système) | ✅ |
| Disque dur 2 (SCSI) | 20 Go | 20 Go | ✅ |
| Disque dur 3 (SCSI) | 20 Go | 20 Go | ✅ |
| Carte réseau | NAT | NAT | ✅ |
| Carte réseau 2 | Personnalisé (VMnet2) | VMnet2 (Ponté sur I219-LM) | ✅ |

**Analyse :** la case VT-x/EPT est cochée — condition indispensable puisque Proxmox est lui-même un hyperviseur (KVM) : sans elle, les VM créées plus tard à l'intérieur de Proxmox tourneraient sans accélération matérielle. Les 3 disques distincts sont bien présents (confirmé après vérification — la première vue de la bibliothèque VMware était tronquée et ne les affichait pas tous). Configuration matérielle de la VM conforme au pré-lab sur tous les points.

---

## 4. Script de vérification `check-prelab.ps1`

Script trouvé dans le repo du cours : `D:\M1-Virtualisation-Cloud-Datacenter\scripts\windows\check-prelab.ps1`.

### 4.1 Problèmes rencontrés avant exécution

**a) Politique d'exécution PowerShell.** Premier lancement bloqué :

```
.\check-prelab.ps1 : Impossible de charger le fichier ... car l'exécution de scripts est désactivée sur ce système.
CategoryInfo : Erreur de sécurité : (:) [], PSSecurityException
FullyQualifiedErrorId : UnauthorizedAccess
```

`Get-ExecutionPolicy -List` a montré toutes les portées à `Undefined` → la politique effective retombe sur `Restricted` (défaut client Windows). Correction appliquée (portée utilisateur uniquement, pas besoin d'Admin) :

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

**b) Erreur d'encodage.** Une fois la politique corrigée, le script plantait au parsing :

```
.\check-prelab.ps1:12:171
Le terminateur " est manquant dans la chaîne.
FullyQualifiedErrorId : TerminatorExpectedAtEndOfString
```

Cause : le fichier contient des accents (é, è) et un tiret cadratin (—) encodés en UTF-8 **sans BOM**. Windows PowerShell 5.1 lit un `.ps1` sans BOM en encodage ANSI par défaut, ce qui corrompt le comptage de caractères sur la ligne contenant ces caractères spéciaux. Fix appliqué (réécriture du fichier en UTF-8 avec BOM, contenu logique inchangé) :

```powershell
$content = Get-Content -Raw -Encoding UTF8 .\check-prelab.ps1
Set-Content -Path .\check-prelab.ps1 -Value $content -Encoding UTF8
```

### 4.2 Exécution finale

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
.\check-prelab.ps1
```

**Résultat :**

```
[PASS] RAM: 31.7 GB
[PASS] CPU logiques: 20
[PASS] Virtualisation firmware active
[WARN] vmware.exe non trouvé dans PATH — vérifier installation
```

**Analyse :** 3/3 vérifications critiques passées. Le `[WARN]` sur `vmware.exe` n'est pas bloquant (le script ne compte que les `[FAIL]` pour son code de sortie, `exit 0` ici) — il signale juste que l'exécutable VMware n'est pas ajouté au PATH système, ce qui n'empêche pas VMware Workstation de fonctionner (confirmé par toute la configuration réalisée en sections 1 à 3). Simple confort pour lancer `vmware` en ligne de commande, sans impact sur le pré-lab.

---

## Conclusion

Pré-lab entièrement validé : hôte conforme, réseau virtuel VMnet2 ponté correctement, VM Proxmox conforme au cahier des charges (CPU, RAM, disques, réseau, virtualisation imbriquée active), script de vérification exécuté avec succès.
