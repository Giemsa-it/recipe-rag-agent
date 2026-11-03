# Recipe Agent – RAG med vektor- og grafsøgning

To-ugers projekt (RAG Project), AI-Agenter E2026.

## Case og agentens rolle

**Domæne:** opskrifter fra [TheMealDB](https://www.themealdb.com) (40 opskrifter, alle der starter med "a").

Opskrifter passer godt til opgaven, fordi de har begge typer information:

| | Eksempel | Database |
|---|---|---|
| **Struktur** man vil filtrere på | ingredienser, kategori, køkken | Graf (Neo4j) |
| **Beskrivende tekst** hvor betydning er vigtigere end ord | "noget let og friskt", "sødt med frugt" | Vektor (Neo4j vektorindeks) |

**Agentens rolle:** *Recipe Agent* er en venlig, praktisk kokkeassistent. Brugeren skriver på dansk, og agenten foreslår 1-3 opskrifter med kategori, køkken, nøgleingredienser (med mængder) og et link til kilden. Agenten har ingen egen opskriftsviden – alt kommer fra de to tools.

## Arkitektur

```
                  TheMealDB API
                        │
            ┌───────────▼────────────┐
            │  n8n: Ingestion        │
            │  hent → normalisér ────┼──► Neo4j graf
            │        → embed (Ollama)┼──► Neo4j :Chunk + vektorindeks
            └────────────────────────┘
                                          ┌────────────── Neo4j ──────────────┐
                                          │ (:Chunk)-[:PART_OF]->(:Recipe)     │
Bruger (n8n Chat)                         │ (:Recipe)-[:HAS_INGREDIENT]->(...) │
      │                                   │ (:Recipe)-[:IN_CATEGORY]->(...)    │
      ▼                                   │ (:Recipe)-[:FROM_CUISINE]->(...)   │
┌──────────────┐  vector_search  ┌────────┴──────┐                            │
│ Recipe Agent │────────────────►│ Vector search │── embed → queryNodes ─────►│
│ GPT-4o mini  │                 └───────────────┘                            │
│ (n8n Agents) │  graph_search   ┌───────────────┐                            │
│              │────────────────►│ Graph search  │── parametriseret Cypher ──►│
└──────────────┘                 └───────────────┘                            │
                                          └────────────────────────────────────┘
```

**Sådan hænger delene sammen:**

1. **Ingestion** (n8n-workflow) henter opskrifter fra TheMealDB, normaliserer dem og skriver dem til Neo4j to gange: som graf (`Recipe`, `Ingredient`, `Category`, `Cuisine`, `Tag`) og som en `Chunk` med tekst og 768-dimensionel embedding fra Ollama `nomic-embed-text`. Hver `Chunk` er koblet til sin `Recipe` med `PART_OF`, så et vektor-hit altid kan følges videre ind i grafen.
2. **Vector search** (sub-workflow) embedder agentens spørgsmål og finder de 5 mest lignende chunks via vektorindekset `chunk_embeddings`.
3. **Graph search** (sub-workflow) kører en fast, parametriseret Cypher-forespørgsel med filtre på ingredienser, køkken og kategori. Agenten skriver aldrig selv Cypher.
4. **Recipe Agent** (n8n Agents builder) vælger tool ud fra spørgsmålet: graf ved konkrete ingredienser/køkken/kategori, vektor ved beskrivelser, og begge ved blandede spørgsmål (se eksempel 2).

## Hvor finder man hvad

| Krav | Fil(er) |
|---|---|
| **README** | `README.md` (denne fil) |
| **Workflow-screenshots** | `screenshots/ingestion.png` (data ingestion)<br>`screenshots/vector-search.png` (vektor-retrieval)<br>`screenshots/graph-search.png` (graf-retrieval) |
| **Workflow-JSON** | `workflows/Ingestion.json`<br>`workflows/Vector search.json`<br>`workflows/Graph search.json` |
| **Agentkonfiguration og prompts** | `agent/model.txt` – model og opsætning<br>`agent/instructions.txt` – agentens instruktioner, rolle og guardrails<br>`agent/tool-descriptions.txt` – beskrivelse, input og brug af hvert tool<br>`agent/dev-prompts.txt` – prompts og iterationer under udvikling |
| **Screenshots af agenten** | `screenshots/agent-model-instructions.png` – model og instruktioner<br>`screenshots/agent-capabilities.png` – tool-forbindelser<br>`screenshots/agent-tool-vector-search.png`, `screenshots/agent-tool-vector-query-input.png` – tool-opsætning |
| **Tre eksempler** | `examples/examples.md` + screenshots i `examples/` |
| **Data og setup** | `data/data-model.md` – datakilde, nodetyper, relationer, properties, normalisering, chunking, begrænsninger<br>`data/sample.json` – én opskrift rå og normaliseret<br>`data/setup.cypher` – constraints og vektorindeks |
| **Neo4j-screenshots** | `screenshots/neo4j-indexes.png`, `screenshots/neo4j-graph.png`, `screenshots/neo4j-cuisines.png`, `screenshots/neo4j-duplicates-before-fix.png`, `screenshots/neo4j-duplicates-after-fix.png` |

## Agenten

- **Bygget med:** n8n Agents builder (self-hosted n8n i Docker)
- **Model:** OpenAI GPT-4o mini
- **Tools:** `Vector search` og `Graph search` (n8n-workflows med *When Executed by Another Workflow*-trigger, tilføjet under *Capabilities → Workflows*)
- **Kanal:** n8n Chat
- **Web search:** slået fra, så agenten kun svarer ud fra databasen
- **Guardrails** (fra `agent/instructions.txt`):
  - Brug kun fakta fra tool-resultaterne; opfind aldrig opskrifter, mængder eller links
  - Sig tydeligt, hvis databasen ikke har et match, i stedet for at bruge generel viden
  - Ingen garantier om allergi eller sundhed
  - Hold dig til madlavning
  - Alle tool-input skal være på engelsk

| Tool | Input | Brug når | Returnerer |
|---|---|---|---|
| `vector_search` | `query` (engelsk beskrivelse) | beskrivelser, stemning, tekstur | 5 opskrifter med tekst, kilde og score |
| `graph_search` | `ingredients_english`, `cuisine`, `category` | konkrete ingredienser, køkken, kategori | op til 10 opskrifter med alle ingredienser og mængder samt kilde |

## Tre eksempler

Se `examples/examples.md`. Kort:

1. **"Jeg har lyst til noget sødt med frugt"** → vector_search → tre frugtdesserter. ✅
2. **"Jeg vil have noget let og friskt med lime"** → graph_search + vector_search → agenten vælger den opskrift, der ligger øverst i begge. ✅, men vektorscorerne skiller dårligt (0.769 vs. 0.768 for en irrelevant opskrift).
3. **"Hvilke retter kan jeg lave med hvidløg?"** → **fejl:** agenten sendte det danske ord `hvidløg` til graph_search og fik 0 resultater. En skarpere prompt hjalp ikke. Løst ved at omdøbe feltet til `ingredients_english`.

## Genskab løsningen

Forudsætninger: Docker, Neo4j (testet med Neo4j Desktop 2026.10.0), Ollama og en OpenAI API-nøgle.

1. **Neo4j:** opret en lokal instans og kør kommandoerne i `data/setup.cypher` (6 constraints + vektorindekset `chunk_embeddings`, 768 dimensioner, cosine).
2. **Ollama:** `ollama pull nomic-embed-text`
3. **n8n:** kør n8n i Docker i en version med Agents builder:
   ```bash
   docker run -d --name n8n -p 5678:5678 -v n8n_data:/home/node/.n8n docker.n8n.io/n8nio/n8n:latest
   ```
   Fra n8n i Docker nås Neo4j og Ollama på `host.docker.internal` (port 7474 og 11434).
4. **Importér workflows:** importér de tre JSON-filer fra `workflows/`. Opret en *Basic Auth*-credential med `neo4j` og dit password, og vælg den på alle Neo4j-noder.
5. **Kør Ingestion.** Tjek i Neo4j:
   ```cypher
   MATCH (r:Recipe) WITH count(r) AS opskrifter MATCH (c:Chunk) RETURN opskrifter, count(c) AS chunks
   ```
   Forventet: 40 og 40.
6. **Publicér** Vector search og Graph search.
7. **Opret agenten** under *Personal → Agents → Create Agent*: vælg GPT-4o mini, indsæt `agent/instructions.txt`, tilføj de to workflows under *Capabilities* med beskrivelserne fra `agent/tool-descriptions.txt`, sæt alle input til *Defined by agent*, og publicér.

## Designvalg

- **Én Neo4j-database til både graf og vektor**, så et vektor-hit kan følges direkte ind i grafen via `PART_OF`.
- **Én chunk pr. opskrift:** opskrifterne er korte, og en hel opskrift er en naturlig semantisk enhed.
- **Faste, parametriserede Cypher-queries** i stedet for at lade agenten skrive Cypher. Det er mere sikkert og forudsigeligt.
- **`MERGE` + unikke constraints + Batching**, så importen kan køres flere gange uden dubletter.
- **HTTP-kald til Neo4j's Query API** (`/db/neo4j/query/v2`) fra n8n, så samme opsætning bruges til import og søgning.

## Problemer undervejs og hvordan de blev løst

| Problem | Løsning |
|---|---|
| `strArea` var `null` for mange opskrifter, så Neo4j kunne ikke `MERGE` | Fallback til `strCountry`, derefter `Unknown` |
| Deadlock når n8n skrev 40 opskrifter parallelt | Batching med 1 item ad gangen på Neo4j-noderne |
| Dublet-noder (f.eks. tre `Side`-kategorier) gav samme opskrift flere gange | Unikke constraints på `Category`, `Cuisine`, `Tag` og genimport (se før/efter-screenshots) |
| Agents builder manglede i n8n 2.36.9 (404 på *Settings → Agents*) | Opdateret n8n-image til `latest` med samme volume |
| Agenten sendte danske ord til graph_search | Feltet omdøbt til `ingredients_english` (eksempel 3) |

## Begrænsninger

- Kun 40 opskrifter, så mange spørgsmål har intet godt svar, og vektorscorerne ligger tæt.
- Køkkennavne er blandede (`Spanish` vs. `Colombia`), fordi de kommer fra to forskellige kildefelter.
- Gentagne ingredienser i én opskrift gemmer kun den sidste mængde.
- Oversættelse til engelsk afhænger af modellen. Feltnavnet løste det for ingredienser, men ikke nødvendigvis for køkken.
- Vektorsøgningen har ingen minimumsscore, så den returnerer altid 5 resultater.

## Ekstra

- **Kildehenvisninger:** agenten viser altid et link til hver opskrift, den bruger.
- **Chat-interface:** n8n's indbyggede chat (n8n Chat-kanalen).
- **Hybrid søgning:** delvist – agenten kombinerer graf og vektor i samme svar (eksempel 2), men som to separate tool-kald og ikke én samlet query.
