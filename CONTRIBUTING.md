# Contribuer à RDK G2 Basic Apple 1

Ce dépôt (le BASIC intégré au Retro Dev Kit Apple 1) est développé par Wirehead (Old-Wirehead) avec plusieurs IA. **Rusty** est le développeur en chef : il relit et fusionne tout ce qui arrive sur `main`. Chaque IA lit ce fichier en premier quand elle reprend le travail.

## Rôles

| Qui | Rôle |
|---|---|
| Wirehead | Chef de projet : décide des priorités, valide les versions, publie (tags, releases). |
| Rusty | Développeur en chef : seul à pousser sur `main`, relit et fusionne les demandes de fusion. |
| Autres IA (Claude, etc.) | Proposent sur leur branche, via une demande de fusion. Jamais de poussée directe sur `main`. |

Aucune IA ne crée de tag ni de release : c'est réservé à Wirehead.

## Identité et signature

Tant que tout le monde publie avec le compte Old-Wirehead, chaque IA **signe** ses issues, commentaires et demandes de fusion à la fin : « — Claude IA », « — Rusty », etc. Les messages de commit commencent par le nom de l'IA entre crochets : `[Claude] Corrige …`.

## Branches

- `main` : version courante, alimentée uniquement par Rusty.
- `<ia>/<sujet>` : une branche par sujet, préfixée par le nom de l'IA en minuscules, par exemple `claude/del-plages` ou `claude/mot-cle-key`.
- Une branche par sujet, partie du dernier `main`. Ne pas réécrire l'historique d'une branche déjà relue.

## Demandes de fusion (pull requests)

1. Ouvrir la demande vers `main` depuis sa branche, avec un titre clair et une description : ce qui change, pourquoi, comment c'est testé.
2. Lier l'issue concernée (`Corrige #3`).
3. Les tests doivent passer : `tests/run-tests.sh` (toutes les sessions identiques à la sortie de l'Integer BASIC original). Construire avec `python3 src/build.py --asm /chemin/vers/apple1-emu bin/rdk-g2basic.bin`.
4. Rusty relit, demande des corrections si besoin, puis fusionne. Il peut aussi reprendre lui-même une partie du travail en le signalant.

## Ce que chaque IA peut modifier

- **Code, tests et documentation** : uniquement par demande de fusion, dans le périmètre de l'issue traitée.
- **Écriture en salle blanche** : G2 Basic est réécrit sans copier l'Integer BASIC d'Apple. Ne jamais coller ni désassembler du code de l'original dans ce dépôt ; la comparaison se fait seulement sur la sortie des sessions de test.
- **Nouveaux mots clés** : toute extension par rapport à l'Integer BASIC (comme `KEY`, `LOMEM=`, `HIMEM=`) s'accompagne d'une session de test et d'une mise à jour de la documentation.
- Après une modification, Rusty intègre la nouvelle image dans rdk-apple1.

## Ce qui ne doit jamais être commité

- Les ROM et l'Integer BASIC original, ni aucun fichier protégé par le droit d'auteur (jeux commerciaux, cassettes audio du commerce, livres, PDF).
- La documentation préliminaire de la carte graphique d'Uncle Bernie, tant qu'il n'en a pas validé la version propre.
- L'image binaire ou le désassemblage de l'Integer BASIC original, même pour les tests.
- Aucun jeton, mot de passe ni clé.

## Étiquettes

| Étiquette | Sens |
|---|---|
| `bug` | Défaut constaté. |
| `amélioration` | Demande de fonctionnalité. |
| `doc` | Documentation. |
| `à-faire-par-claude`, `à-faire-par-rusty`, … | Qui doit s'en occuper. |
| `en-revue` | Demande de fusion en attente de relecture par Rusty. |
| `bloqué` | En attente d'une décision de Wirehead ou d'une information extérieure. |

## Discussions

- Catégorie **« Coordination IA »** : répartition du travail, questions entre IA, comptes rendus de session. Mentionner l'IA visée avec `@nom` dans le texte, puisque toutes publient avec le même compte.
- Les défauts et les demandes précises vont dans les **issues**, pas dans les discussions.
- Les décisions de Wirehead priment toujours.

## Langue

Issues, discussions et commentaires en français. Le code et la documentation anglaise restent en anglais. En français, « Apple-1 » est masculin.

## Licence

G2 Basic est sous licence MIT. Toute contribution est acceptée sous la licence MIT.
