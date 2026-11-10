# Contribuer à RDK G2 Basic

RDK BASIC est un interpréteur Integer BASIC **écrit de zéro en assembleur 6502** pour l'Apple-1 : même syntaxe, mêmes jetons, même format de cassette que l'original, avec ses bogues connus corrigés, et des extensions pour la carte couleur GEN2 d'Uncle Bernie. Il est intégré au [Retro Dev Kit Apple 1](https://github.com/Old-Wirehead/rdk-apple1) sous forme d'une image de 7 933 octets chargée en `$E000`.

Ce projet est développé par **Wirehead** (Old-Wirehead) avec l'aide de plusieurs IA. Ce fichier explique comment y contribuer, humain ou IA.

## Rôles

| Qui | Rôle |
|---|---|
| Wirehead | Chef de projet : décide des priorités, des releases et tags, de la licence, du passage en public, des suppressions importantes et de tout ajout de matériel sous droits. |
| Claude | Développeur : branches `claude/…`, fusionne ses propres demandes, relit celles de Rusty Jr après fusion. |
| Rusty Jr | **Développeur en chef** (10 novembre 2026) : branches `rusty/…`, fusionne ses propres demandes et celles de Rusty Sr, relit celles de Claude après fusion, coordonne le travail. |
| Rusty Sr | **Consultant** (10 novembre 2026) : lit les discussions, les commits et les demandes de fusion, et donne son avis. **Il ne fusionne jamais**, ne crée ni tag ni release ; il peut proposer du code sur une branche `rusty-sr/…`, relu et fusionné par Rusty Jr, ou refusé. |

Le dernier mot appartient à Wirehead, et à Rusty Jr pour les choix de développement courant.

## Licence

**GPL-3.0-only** : voir [LICENSE](LICENSE) et [NOTICE](NOTICE). Toute contribution est acceptée sous cette même licence.

Le `NOTICE` crédite Uncle Bernie pour l'ACI Gen2 et la carte GEN2, et porte la **clause de non-responsabilité**. Ne la retirez pas d'une redistribution : c'est la seule chose qu'il ait demandée.

## Écriture en salle blanche — la règle qui compte

RDK BASIC ne contient **aucun code** de l'Integer BASIC d'Apple. Il a été écrit à partir de la spécification de comportement : les manuels publiés, l'observation en boîte noire de programmes chargés en mémoire, et notre propre description du format des jetons.

Concrètement, pour toute contribution :

- **ne jamais** désassembler, lire ni recopier l'interpréteur d'origine (`$E000-$EFFF`) ;
- **ne jamais** coller dans ce dépôt une image, un listing ou un désassemblage de l'original, même pour un test ;
- la comparaison avec l'original se fait **uniquement sur la sortie** des sessions de test, jamais sur le code.

## Ce qui ne doit jamais être commité

- une image de l'Integer BASIC d'Apple, son désassemblage, ou une cassette qui le contient ;
- une ROM, un firmware ou un fichier protégé par le droit d'auteur (jeux commerciaux, cassettes du commerce, livres, PDF de tiers) ;
- les documents non publiés d'Uncle Bernie sur la carte GEN2 ;
- un jeton, un mot de passe ou une clé.

## Comment travailler

- **Une issue, un responsable** : ouvrez une issue ou prenez-en une, et annoncez-vous en commentaire avant de commencer.
- **Une branche par sujet**, partie du dernier `main`, nommée `<ia>/<sujet>` ou `<pseudo>/<sujet>`.
- **Une demande de fusion vers `main`**, avec un titre clair et une description : ce qui change, pourquoi, comment c'est testé, et le lien vers l'issue (`Corrige #12`).
- L'auteur fusionne lui-même une fois les vérifications passées ; un autre contributeur relit après la fusion et ouvre une issue si quelque chose ne va pas.

## Vérifications avant de fusionner

1. Construire l'image et **la committer** si elle change :

```
python3 src/build.py --asm /chemin/vers/apple1-emu bin/rdk-g2basic.bin
```

2. Lancer les tests de régression, qui doivent tous passer :

```
tests/run-tests.sh
```

3. Pour tout nouveau mot-clé ou changement visible : **une session de test** dans `tests/sessions/` et sa sortie attendue dans `tests/expected/`, plus la mise à jour du [manuel](docs/manual.md).

Le script accepte aussi `--real` pour comparer avec l'Integer BASIC d'origine, à condition de fournir `ORIG_ROM=/chemin/vers/integer_basic.bin` : cette image n'est **jamais** dans le dépôt.

## Identité et signature

Quand plusieurs personnes publient avec le même compte GitHub, chacune **signe** ses issues, commentaires et demandes de fusion à la fin : « — Claude IA », « — Rusty Jr », « — Rusty Sr », etc. Les messages de commit commencent par le nom de l'auteur entre crochets : `[Claude] Corrige…`, `[Rusty Jr] Ajoute…`, `[Rusty Sr] Propose…`.

Les commentaires de Rusty Sr commencent par le nom de l'IA visée (« Rusty Jr — », « Claude — ») et précisent que c'est un avis, pas une décision. Dans les discussions, on écrit le nom de l'IA **sans `@`** : sur GitHub, `@nom` notifie un vrai compte étranger au projet.
