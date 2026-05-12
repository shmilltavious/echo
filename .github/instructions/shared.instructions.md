---
applyTo: "src/shared/**"
---
# Shared Module Rules for ECH.o

You are editing SHARED modules. These live in ReplicatedStorage and are used by both client and server.

## Rules
- No side effects on require — modules return a frozen table of functions/constants
- No service calls (no game:GetService) — pass services in as parameters if needed
- Must work identically on client and server
- Type-annotate all exports

## Constants.luau Conventions
- All magic numbers go here: speeds, radii, durations, thresholds
- Group by system: MOVEMENT, PULSE, MONSTER, AUDIO
- Example: `Constants.PULSE.WALK_RADIUS = 40`

## SphereDetection.luau
- Pure math: given a position and radius, determine which parts/players are inside
- No instance creation — that's the client visualizer's job