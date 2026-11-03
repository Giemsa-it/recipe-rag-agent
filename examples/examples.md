# Tre eksempelspørgsmål

Alle tests er kørt i n8n Chat mod den publicerede **Recipe Agent** (GPT-4o mini) med de to tools `Vector search` og `Graph search`. Screenshots ligger i samme mappe.

| # | Spørgsmål | Tools brugt | Resultat |
|---|---|---|---|
| 1 | Jeg har lyst til noget sødt med frugt | vector_search | ✅ Godt |
| 2 | Jeg vil have noget let og friskt med lime | graph_search + vector_search | ✅ Godt, med svagheder |
| 3 | Hvilke retter kan jeg lave med hvidløg? | graph_search | ❌ Fejlede → rettet → ✅ |

---

## Eksempel 1: Semantisk søgning (vector_search)

**Spørgsmål:** *Jeg har lyst til noget sødt med frugt*

**Tool-kald:** Agenten kaldte kun `Vector search` (se `ex1-vector-answer.png`). Spørgsmålet er en beskrivelse uden konkrete ingredienser, så det er det forventede valg ifølge instruktionerne.

**Hentet information:** De mest lignende opskrifter var desserter med frugt. Ved en manuel test af workflowet med `"something sweet with fruit"` var topresultatet *Apple Pie* (Dessert).

**Agentens svar (opsummeret):**
1. **Apricot & Turkish Delight Mess** – Dessert, Turkish. Mascarpone, græsk yoghurt, marcipan, abrikoser, tyrkisk delikatesse, mandler.
2. **Apple Pie Pops** – Dessert, Dominica. Æbler, sukker, mel, smør, kanel.
3. **Apple & Blackberry Crumble** – Dessert, British. Æbler, brombær, sukker, smør, kanel.

Hver opskrift havde et link til kilden på TheMealDB.

**Vurdering:** Godt resultat. Alle tre forslag er desserter med frugt, og ingen af ordene "sød" eller "frugt" står direkte i opskrifterne. Det viser styrken ved vektorsøgning: den finder betydning, ikke nøgleord. Agenten oversatte selv det danske spørgsmål til engelsk, svarede på dansk og overholdt kravet om kildelinks. Svagheden er, at vi ikke kan se en score-grænse: vektorsøgningen returnerer altid 5 resultater, også hvis ingen er relevante.

---

## Eksempel 2: Hybrid – begge tools kombineret

**Spørgsmål:** *Jeg vil have noget let og friskt med lime*

**Tool-kald:** `2 tool calls` (se `ex2-toolcall-graph.png` og `ex2-toolcall-vector.png`).

| Tool | Input | Formål |
|---|---|---|
| graph_search | `{"ingredients_english": "lime", "cuisine": "", "category": ""}` | Hård betingelse: opskriften skal indeholde lime |
| vector_search | `{"query": "light and fresh with lime"}` | Blød betingelse: rangér efter "let og frisk" |

**Hentet information:**

*graph_search* (opskrifter der faktisk indeholder lime, med mængder):
- Ají de Aguacate Recipe (Colombian Spicy Avocado Sauce) – Miscellaneous, Colombia – bl.a. avocado (2), lime (Juice of 2), cilantro (4 tablespoons)
- Acaraje black-eyed pea fritters with shrimp filling – Seafood, Brazil – bl.a. lime (Juice of 1), raw tiger prawns (150g)
- …

*vector_search* (top 3 af 5, cosine score):
| Opskrift | Score |
|---|---|
| Ají de Aguacate Recipe (Colombian Spicy Avocado Sauce) | 0.769 |
| Achiote Oil (Aceite Achiotado) Recipe | 0.768 |
| Acaraje black-eyed pea fritters with shrimp filling | … |

**Agentens svar (opsummeret):**
1. **Ají de Aguacate** – Diverse, Colombia. Avocado, saft af 2 lime, løg, scallions, habanero, æg, koriander. Kort fremgangsmåde: blend det hele og justér med limesaft.
2. **Acaraje** – Skaldyr, Brasilien.

(se `ex2-hybrid-answer.png`)

**Vurdering:** Agenten fulgte hybrid-reglen i instruktionerne: den kaldte begge tools og valgte *Ají de Aguacate* først, fordi den ligger øverst i begge resultater. Det er netop kombinationen af graf (har den lime?) og vektor (føles den let og frisk?), som projektet handler om.

