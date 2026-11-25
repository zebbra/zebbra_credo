# zebbra_credo

zebbra's Credo checks for Elixir apps built on Ash and Phoenix. The checks keep the team's conventions in the code: one door per concern, no raw SQL outside the allowed files, a reason for every `authorize?: false`, and the LiveView and Ash rules we agreed on. One Credo plugin line turns them on.

## Install

```elixir
def deps do
  [
    {:zebbra_credo, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

Then add the plugin to `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [{ZebbraCredo, app: MyApp}]
    }
  ]
}
```

`mix credo` now runs every default-enabled check below.

## Plugin params

```elixir
plugins: [
  {ZebbraCredo,
   app: MyApp,
   except: [:clock],
   except_checks: [ZebbraCredo.Check.EnumKernel],
   checks: [
     {ZebbraCredo.Check.ForbiddenCalls,
      rules: [[module: MyApp.Platform, functions: :all, allowed: ["lib/my_app/billing/**"], message: "..."]]},
     {ZebbraCredo.Check.RawSql, allowed: ["lib/my_app/health.ex"]}
   ]}
]
```

| Param | Meaning |
|---|---|
| `app:` | Required. The app's root module. The plugin derives `MyAppWeb`, `lib/my_app/` and `lib/my_app_web/` from it. A missing `app:` is a config error. |
| `web:` | The web namespace, when it is not `<App>Web`. |
| `repo:` | The Ecto repo, when it is not `<App>.Repo`. |
| `except:` | Keys of the `ForbiddenCalls` preset to drop (see the table below). An unknown key is a config error that lists the valid keys. |
| `except_checks:` | Checks to switch off. |
| `checks:` | `{check, params}` tuples. They add params to a default check and turn on opt-in checks. |

Each check receives only the app params it declares. `app:` and `web:` reach the checks that use a namespace, `repo:` reaches `RawSql`, and `except:` reaches `ForbiddenCalls`. The other checks get none of them.

### Precedence

Lowest to highest:

1. The house defaults the plugin derives from `app:`.
2. The params in the plugin's `checks:`.
3. The project's own entries in `checks:` of `.credo.exs`.

A check the project lists itself keeps the project's params, and the plugin fills in `app:` when the project leaves it out. The plugin never enables a check twice. `{check, false}` in the project's config keeps that check off. The old list format (`checks: [...]`) and `extra:` work as well.

### Upgrades

A new version of this package can add checks and preset rules. They apply to every project at once, and the issues they find are on purpose. Fix them, or opt out with `except:` (a preset rule) or `except_checks:` (a whole check).

## Default-enabled checks

All checks have a high base priority.

### SystemComment

Every `authorize?: false` needs a `# system: <why>` comment in the lines right above it.

```elixir
# system: the nightly purge runs without a user.
QueryLog.purge_expired_rows(cutoff, authorize?: false)
```

Params:

* `include_tests:` also check files under `test/` (default `false`).
* `policy_bypasses:` also require the comment above a policy `bypass` (default `false`).

### AshEntryPoints

Only Ash domains, resources, fragments, Ash callback modules (changes, preparations, validations, calculations, manual actions, policy checks, tracers) and Spark verifiers compose Ash: `Ash.read`, `Ash.Query`, `Ash.Changeset`, `Ash.Seed` and so on. Other modules call a domain's code interface. Introspection, types, errors and values stay open to every module.

Fix: define an action with arguments and a code interface on the domain, and call that. No params.

### RawSql

