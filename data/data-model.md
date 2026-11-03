# Data og datamodel

## Datakilde

**TheMealDB** – gratis, åbent opskrifts-API: https://www.themealdb.com

Data hentes af n8n-workflowet *Ingestion* via:

```
GET https://www.themealdb.com/api/json/v1/1/search.php?f=a
```

Endpointet returnerer alle opskrifter, hvis navn starter med det angivne bogstav (her `a`, 40 opskrifter). Flere opskrifter kan tilføjes ved at køre workflowet igen med et andet bogstav. Importen er idempotent (`MERGE`), så genkørsler giver ingen dubletter.

Et lille udsnit af de normaliserede data ligger i `sample.json`.

## Grafmodel

```
(:Recipe)-[:HAS_INGREDIENT {measure}]->(:Ingredient)
(:Recipe)-[:IN_CATEGORY]->(:Category)
(:Recipe)-[:FROM_CUISINE]->(:Cuisine)
(:Recipe)-[:HAS_TAG]->(:Tag)
(:Chunk)-[:PART_OF]->(:Recipe)
```

### Nodetyper

| Label | Properties | Beskrivelse |
|---|---|---|
| `Recipe` | `id` (unik), `name`, `source` | En opskrift. `id` er TheMealDB's `idMeal`, `source` er link til opskriften |
| `Ingredient` | `name` (unik) | En ingrediens, f.eks. `garlic` |
| `Category` | `name` (unik) | Rettens kategori, f.eks. `Seafood`, `Dessert` |
| `Cuisine` | `name` (unik) | Køkken/oprindelse, f.eks. `Italian`, `Thai` |
| `Tag` | `name` (unik) | Fritekst-tags fra kilden, f.eks. `baking`, `fruity` |
| `Chunk` | `id` (unik), `text`, `source`, `embedding` | Tekst til semantisk søgning, med 768-dimensionel vektor |

### Relationstyper

| Relation | Fra → Til | Properties |
|---|---|---|
| `HAS_INGREDIENT` | Recipe → Ingredient | `measure` (mængde, f.eks. `800g`) |
| `IN_CATEGORY` | Recipe → Category | – |
| `FROM_CUISINE` | Recipe → Cuisine | – |
| `HAS_TAG` | Recipe → Tag | – |
| `PART_OF` | Chunk → Recipe | – |

`PART_OF` binder vektordelen sammen med grafen: et vektor-hit på en `Chunk` kan altid følges videre til opskriften og dens ingredienser, kategori og køkken.

## Normalisering

Udført i n8n-noden *Normaliser* (Code):

- TheMealDB gemmer ingredienser i 20 separate felter (`strIngredient1..20`, `strMeasure1..20`). De samles til ét array, og tomme felter fjernes.
- Ingrediens- og tagnavne trimmes og gemmes med små bogstaver, så `Garlic` og `garlic` bliver samme node.
- Tags splittes fra en kommasepareret streng.
- Køkken hentes fra `strArea`, og hvis det mangler, fra `strCountry` (TheMealDB har for mange opskrifter kun udfyldt `strCountry`, f.eks. `Brazil`).
- Manglende kategori, køkken eller navn erstattes med `Unknown`, fordi Neo4j ikke kan `MERGE` på `null`.

### Kendte begrænsninger i data

- **Blandede køkkennavne:** `strArea` bruger adjektiver (`Spanish`, `Turkish`), mens `strCountry` bruger landenavne (`Colombia`, `Venezuela`). De to er ikke slået sammen, så en søgning på `Spain` finder ikke `Spanish`.
- **Gentagne ingredienser:** Samme ingrediens kan optræde flere gange i én opskrift (f.eks. hvidløg i både fyld og dej). Relationen `HAS_INGREDIENT` oprettes med `MERGE`, så kun den sidst angivne mængde gemmes.
- **Samtidige skrivninger:** Uden unikke constraints på `Category`, `Cuisine` og `Tag` kunne parallelle `MERGE`-kald oprette dubletter (og deadlocks). Løst med constraints i `setup.cypher` og Batching (1 item ad gangen) på Neo4j-noderne i n8n.
- **Lille datasæt:** Kun opskrifter, der starter med `a` (40 stk.), er importeret.

## Chunking

Én chunk pr. opskrift (`Chunk.id = <recipe id>-0`). Opskrifterne er korte, og en hel opskrift er en naturlig semantisk enhed, så yderligere opdeling ville splitte ingredienser fra fremgangsmåde uden gevinst. Chunk-teksten har formen:

```
<navn>. <kategori> dish from <køkken> cuisine. Ingredients: <ingredienser>. Instructions: <fremgangsmåde>
```

Navn, kategori og ingredienser indgår i teksten, så de også påvirker den semantiske søgning.

## Embeddings

- Model: `nomic-embed-text` via Ollama (lokalt), 768 dimensioner
- Lighedsmål: cosine
- Vektorindeks: `chunk_embeddings` på `Chunk.embedding`

## Genskab databasen

1. Opret en lokal Neo4j-instans (testet med Neo4j 2026.10.0 i Neo4j Desktop).
2. Kør `setup.cypher` i Neo4j Query.
3. Kør `ollama pull nomic-embed-text`.
4. Importér `workflows/ingestion.json` i n8n, sæt Basic Auth-credential (`neo4j` + password) på noderne *Gem graf* og *Gem chunk*, og kør workflowet.
5. Tjek: `MATCH (c:Chunk) RETURN count(c)` skal give 40.

Hvis n8n kører i Docker, bruges `host.docker.internal` i stedet for `localhost` til Neo4j (port 7474) og Ollama (port 11434).
