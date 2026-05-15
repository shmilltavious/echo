---
applyTo: "src/server/**"
---
# Server-Side Rules for ECH.o

You are editing SERVER scripts. These run in ServerScriptService.

## Absolute Rules
- NEVER reference: LocalPlayer, UserInputService, ContextActionService, PlayerGui, Camera, Mouse
- NEVER require modules from `src/client/`
- ALL client-sent data via RemoteEvents must be validated (type check, range check, sanity check)
- Player data persistence uses DataStoreService with pcall wrapping

## Monster AI Guidelines
- The Entity navigates via PathfindingService toward audio event origins
- Audio events are server-authoritative: client tells server "I made noise at position X with radius Y", server validates and broadcasts
- Monster hearing radius is defined in `src/shared/Constants.luau`
- Monster state machine: Idle → Investigating → Chasing → Attacking → Returning

## Sound Event Flow
1. Client detects player input (footstep, voice, throw) → fires RemoteEvent with position + intensity
2. Server validates position (within reasonable distance of player character)
3. Server stores event in audio event queue
4. Monster AI polls queue each heartbeat and pathfinds to loudest/nearest event