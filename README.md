# Roblox Coverage

Code coverage instrumentation for Roblox Luau modules. This library injects lightweight probes into your ModuleScripts at runtime, collects execution hits, and emits an Istanbul-compatible JSON report that you can feed into standard coverage tooling (HTML, lcov, Cobertura, etc.).

## Features
- Runtime instrumentation of ModuleScripts (no compiler plugin required)
- Istanbul/nyc-compatible JSON output
- Function and branch hit tracking in addition to statements
- Sensible include/exclude defaults (avoids `Packages` and the coverage folder)
- Demo place + script to generate full HTML/text/LCOV/Cobertura reports locally

## How it works
1. `coverage.instrument()` walks your include roots, injects `_G.__covhit`, `_G.__covfn`, and `_G.__covbranch` calls into ModuleScript sources, and tracks IDs per line/function/branch.
2. Your code runs normally; probes increment counters in `_G.__COVERAGE__`.
3. `coverage.istanbul()` converts the collected data to an Istanbul report object you can serialize and post-process with `istanbul-lib-*` or CI tools.

## Quick start (demo)
Prereqs: Node.js, Roblox Studio

If you do not have Roblox Studio installed, you can specify a `ROBLOSECURITY` environment variable of a throwaway account to run Luau on the cloud.

```bash
npm install
npm run demo
```

The demo will:
- Build the example place via Rojo to `demo/place.rbxl`
- Run `demo/test.luau` with rbxluau, which instruments and exercises sample modules
- Emit Istanbul JSON to `demo/coverage/coverage-final.json`
- Generate HTML, lcov, Cobertura, text, and JSON summary reports into `demo/coverage/`

Open `demo/coverage/index.html` in a browser to explore the report.

## Using in your experience
```lua
local coverage = require(game:GetService("ReplicatedStorage").coverage)

-- Instrument common services by default; you can pass explicit roots.
coverage.instrument(
    {
        game:GetService("ServerScriptService"),
        game:GetService("ReplicatedStorage"),
        game:GetService("ServerStorage"),
        game:GetService("StarterPlayer"),
        game:GetService("StarterGui"),
    },
    {
        game:GetService("ReplicatedStorage"):FindFirstChild("Packages"),
    }
)
```

1. Run your tests or gameplay to collect coverage.
2. Export the report where you need it (e.g. to HttpService, DataStore, or a file if running in a CLI environment):

```lua
local HttpService = game:GetService("HttpService")
local report = coverage.istanbul()
local json = HttpService:JSONEncode(report)
-- Persist json as needed
```

## Notes
- This library destructively modifies ModuleScript sources. It's recommended to only enable coverage instrumentation in test environments.
- The instrumentation also adds overhead; expect slower execution times when coverage is enabled.
- Coverage JSON uses Roblox datamodel paths, not filesystem paths. You may need to map these paths when integrating with external tools.