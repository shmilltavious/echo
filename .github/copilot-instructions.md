# ECH.o — Project Context

## What This Is
ECH.o is a multiplayer survival horror game on Roblox built around echolocation.
Players are completely blind. Sound (footsteps, voice chat, thrown objects) creates
expanding visual pulses that temporarily reveal the environment in wireframe.
A monster hunts by sound — every noise is a risk.

## Language & Runtime
- Language: Luau (Roblox's typed superset of Lua). NOT standard Lua 5.1.
- Always use type annotations on function parameters and returns.
- Use `task.wait()`, `task.spawn()`, `task.defer()` — NEVER `wait()`, `spawn()`, or `delay()`.
- Use `LinearVelocity` / `AlignPosition` — NEVER `BodyVelocity`, `BodyPosition`, or `BodyGyro`.
- Prefer `math.noise()` over `math.random()` for procedural generation.

## Project Structure (Rojo)
- Sync tool: Rojo. Config in `default.project.json`.
- `src/server/` → ServerScriptService.Server (server scripts)
- `src/client/` → StarterPlayer.StarterPlayerScripts.Client (client scripts)
- `src/shared/` → ReplicatedStorage.Shared (shared modules)
- File extensions: `.luau` for all scripts.
- `init.server.luau` or `init.client.luau` for entry points.
- Server files use `.server.luau` suffix (e.g., `MonsterAI.server.luau`).

## Architecture Rules
- Client/server separation is absolute. Never trust client input.
- RemoteEvents for client → server communication. Validate all arguments server-side.
- RemoteFunctions: avoid unless necessary. Never let clients invoke server RemoteFunctions.
- Shared modules in `src/shared/` must be pure logic — no side effects, no service calls.
- ModuleScripts return a single table.

## Key Game Systems (already built or in progress)
- `MazeGenerator.luau` — procedural maze/corridor generation
- `MonsterAI.server.luau` — entity that pathfinds toward sound sources
- `MonsterSetup.server.luau` — spawning and configuring the entity
- `ButtonSystem.luau` — server-side interactive button handling
- `PulseVisualizer.luau` — client-side echolocation pulse rendering
- `SphereVisuals.luau` — visual sphere expansion effect
- `SphereDetection.luau` — shared detection radius logic
- `PulseRelay.luau` — client relay for pulse events
- `InputHandler.luau` — client input processing
- `Menu.luau` — client UI menu
- `ButtonPrompt.luau` — client proximity prompt UI
- `Constants.luau` — shared constants (speeds, radii, timings)

## Coding Style
- Services: `local Players = game:GetService("Players")` at top of file.
- One service per line, alphabetical order.
- Use `--!strict` at the top of every file.
- Error handling: wrap DataStore calls and network calls in pcall/xpcall.
- Comments: brief, explain WHY not WHAT. No "-- increment i" style comments.

## Performance Constraints (Roblox-specific)
- Target: 60fps on mid-range PC, 30fps on mobile.
- Avoid `Instance.new()` in loops — pre-create and pool objects.
- Echolocation pulses are the most expensive operation. Reuse Part instances.
- Use CollectionService tags for batch operations on similar objects.
- Minimize RemoteEvent frequency — batch updates where possible.