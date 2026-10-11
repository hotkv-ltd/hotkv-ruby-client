# HotKV Ruby Client

[![CI](https://github.com/hotkv-ltd/hotkv-ruby-client/actions/workflows/ci.yml/badge.svg)](https://github.com/hotkv-ltd/hotkv-ruby-client/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A high-performance Ruby client for [HotKV](https://hotkv.com), a RESP2/RESP3-compatible
in-memory data store with built-in AI and LLM-serving features (semantic and prompt
caching, agent memory, RAG, feature store, rate limiting, time series and more).

Zero runtime dependencies (only Ruby's own socket, openssl, digest and json standard library).

## Install

Add it to your Gemfile:

```ruby
gem "hotkv"
```

or install it directly:

```
gem install hotkv
```

Requires Ruby 3.0 or newer. Built and verified against HotKV server
v0.3.0 (see [Compatibility](#compatibility)).

## Quick start

```ruby
require "hotkv"

client = HotKV::Client.new(url: "hotkv://localhost:6379")

client.set("greeting", "hello")
client.get("greeting") # => "hello"

client.close
```

## Connection options

`HotKV::Client.new` takes a `url:` and/or keyword options; an explicit
keyword always overrides whatever the URL carried for the same setting.

```ruby
client = HotKV::Client.new(
  url: "hotkv://localhost:6379",
  username: "app",
  password: ENV.fetch("HOTKV_PASSWORD"),
  db: 2,
  client_name: "billing-service",
  connect_timeout: 5.0,   # seconds; nil disables the timeout
  command_timeout: nil,   # seconds; nil (the default) never times out a
                          # command client side, which matters for
                          # blocking commands like BLPOP
  pool_size: 10,
  idle_timeout: 300,      # seconds a pooled connection may sit idle
                          # before it is PINGed on next checkout
  pool_timeout: 5.0       # seconds to wait for a free pooled connection
)
```

Accepted URL schemes: `hotkv://`, `hotkvs://` (TLS), and, for drop in
migration from a Redis client, `redis://` / `rediss://`. Unix sockets use
`hotkv+unix:///path/to/socket`. `hotkv://user:pass@host:port/3` sets
username, password and the database index.

### TLS

```ruby
client = HotKV::Client.new(
  url: "hotkvs://localhost:6379",
  ca_file: "/etc/ssl/certs/hotkv-ca.pem",
  cert_file: "/etc/ssl/certs/client.pem", # optional client certificate
  key_file: "/etc/ssl/private/client.key",
  server_name: "hotkv.internal"           # SNI / hostname verification override
)

# Tests only: skip certificate verification entirely.
HotKV::Client.new(url: "hotkvs://localhost:6379", insecure_skip_verify: true)
```

### Pooling

Every `HotKV::Client` keeps a bounded, thread safe connection pool
(`pool_size`, default 5). Each command checks a connection out, runs, and
returns it; idle connections older than `idle_timeout` seconds are health
checked with `PING` before being handed out again. One client instance is
safe to share across threads.

## Pipelines

Batch many commands into a single round trip. A command that fails does
not abort the batch: its slot in the result Array holds the `HotKV::Error`
instance instead.

```ruby
results = client.pipelined do |p|
  p.set("a", "1")
  p.incr("a")
  p.get("a")
end
results # => ["OK", 2, "2"]
```

## Transactions

`multi` runs a server side MULTI/EXEC block on one connection:

```ruby
result = client.multi do |tx|
  tx.set("balance", "100")
  tx.decrby("balance", "30")
end
result # => ["OK", 70]
```

`watch` holds one connection for optimistic locking: read on it to decide,
then call `multi` on the same session to commit. `EXEC` returns nil (and so
does `multi`) if a watched key changed first.

```ruby
result = client.watch("balance") do |w|
  current = w.get("balance").to_i
  w.multi do |tx|
    tx.set("balance", (current - 30).to_s)
  end
end

if result.nil?
  # someone else changed "balance" first; retry
end
```

## Pub/Sub

`subscribe`, `psubscribe` and `ssubscribe` open a dedicated connection and
block the calling thread, dispatching frames to callbacks:

```ruby
client.subscribe("orders") do |on|
  on.subscribe { |channel, count| puts "listening on #{channel} (#{count} total)" }
  on.message do |channel, payload|
    puts "#{channel}: #{payload}"
    on.unsubscribe if payload == "stop" # ends the loop once confirmed
  end
end
```

Run it in its own `Thread` if you need the rest of your program to keep
going; `on.unsubscribe`/`on.punsubscribe`/`on.sunsubscribe` (called with no
block) end the loop from inside a callback.

## Cluster

`HotKV::Cluster` discovers the slot map with `CLUSTER SLOTS`, routes each
command by its key's CRC16 slot (with `{hash tag}` support), and follows
`MOVED` (refreshing the map) and `ASK` (sending `ASKING` first)
automatically. It exposes the exact same typed command methods as
`HotKV::Client`.

```ruby
cluster = HotKV::Cluster.new(urls: ["hotkv://node-a:6379", "hotkv://node-b:6379"])
cluster.set("user:42", "active")
cluster.get("user:42")
cluster.close
```

Against a server that is not running in cluster mode, `HotKV::Cluster`
simply routes every command to the configured seed node(s), so the same
client also works for local development against a single server.

## HotKV exclusive commands

The HotKV specific command families (tags, nanosecond TTLs, GCRA and
token bucket rate limiting, vector search, time series, feature store,
semantic/prompt/tool/negative/guard/rerank caches, agent memory, RAG, LLM
stats and budgets, prompt registry, embedding dedup, tenancy, IAM, audit,
encryption and replication control) have typed, namespaced helpers
returning Hash/Struct results:

```ruby
client.tag.set("doc:1", "vip", "beta")
client.tag.members("vip") # => ["doc:1", ...]

client.nexpire("doc:1", 5_000_000_000) # nanosecond resolution TTL

client.ts.create("cpu.load", retention: 86_400_000)
client.ts.add("cpu.load", 0.42)
client.ts.range("cpu.load", "-", "+")

client.ratelimit.create("api", 100, 60_000)
client.ratelimit.check("api", "user:42") # => {allowed:, remaining:, ...}

client.vsim.createindex("docs", 384)
client.vsim.set("docs", "doc:1", embedding)
client.vsim.search("docs", 5, query_embedding)
```

Enterprise features need a server license that includes them; a command
whose feature is not licensed raises `HotKV::Error::NotLicensedError`,
distinct from every other server error so you can detect and handle it
(for example, to fall back to a simpler code path).

## AI caching

`HotKV::AI::PromptCache` builds a deterministic cache key from provider,
model, the normalized messages/system prompt and generation parameters (so
the exact same call always hits, across processes and restarts), and only
calls your LLM on a miss:

```ruby
prompt_cache = HotKV::AI::PromptCache.new(client, namespace: "chat", stats_bucket: "chat-llm")

messages = [{ role: "user", content: "Summarize the HotKV pooling model in one sentence." }]

result = prompt_cache.get_or_call(
  provider: "openai",
  model: "gpt-4o",
  messages: messages,
  params: { "temperature" => "0.2" } # generation params are always string valued
) do
  # This block only runs on a cache miss.
  response = openai_client.chat(model: "gpt-4o", messages: messages, temperature: 0.2)
  prompt_cache.record_usage(
    input_tokens: response.usage.prompt_tokens,
    output_tokens: response.usage.completion_tokens,
    cost_usd: response.usage.estimated_cost_usd,
    latency_ms: response.latency_ms
  )
  response.text
end

result[:response]   # the (cached or freshly generated) text
result[:cache_hit]  # true if this call never touched the LLM
```

`HotKV::AI::SemanticCache` looks up the nearest cached answer above a
similarity threshold for a caller supplied embedding vector (the SDK never
computes embeddings itself, so it works with any provider):

```ruby
semantic_cache = HotKV::AI::SemanticCache.new(client, dims: 1536, namespace: "faq", threshold: 0.9)

question = "How do I enable TLS?"
embedding = embeddings_client.embed(question)

result = semantic_cache.get_or_call(question, embedding) do
  llm_client.answer(question) # only called on a miss
end
result[:response]
```

Both helpers are provider neutral: they never depend on any particular
LLM or embeddings SDK.

**Recording usage so hits report savings**: `get_or_call`'s block may
return either just the response, or a `[response, usage]` pair (a
`HotKV::TokenUsage`, the original call's token usage). When it does, that
usage is stored with the cache entry, so a later hit attributes its
tokens, and once the model is priced, their exact cost, to the
namespace's `usage_saved_*` stats:

```ruby
result = prompt_cache.get_or_call(provider: "anthropic", model: "claude-sonnet-5", messages: messages) do
  response = my_llm_client.chat(model: "claude-sonnet-5", messages: messages)
  usage = HotKV::TokenUsage.new(
    model: "claude-sonnet-5",
    input_tokens: response.usage.input_tokens,
    output_tokens: response.usage.output_tokens
  )
  [response.text, usage] # get_or_call stores `usage` on a miss
end
prompt_cache.stats # usage_saved_requests, usage_saved_input_tokens, ..., usage_saved_cost_usd
```

## LLM cost tracking

`client.llmstats` and `client.llmbudget` track token usage and cost
independently of caching, e.g. across every call your application makes to
a given model:

```ruby
client.llmstats.bucket("chat")
client.llmstats.record("chat", 100, 20, 0, 0, 120.5, model: "claude-sonnet-5")
# cost_usd (the 5th argument, 0 above) is ignored and priced by the server when `model` is given
client.llmstats.get("chat") # requests, cost_usd, cache_write_5m_tokens, ...

# Custom pricing for a model not in HotKV's built-in price table
client.llmstats.price_set("my-fine-tuned-model", 2, 8) # USD per 1,000,000 input/output tokens
client.llmstats.price_get("my-fine-tuned-model")

client.llmbudget.set("team-alpha", 1_000_000, 50.0, 86_400)
allowed = client.llmbudget.consume(
  "team-alpha", usage: HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)
)
```

For OpenAI style responses, whose `prompt_tokens` already includes cache
hits, pass `prompt_tokens - cached_tokens` as `record`'s `input_tokens`
argument (`cached_tokens` is always cache-READ tokens, unlike Anthropic,
which reports it separately).

## Command coverage

Typed methods cover strings, keys/expiry, lists, sets, hashes (including
per field TTL and the newer `HGETDEL`/`HGETEX`/`HSETEX`), sorted sets,
streams (including `XSETID`, `XCFGSET` and idempotent `XADD`), geospatial,
bitmaps, HyperLogLog, Bloom/Count-Min/Top-K (`client.bf`, `client.cms`,
`client.topk`), Pub/Sub publishing and introspection, Lua scripting and
functions, `SORT`, ACL, the commonly used server and `CLIENT` commands and
the `SCAN` family (`scan_each`, `hscan_each`, `sscan_each`, `zscan_each`
return Ruby Enumerators). The newer `MSETEX`, `DELEX`, `DIGEST` and
`SET ... IFEQ/IFNE/IFDEQ/IFDNE` are typed too.

This is **not** every command. Commands without a typed method go through
the generic `command` method; the main groups are:

- `CLIENT TRACKING`/`CACHING`/`GETREDIR`/`TRACKINGINFO`/`REPLY` (they
  change how a connection behaves, so they need a dedicated connection),
- every `CLUSTER` subcommand, `CLUSTERSCAN`, `SFLUSH`, `TRIMSLOTS`,
  `MIGRATE`, `READONLY`/`READWRITE`,
- `HIMPORT` (its state lives on one connection),
- `LATENCY`, `MODULE`, `MONITOR`, `DEBUG`, `REPLICAOF`, `SHUTDOWN`,
  `FAILOVER` and most `MEMORY` subcommands,
- the internal `*.SYNC` replication helpers.

Every one of them is reachable through the generic method, which sends the
arguments as given (Strings are sent byte for byte) and returns the decoded
reply:

```ruby
client.command("LOLWUT")
client.execute("OBJECT", "HELP") # alias
client.command("CLUSTER", "KEYSLOT", "user:42")

# Connection scoped state needs one connection: run it in a pipeline.
client.pipelined do |p|
  p.command("HIMPORT", "PREPARE", "user", "name", "age")
  p.command("HIMPORT", "SET", "user:1", "user", "Ada", "36")
end
```

### Numbers

Floats are always sent as plain decimal text (`HotKV::Wire.float`): Ruby's
`1.0e-05` goes out as `0.00001`, so values the server's stricter parsers
refuse in exponent form (for example `LLMBUDGET.SET`'s cost limit, which is
a fixed point amount) work. Infinity is sent as `inf`/`-inf` where the
server takes it (sorted set scores); NaN, and infinity where only finite
numbers are valid (`INCRBYFLOAT`, coordinates, vector components,
thresholds), raise `HotKV::Error::ArgumentError` before anything is sent.
Money amounts (`llmbudget.set`, `llmstats.price_set`) are rounded to the
micro dollar the server stores, and an amount too small to survive that
rounding raises instead of silently becoming 0.

### Replica reads

`HotKV::Cluster` sends every command to the node that owns the key's slot.
Reading from replicas (`READONLY`) is not supported, and passing
`readonly:` or `read_from:` raises `HotKV::Error::ArgumentError` instead of
being ignored. Point a separate `HotKV::Client` at a replica for read
only traffic.

## Error handling

Every server error raises a typed subclass of `HotKV::Error::ServerError`
(itself under `HotKV::Error::Base`), keyed off the server's error prefix:
`HotKV::Error::WrongTypeError`, `NoAuthError`, `NotLicensedError`,
`ReadOnlyError`, `MovedError`/`AskError` (cluster redirects), and a generic
`CommandError` for anything else. Connection, timeout and protocol level
failures raise `HotKV::Error::ConnectionError`, `TimeoutError` and
`ProtocolError` respectively.

```ruby
begin
  client.set("readonly-key", "value")
rescue HotKV::Error::NotLicensedError => e
  logger.warn("HotKV feature not licensed: #{e.message}")
rescue HotKV::Error::ConnectionError => e
  logger.error("HotKV unreachable: #{e.message}")
end
```

A `nil` bulk reply (a missing key, a cache miss, ...) is always a plain
Ruby `nil`, never an exception.

## Testing

Unit tests need no server:

```
bundle install
bundle exec rake test:unit
```

Integration tests run against a real HotKV server, reached through
`HOTKV_TEST_URL`, and are skipped automatically when that variable is
unset:

```
HOTKV_TEST_URL=hotkv://127.0.0.1:6379 bundle exec rake test:integration
HOTKV_TEST_RESP3=0 HOTKV_TEST_URL=... bundle exec rake test:integration   # over RESP2
```

`bundle exec rake test` runs both. Integration tests for an enterprise
feature your license does not include skip themselves with a clear reason
(detecting `HotKV::Error::NotLicensedError`) rather than failing. The
suite uses unique key and namespace names and cleans up after itself, but
use a server you do not mind it writing to; the `FLUSHDB`/`SWAPDB` tests
touch only databases 13 to 15.

Further opt-in runs:

- `HOTKV_REMOTE_HOST` (with `HOTKV_REMOTE_PORT`, `HOTKV_REMOTE_PASSWORD`,
  `HOTKV_REMOTE_CA`) runs `test/integration/remote_server_test.rb`, a
  customer style session against a TLS and password protected server.

## Compatibility

Developed and tested against HotKV server **v0.3.0** (RESP2 and RESP3, with
the enterprise families licensed). Commands a given server does not know raise a `HotKV::Error::CommandError`;
unlicensed enterprise commands raise `HotKV::Error::NotLicensedError`.
Ruby 3.0 to 3.3 are supported; the unit tests run on every one of them in
the CI matrix.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Support

- Bugs and feature requests: [GitHub issues](https://github.com/hotkv-ltd/hotkv-ruby-client/issues)
- Questions and commercial support: support@hotkv.com
- Security vulnerabilities: see [SECURITY.md](SECURITY.md)

## License

Licensed under the Apache License, Version 2.0: see [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Trademarks and affiliation

"HotKV" is a trademark of HotKV Ltd; the license does not grant rights to use it.
The HotKV server is a separate commercial product, and its enterprise commands need a HotKV license.

HotKV is an independent product of HotKV Ltd. It speaks the RESP protocol and implements
many Redis commands so that existing tools and client habits carry over, but it is not Redis,
Valkey, Dragonfly or KeyDB, and this SDK is built for and tested against HotKV. HotKV Ltd is not
affiliated with, endorsed by or sponsored by Redis Ltd., the Valkey project, DragonflyDB or KeyDB.
Redis is a registered trademark of Redis Ltd. Valkey, Dragonfly, KeyDB and all other product and
company names are trademarks of their respective owners; they are used here only to describe
protocol and command compatibility.
