# Tune Manager

<img src="TuneManager-logo.png" width="96" align="right" alt="Tune Manager"/>

Logiciel Windows qui installe, configure et gère la chaîne audio **gratuite** d'ArtIsWar
(ArtTuneDB pour Equalizer APO) pour MW4 / Warzone / Black Ops, sans étapes manuelles.

Le son est identique à l'installation officielle : mêmes installateurs, même bibliothèque ArtTuneDB,
même moteur ATK (VST/JSFX), mêmes HRIR, mêmes réglages.

## Installer

1. Télécharger **`Tune Manager Setup.exe`** dans la dernière [Release](../../releases/latest).
2. Le lancer (droits administrateur demandés). SmartScreen peut avertir, car l'exe n'est pas signé :
   *Informations complémentaires › Exécuter quand même*.
3. Au premier lancement, Tune Manager propose d'installer la chaîne audio en un clic.

Les mises à jour suivantes sont proposées automatiquement au lancement de Tune Manager.
Le dépôt étant privé, il faut un jeton GitHub en lecture seule (*Paramètres › Mises à jour de Tune Manager*),
ou GitHub CLI connecté (`gh auth login`).

## Ce que fait le logiciel

- **Profils** : casque + jeu + style de preset + niveau de ta propre arme + HRIR + boost, activés en un clic
  (fenêtre ou icône de la zone de notification). Boost réglable en direct.
- **EQ automatique** : cherche ton casque sur squig.link (GadgetryTech) et crée l'EQ sur la target ArtIsWar
  de la version du jeu (même algorithme que l'AutoEQ du site).
- **Configuration** :
  - *Installation* : installation et désinstallation silencieuses (VB-CABLE, Voicemeeter, ReaPlugs,
    Equalizer APO, HeSuVi, bibliothèque, HRIR, renommage et icônes des câbles, Device Selector,
    format 16 canaux, nettoyage).
  - *Windows* : diagnostic complet + intégrité du moteur ATK.
  - *Voicemeeter* : routage et options réglés tout seuls, fenêtre cachée.
- **Réglages en jeu** : rappel des réglages audio obligatoires du jeu (d'après `COD_SETTINGS.md`).
- **Paramètres** : mises à jour de la bibliothèque ArtTuneDB et de Tune Manager, démarrage avec Windows.

## Développement

| Élément | Rôle |
|---|---|
| `TuneManager.ps1` | Le logiciel (interface WPF + moteur d'installation) |
| `Setup/Launcher.cs` | `TuneManager.exe`, lanceur avec icône |
| `Setup/Setup.cs` | `Tune Manager Setup.exe`, installeur graphique |
| `Setup/Build.ps1` | Compile les deux exe avec le compilateur C# de Windows |
| `Setup/Logo.ps1` | Génère le logo et l'icône |
| `Setup/Publish.ps1` | Publie une version : `Publish.ps1 2.1.1 "ce qui change"` |
| `Setup/version.txt`, `Setup/repo.txt` | Version et dépôt GitHub utilisés pour les mises à jour |

```powershell
powershell -ExecutionPolicy Bypass -File TuneManager.ps1 -Check      # diagnostic (lecture seule)
```

## Crédits

ArtTuneDB et son installeur : ArtIsWar (GPL-3.0, bibliothèque CC BY-NC-SA 4.0) — https://github.com/ArtIsWar/ArtTuneDB.
Equalizer APO, VB-CABLE / Voicemeeter (VB-Audio), ReaPlugs (Cockos), HeSuVi, squig.link (GadgetryTech).
Les composants tiers sont téléchargés depuis leurs sources officielles au moment de l'installation.
