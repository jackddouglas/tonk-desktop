# Render provenance consistency spike

A render receipt needs the revision of the data actually evaluated, followed by
acknowledgments through query frames, host delivery and nested display completion.
Reading the branch head beside a DOM snapshot does not establish this.

First executable question: can a subscription's starting revision identify its
returned rows when a commit lands during evaluation?

The isolated checkout `/tmp/dialog-render-provenance` starts from the exact
`dialog-db` commit used by the conditional-evaluate worktree. Its native test
`it_pins_subscription_reads_before_awaiting` pauses the first provider operation,
commits a name change through the original branch, then releases evaluation. The
expected contract is old rows at the old pin, followed by new rows at the next
poll. This is a prerequisite to exposing a query checkpoint on SSE.

No renderer receipt or new worker protocol is enabled by this experiment.

The subsequent protocol needs three distinct pieces of evidence:

1. A query checkpoint that belongs to the retained rows. It includes both the
   durable branch revision and the ephemeral overlay identity; a null durable
   revision means an evaluated empty branch, not an uninitialized query.
2. Delivery of that checkpoint even when a new revision does not change query
   results. This must not force a DOM repaint or create a repoll loop.
3. A renderer acknowledgment for every active input and nested display in the
   current render generation. Opening a downstream subscription, navigating,
   changing a view, taking a fallback query path, or holding a historical frame
   invalidates completion until the relevant inputs settle again.

Until all three exist, the public inspector continues to report
`renderedRevision: null` and `revisionTracking: unavailable`.

## Reproduction and candidate

Base: `dialog-db` commit `120fba8b6490c31b2ae1523e6add5b800f9b989e`.
`baseline.txt` records the deterministic failure: the old revision was retained
while the paused poll returned the newly committed name. The candidate is in
`dialog-query-checkpoint.patch`; it is not a dependency override or a deployed fix.

Apply the patch in a clean checkout of that commit, then run:

```sh
cargo test -p dialog-repository repository::branch::subscription::tests --lib
cargo fmt --all -- --check
```

The candidate detaches the durable head and session-overlay state before the
first asynchronous poll operation. It preserves branch metadata and shares
content-addressed caches. Idle polls keep their existing early return. A public
`SubscriptionCheckpoint` distinguishes a never-evaluated query from an evaluated
empty branch, and advances even for unchanged query results. Concurrent head
changes during synchronous capture cause a bounded read retry, never a write.

Cost to assess before adoption: active polls currently clone the overlay's fact
indexes and bounded instant log. No performance improvement is claimed. A shared
immutable/COW overlay snapshot may be preferable for large session overlays.

## Validation

- Baseline: deterministic durable-write race failed, returning Bob at Alice's
  captured revision (see `baseline.txt`).
- Candidate: all 47 subscription tests passed, including paused durable writes,
  paused overlay writes, empty-branch checkpoints and unrelated-write checkpoints.
- Rust formatting and patch whitespace checks passed.
- `cargo check -p dialog-repository --lib --target wasm32-unknown-unknown`
  passed, with three warnings in unchanged dialog-storage code.
- This is query-layer evidence only. No SSE delivery or DOM completion guarantee
  is implemented or implied, and the app's existing runtime is unchanged.
