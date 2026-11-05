# Elixir context

Apply only the sections supported by the consuming project's actual dependencies and versions. Plain Elixir projects do not inherit Phoenix, Ecto or Oban requirements.

## OTP and module boundaries

Inspect the application supervision tree, public context APIs and data ownership. Use processes for concurrency, state ownership or lifecycle requirements, not simply to organize functions. Keep pure calculations as functions. Follow the project's error and supervision policy rather than mechanically rescuing every exception or crashing every caller.

Before renaming a module, inspect behaviours, callbacks, configuration, child specifications, dynamic dispatch, serialized references and persisted jobs. A direct-call search does not prove that a module is unused. Do not expose functions solely for tests.

## Phoenix and LiveView, when present

Trace the user event, server state, asynchronous work and rendered response. Avoid blocking callbacks. Correlate asynchronous results with the current selection and preserve the last valid state on a failed refresh. Verify subscription cleanup, cancellation and reconnect behavior. Measure rendering and query costs before blaming the framework.

## Ecto, when present

Keep domain invariants and validation at the appropriate boundary. Use changesets and database constraints for their respective guarantees. Make related local writes transactional where required; a database transaction cannot roll back an external effect. Check tenant scoping, query shape and preloads. Plan migrations for the actual data volume and coexisting readers/writers.

## Oban and model calls, when present

Separate queue concurrency from global provider capacity. Understand retries, uniqueness, cancellation and duplicate effects; job uniqueness alone does not guarantee idempotency of an external request. Account for existing persisted jobs before changing arguments or worker identities. Follow the project's budget, telemetry, privacy and retry policies for paid calls.

## Verification

Discover the project's real commands. Use ExUnit and appropriate integration checks without imposing a new testing framework. Isolate database, time, queue and network effects. Run formatting and compilation checks without starting the application unless required. Do not run database reset, seeds or release publication as an incidental setup step.
