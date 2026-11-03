// Neo4j setup for the recipe RAG project
// Run each statement separately in Neo4j Query (database: neo4j)
// before running the n8n Ingestion workflow.

// Uniqueness constraints (also create range indexes, and make MERGE fast and duplicate-safe)
CREATE CONSTRAINT recipe_id IF NOT EXISTS FOR (r:Recipe) REQUIRE r.id IS UNIQUE;

CREATE CONSTRAINT ingredient_name IF NOT EXISTS FOR (i:Ingredient) REQUIRE i.name IS UNIQUE;

CREATE CONSTRAINT chunk_id IF NOT EXISTS FOR (c:Chunk) REQUIRE c.id IS UNIQUE;

CREATE CONSTRAINT category_name IF NOT EXISTS FOR (c:Category) REQUIRE c.name IS UNIQUE;

CREATE CONSTRAINT cuisine_name IF NOT EXISTS FOR (c:Cuisine) REQUIRE c.name IS UNIQUE;

CREATE CONSTRAINT tag_name IF NOT EXISTS FOR (t:Tag) REQUIRE t.name IS UNIQUE;

// Vector index for semantic search
// 768 dimensions = Ollama nomic-embed-text
CREATE VECTOR INDEX chunk_embeddings IF NOT EXISTS
FOR (c:Chunk) ON c.embedding
OPTIONS {indexConfig: {
  `vector.dimensions`: 768,
  `vector.similarity_function`: 'cosine'
}};

// Verify
SHOW INDEXES;

// Optional: wipe all data before a full re-import (keeps constraints and indexes)
// MATCH (n) DETACH DELETE n;

// Sanity checks after ingestion
// MATCH (c:Chunk) RETURN count(c) AS chunks, size(head(collect(c.embedding))) AS dimensions;
// MATCH (r:Recipe)-[rel]->(n) RETURN r, rel, n LIMIT 50;
