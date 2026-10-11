# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # RAG.* (needs the RAGPipeline license feature): a
    # retrieval pipeline with hybrid vector + BM25 search.
    class RAG
      def initialize(client)
        @client = client
      end

      def create(name, dimensions, strategy: nil, chunk_size: nil, chunk_overlap: nil)
        args = ["RAG.CREATE", name, dimensions]
        args.push("STRATEGY", strategy) if strategy
        args.push("CHUNK_SIZE", chunk_size) if chunk_size
        args.push("CHUNK_OVERLAP", chunk_overlap) if chunk_overlap
        @client.invoke(*args) { |r| r == "OK" }
      end

      # +meta+: a Hash of metadata key/values to attach to +doc_id+.
      # +vectors+: an Array of embedding vectors (each an Array of Floats),
      # one per chunk the server will split +text+ into.
      def ingest(pipeline, doc_id, text, meta: nil, vectors: nil)
        args = ["RAG.INGEST", pipeline, doc_id, text]
        args.push("META", *meta.flat_map { |k, v| [k, v] }) if meta && !meta.empty?
        args.push("VECTORS", *vectors.map { |v| Wire.csv_vector(v) }) if vectors && !vectors.empty?
        @client.invoke(*args)
      end

      def search(pipeline, query_text, k: nil, alpha: nil, vector: nil, filter: nil)
        args = ["RAG.SEARCH", pipeline, query_text]
        args.push("K", k) if k
        args.push("ALPHA", Wire.finite(alpha)) if alpha
        args.push("VECTOR", Wire.csv_vector(vector)) if vector
        args.push("FILTER", *filter.flat_map { |fk, fv| [fk, fv] }) if filter && !filter.empty?
        @client.invoke(*args) { |r| r.map { |row| search_row(row) } }
      end

      def stats(pipeline)
        @client.invoke("RAG.STATS", pipeline) { |r| Commands::Support.pairs_to_h(r) }
      end

      def drop(pipeline)
        @client.invoke("RAG.DROP", pipeline) { |r| r == "OK" }
      end

      def list
        @client.invoke("RAG.LIST")
      end

      private

      def search_row(row)
        chunk_id, doc_id, text, score, vector_score, bm25_score, *rest = row
        meta = {}
        rest.each_slice(2) { |(k, v)| meta[k] = v }
        { chunk_id: chunk_id, doc_id: doc_id, text: text, score: Wire.parse_float(score),
          vector_score: Wire.parse_float(vector_score), bm25_score: Wire.parse_float(bm25_score), meta: meta }
      end
    end
  end
end