Der er dog to tydelige svagheder:
- **Vektorscorerne skiller dårligt.** *Achiote Oil* fik 0.768 – næsten samme score som vinderen (0.769) – selvom den hverken indeholder lime eller er "let og frisk". Med kun 40 opskrifter og én chunk pr. opskrift ligger scorerne meget tæt, så vektorsøgning alene ville have givet et dårligt svar. Grafen var nødvendig for at fjerne støjen.
- **"Let" blev tolket løst.** *Acaraje* er friturestegte fritter, men kom med som forslag 2, fordi den indeholder lime og optræder i begge resultater. Agenten vægter "findes i begge" højere end selve beskrivelsen.

---

## Eksempel 3: Begrænsning/fejl – sprog i tool-input (graph_search)

**Spørgsmål:** *Hvilke retter kan jeg lave med hvidløg?*

### Første forsøg – fejl

**Tool-kald** (se `ex3-fail-toolcall.png`):
```json
{ "ingredients": "hvidløg", "cuisine": "", "category": "" }
```

**Hentet information:**
```json
{ "results": [] }
```

**Agentens svar:** *"Det ser ud til, at databasen ikke indeholder nogen opskrifter med hvidløg …"* (se `ex3-fail-answer.png`)

**Hvorfor:** Alle ingredienser er gemt på engelsk (`garlic`). Agenten sendte det danske ord direkte videre, så Cypher-forespørgslen fandt intet. Svaret er forkert – databasen har flere opskrifter med hvidløg. Agenten fulgte heller ikke reglen *"If one tool returns nothing, try the other once"*.

**Forsøg på rettelse 1 (prompt):** Vi skrev en eksplicit regel i instruktionerne (`ALL tool inputs MUST be in English … "hvidløg" -> "garlic" …`) og i feltbeskrivelsen. Efter publicering og en ny chat sendte agenten **stadig** `"hvidløg"`. GPT-4o mini ignorerede altså reglen i fri tekst.

**Rettelse 2 (schema):** Vi omdøbte feltet i Graph search-workflowet fra `ingredients` til `ingredients_english` (se `../screenshots/graph-search-trigger-field.png`) og opdaterede tool-definitionen i agenten.

### Andet forsøg – virker

**Tool-kald** (se `ex3-fixed-toolcall.png`):
```json
{ "ingredients_english": "garlic", "cuisine": "", "category": "" }
```

**Hentet information** (uddrag af output):
```json
{ "recipe": "Ajo blanco", "category": "Starter", "cuisine": "Spanish",
  "ingredients": ["white bread (150g)", "almonds (200g)", "extra virgin olive oil (50 ml)",
                  "garlic clove (1)", "red wine vinegar (1 ½ tbsp)"],
  "source": "https://www.themealdb.com/meal/53169" },
{ "recipe": "Acaraje black-eyed pea fritters with shrimp filling", "category": "Seafood", "cuisine": "Brazil",
  "ingredients": ["black eyed peas (800g)", "vegetable oil (1 tablespoon)", "garlic (2 cloves)", "salt (1 tsp)", "..."] },
...
```
Bemærk at *Ajo blanco* blev fundet, selvom ingrediensen hedder `garlic clove` – graph_search matcher delvise ord (`CONTAINS`).

**Agentens svar (opsummeret):** (se `ex3-fixed-answer.png`)
1. **Ajo blanco** – Forret, Spansk. 150 g hvidt brød, 200 g mandler, 50 ml olivenolie, 1 fed hvidløg, 1½ spsk rødvinseddike.
2. **Acaraje** – Skaldyr, Brasiliansk. 800 g sorte øjne bønner, 2 fed hvidløg, 150 g rå tigerrejer.
3. **Algerisk Bouzgene Berber brød med ristet peppersauce** – Tilbehør, Algerisk.

**Vurdering:** Dette er projektets vigtigste læring om agenter: **en lille model følger feltnavne i et schema mere pålideligt end regler i en prompt.** Når kravet stod i selve navnet (`ingredients_english`), oversatte modellen korrekt.

Eksemplet afslører også en begrænsning i datamodellen: Acaraje bruger hvidløg to gange i kilden (1 fed i dejen og 2 fed i fyldet), og tool-outputtet indeholder kun `garlic (2 cloves)` – agenten viser derfor kun "2 fed hvidløg". Relationen `HAS_INGREDIENT` oprettes med `MERGE`, så kun den sidste mængde bliver gemt (se `../data/data-model.md`, *Kendte begrænsninger i data*).

Rettelsen dækker kun ingredienser. Det samme problem kan stadig opstå, hvis agenten f.eks. sender "Spanien" som køkken – her er vi afhængige af, at modellen følger listen i beskrivelsen.