Raw SQL and plain Ecto (`Ecto.Query`, `Ecto.Adapters.SQL`, `Postgrex`, the repo's query functions), a resource's `custom_statements` and table names in `fragment(...)` only in the allowed files. They bypass Ash and its policies.

Fix: use an Ash action or expression. Where Ash cannot express it, add the file to `allowed:` with a comment saying why. The check ships no allow-list, because allow-lists name project files.

Params:

* `app:` the repo defaults to `<App>.Repo`.
* `repo:` the repo, when it is not `<App>.Repo`.
* `allowed:` file globs that may send raw SQL.
* `repo_functions:` repo functions that are not raw SQL (default `[:all_tenants]`).

Allow-list patterns that came up in real projects:

```elixir
{ZebbraCredo.Check.RawSql,
 allowed: [
   # Aggregation queries: Ash has no GROUP BY, unnest or jsonb_to_record.
   "lib/my_app/reporting/queries.ex",
   # Readiness probe: SELECT 1 reads no table.
   "lib/my_app_web/plugs/health.ex",
   # Oban's oban_jobs: no Ash resource reads it.
   "lib/my_app/sync/actions/last_job.ex",
   # Postgres catalog reads: pg_*, schema_migrations, pg_timezone_names.
   "lib/my_app/settings/validations/known_time_zone.ex",
   # Multitenancy plumbing: all_tenants/0 and the per-tenant search_path SQL.
   "lib/my_app/repo.ex",
   "lib/my_app/tenancy/sql.ex",
   # Paper-trail and audit maintenance: one delete per version table.
   "lib/my_app/audit/retention/actions/prune.ex",
   # Foreign or mock databases: not the app's own database.
   "lib/my_app/foreign_database.ex",
   # Search-extension expressions: pg_search BM25 operators.
   "lib/my_app/sources/expressions/bm25_*.ex"
 ]}
```

### ForbiddenCalls

Calls to modules that only some files may make. Each rule is a keyword list: `module:`, `functions:` (a list, or `:all` for any reference to the module or a module under it), `except:` (modules a `:all` rule leaves out), `allowed:` (file globs that may use it), `only:` (file globs the rule applies to, default every file) and `message:` (why, and what to use instead).

With `app:` the house preset applies first. `rules:` adds the project's own.

Params:

* `app:` turns on the house preset. Without it only `rules:` apply.
* `web:` the web namespace, when it is not `<App>Web`.
* `except:` preset keys to leave out.
* `rules:` the project's own rules, added to the preset.

The preset keys:

| Key | Rule |
|---|---|
| `:token_resource` | `AshAuthentication.TokenResource` stays out of the web. |
| `:oban_run_trigger` | No `AshOban.run_trigger`: use `change run_oban_trigger` in the action. |
| `:pubsub_door` | `Phoenix.PubSub` only in `lib/my_app/pub_sub.ex`. The web calls neither it, nor `MyAppWeb.Endpoint.subscribe`, nor `MyApp.PubSub`: it uses the domain's `subscribe_*(scope)`. |
| `:logger` | `Logger` at info and above (including `:log` and `:bare_log`) only in log subscribers, `lib/my_app/telemetry/**`, the web and `lib/mix/**`. |
| `:clock` | `Date.utc_today`, `DateTime.now`, `DateTime.now!`, `DateTime.utc_now`, `NaiveDateTime.local_now`, `NaiveDateTime.utc_now`, `Time.utc_now`, `System.system_time` and `System.os_time` only in `lib/my_app/local_time.ex`. |
| `:http_door` | `Req`, `Finch` and `Mint.HTTP` only in `lib/my_app/http.ex` and `lib/my_app/http/**`. |
| `:decimal_from_float` | No `Decimal.from_float`: build the decimal from a string or an integer. |
| `:aes_ctr` | No `Cloak.Ciphers.AES.CTR`: use GCM, which authenticates the ciphertext. |
| `:mdex_to_heex` | No `MDEx.to_heex` or `MDEx.to_heex!`: it evaluates model output as a template. |

### AssignInRender

A LiveView's or LiveComponent's `render/1` assigns nothing: no `assign`, `assign_new` or `update`. An assign made in `render/1` counts as changed on every render, so every patch re-renders whatever reads it.

Fix: compute the value where its inputs change (`mount`, `handle_params`, `handle_event`, `update`) or read it in the template. Function components assign as usual.

Params:

* `app:` the app's web module is where `use <Web>, :live_view` is recognised.
* `web:` the web namespace, when it is not `<App>Web`.

### EnumKernel

`use Ash.Type.Enum` only in the app's enum kernel and the allowed files. Every other enum is `use MyApp.Type.Enum, values: [...]`.

Params:

* `app:` the kernel is `MyApp.Type.Enum` in `lib/my_app/type/enum.ex`.
* `kernel:` the kernel's file path, when it differs.
* `allowed:` file globs that may `use Ash.Type.Enum` besides the kernel.

### NoAnonymousDslFunctions

No `fn` or `&` as the argument of Ash DSL macros such as `change`, `run`, `prepare` and `validate`. Anonymous functions there cannot be named, reused, tested or found.

Fix: put the logic in its own module and reference it: `change MyApp.Orders.Changes.Slugify` or `change {Module, opts}`.

Params:

* `files:` files to check, as Credo's `included` and `excluded` globs (default `lib/`).
* `macros:` the DSL macros to watch (default `[:run, :change, :prepare, :validate]`).
* `allowed:` file globs that may use anonymous functions.

### ScopeNotActor

The web layer passes `scope: scope` to actions and code interfaces, never `actor:`. Explicit options beat the scope, so `scope: scope, actor: user` silently replaces the scope's actor. `actor: nil` is allowed. Trusted system code may pass `actor:` with a `# system: <why>` comment above. Only files under the app's web directory are checked, never `test/`.

Params:

* `app:` the web directory is the only place checked.
* `web:` the web namespace, when it is not `<App>Web`.

## Opt-in checks

### AshAiToolGuard

Not enabled by default: it needs `loop:`. It holds the hard rules for AshAi tool use, each a way around the Tool Guard:

* No `tools: true` or `resources: true`.
* No prompt action with tools or `extra_tools`, and none whose options the check cannot read.
* No `AshAi.Mcp.Router`, `AshAi.Mcp.Server` or `AshAi.Mcp.Dev`.
* In a file that uses `AshAi.ToolLoop`: only `run/2` and `stream/2`, called by name, each with a literal keyword list that holds `tools: false`. Never `:approvals`, `:actions`, `:otp_app` or a tool list.

Fix: the loop takes `tools: false`, and domain tools come from `build_tools_and_registry/1`, wrapped and passed as `extra_tools`. Only the `loop:` module runs `AshAi.ToolLoop`.

Params:

* `loop:` required. The module that runs `AshAi.ToolLoop`.
* `rules_doc:` path of the document that states these rules, named in the messages.

Turn it on through the plugin:

```elixir
checks: [{ZebbraCredo.Check.AshAiToolGuard, loop: MyApp.AI.Loop}]
```

## Use without the plugin

Each check also works on its own. List it in `checks: %{enabled: [...]}` and pass `app:` as a check param:

```elixir
checks: %{
  enabled: [
    {ZebbraCredo.Check.SystemComment, []},
    {ZebbraCredo.Check.ForbiddenCalls, [app: MyApp, except: [:clock]]},
    {ZebbraCredo.Check.RawSql, [app: MyApp, allowed: ["lib/my_app/health.ex"]]}
  ]
}
```

## License

MIT.
