---
applyTo: "src/client/**"
---
# Client-Side Rules for ECH.o

You are editing CLIENT scripts. These run in StarterPlayerScripts.

## Absolute Rules
- NEVER reference: ServerStorage, ServerScriptService, DataStoreService
- NEVER modify other players' characters or data directly
- ALL gameplay-affecting actions must go through RemoteEvents to the server
- The client is UNTRUSTED — it requests, the server decides

## Echolocation Rendering
- Screen is pitch black by default (Lighting.Brightness = 0, Ambient = 0,0,0)
- Sound events trigger expanding sphere visuals originating from the sound source
- Pulse reveals geometry by temporarily making parts visible (wireframe/edge highlight style)
- Pulse fades after a few seconds — use TweenService for smooth fade
- Pulse radius scales with: movement speed (crouch < walk < sprint) and mic volume

## Input Handling
- InputHandler.luau processes all player input
- Movement states: Crouching, Walking, Sprinting — each has different sound radius
- Crouch: faint short-range pulse, very low monster risk
- Walk: medium pulse, moderate risk
- Sprint/Jump: massive pulse, extreme risk — lights up entire hallways

## Voice Chat Integration
- Use AudioAnalyzer to read mic volume
- Map volume thresholds to pulse intensity tiers (whisper, talk, shout)
- "Marco Polo" mechanic: shouting creates huge pulse for teammates but attracts Entity