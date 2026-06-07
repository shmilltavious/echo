# Monster Run/Walk Blender Cleanup

This guide fixes the specific issue where the monster physically moves toward the player, but the run or walk animation appears to move backward. Keep the current Roblox movement, hull, facing, and yaw code. Replace the bad locomotion animation asset after exporting a corrected in-place clip from Blender.

## What Success Looks Like

- The monster's chest/face points the same way it travels.
- The run stride visually moves forward, not backward.
- The clip loops without a pose pop.
- The root/hips do not drift across X/Z during the loop.
- In Roblox Studio, `Workspace.Monster.MonsterVisual_ForwardDot` stays positive while `MonsterVisual_CurrentAnimation` is `Run`.
- `Workspace.Monster.MonsterVisual_DriftMagnitude` stays low during Run/Walk.

## 1. Open A Safe Copy

1. Open the monster `.blend` file in Blender.
2. Immediately save a copy named `monster_animation_cleanup.blend`.
3. Open the Dope Sheet, then switch it to Action Editor.
4. Select the current run action.
5. Duplicate the action and rename the duplicate:

```text
Monster_Run_InPlace_Roblox
```

Work only on the duplicate so the original import is preserved.

## 2. Confirm The Real Forward Direction

1. Scrub the run action in Blender.
2. Identify the monster's face/chest/nose direction.
3. Watch the feet and hips:
   - Correct: the monster appears to run toward its face/chest direction.
   - Wrong: the legs push as if the monster is running away from its face/chest direction.

The Roblox project currently expects the visual rig to use:

```text
MonsterVisualYawOffsetDegrees = -90
```

Do not use Roblox yaw offsets to hide a reversed stride. The animation itself should stride forward.

## 3. Remove Root Translation

The clip must be in-place. The game code moves `Workspace.Monster.MonsterDriver`; the animation should not move the character across the floor by itself.

1. In Pose Mode, find the root-style bone. Common names:
   - `root`
   - `Armature`
   - `mixamorig:Hips`
   - `Hips`
   - `Pelvis`
2. Open the Graph Editor.
3. Inspect Location curves for the root/hips.
4. Flatten horizontal floor movement:
   - Remove or zero X/Y floor-plane translation curves, depending on your Blender axis layout.
   - Keep vertical bounce if it is part of the run.
5. Scrub the loop and confirm the character stays in place while the legs run.

The first and last frame root/hips planar position should match.

## 4. Fix Backward Stride

If the clip stays in place but the stride still looks backward:

1. Check whether the armature/action is facing 180 degrees away from the mesh's visual face.
2. Correct either the action orientation or root bone orientation so the face/chest direction and foot push direction agree.
3. Scrub again from side view and front view.
4. The feet should now plant and push backward relative to travel, making the body appear to move forward.

Avoid negative animation playback speed in Roblox. That will reverse timing, not author a proper forward run.

## 5. Fix The Loop Seam

1. Compare the first and last frames.
2. The full body pose should match closely.
3. If needed, copy the first pose to the last frame.
4. Check feet especially; no sudden sideways foot jump at the seam.
5. In the Graph Editor, make interpolation consistent around the seam.

For this monster, a tiny body bounce is fine. A sideways root pop is not.

## 6. Clean Object Transforms

Before export:

1. In Object Mode, inspect mesh and armature transforms.
2. Mesh object scale should ideally be `1, 1, 1`.
3. Apply mesh transforms only if needed.
4. Be careful applying armature transforms after animation exists; it can change how pose curves behave.
5. Do one final scrub after any transform cleanup.

If applying armature transforms breaks the action, undo and correct orientation through the action/root setup instead.

## 7. Export FBX From Blender

Use these export settings:

```text
Format: FBX
Selected Objects: On
Objects: Armature and mesh only
Bake Animation: On
Action: Monster_Run_InPlace_Roblox only, if possible
Apply Scalings: FBX Unit Scale
Forward: Z Forward
Up: Y Up
```

Recommended filename:

```text
monster_run_inplace_roblox.fbx
```

If Blender exports every action, disable extra action export options or temporarily unlink unrelated actions before export.

## 8. Import Into Roblox Studio

1. Open Roblox Studio.
2. Open the monster rig in the Animation Editor or Clip Editor.
3. Import `monster_run_inplace_roblox.fbx`.
4. Preview before publishing:
   - The monster should run in place.
   - It should visually face the direction of the stride.
   - The loop should not pop.
5. Publish/save the animation.
6. Copy the new `rbxassetid://...`.

## 9. Replace The Project Asset ID

After Roblox gives you the new ID, update this file:

```text
src/shared/Constants.luau
```

Replace:

```lua
Run = "rbxassetid://117522782092613",
Walk = "rbxassetid://117522782092613",
```

with:

```lua
Run = "rbxassetid://NEW_RUN_ID",
Walk = "rbxassetid://NEW_RUN_ID",
```

Keep `Walk` pointed at the fixed Run clip until a real walk animation exists.

## 10. Roblox Test Checklist

Run:

```powershell
rojo build default.project.json --output "$env:TEMP\echo-fixed-run.rbxl"
```

Then in Studio Play mode:

1. Trigger sprint noise.
2. Confirm `Workspace.Monster.MonsterVisual_CurrentAnimation == "Run"` while moving.
3. Confirm `Workspace.Monster.MonsterVisual_ForwardDot > 0`.
4. Confirm the monster visually runs toward you, not away from you.
5. Confirm `Workspace.Monster.MonsterVisual_DriftMagnitude` stays low.
6. Confirm `Workspace.Monster.MonsterCollisionHull.Size` is still `11.8, 7, 11.8`.

If `ForwardDot` is positive and the stride still looks backward, the exported action is still reversed. Return to Blender and fix the action orientation/stride direction before importing again.

## When To Make A Separate Walk Clip

Right now Walk uses the Run asset at reduced speed. That is acceptable temporarily, but a dedicated walk clip is better if:

- Patrol still foot-slides.
- The monster looks too bouncy while walking.
- Run looks fixed but Walk still feels unnatural.

Create `Monster_Walk_InPlace_Roblox` using the same rules: forward stride, in-place root, clean loop.
