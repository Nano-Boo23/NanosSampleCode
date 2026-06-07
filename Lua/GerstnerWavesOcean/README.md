# What's this project?

<img width="272" height="245" alt="iQr181780868483" src="https://github.com/user-attachments/assets/a6c85a39-9c14-4eb7-acf8-0dde473328cd" />

This module simulates an effectively infinite ocean by dynamically placing skinned meshes around the player's camera and moving the bones of those meshes with a **[Gerstner / trochoidal](https://en.wikipedia.org/wiki/Trochoidal_wave)** wave equation to produce realistic, rolling waves. It streams mesh tiles in and out as the player travels, keeps the part count roughly constant, and scales its cost to the player's graphics-quality setting.

**Showcase game:** https://www.roblox.com/games/86081630361588/M-E-O-W
> What does M.E.O.W. mean? **M**odule for **E**oA's **O**ptimized **W**aves, lol. I made this module for the Roblox game Echoes of Arcania, which I am also currently developing (as of 2026-06-07).
---

## How does the module work?

That probably sounded like *a mouthful of random words*, so here's the breakdown.

### The mesh

The module needs *something* to move. It uses a **skinned mesh**; a mesh with a grid of bones you can move independently. The mesh used in my showcase game was made in Blender by subdividing a plane, adding armatures (also known as bones) on the vertices, and exporting it to Roblox Studio. That allows us to deform its surface by changing a bone's `Transform`, and that's how every wave is drawn.

<img width="1263" height="741" alt="image" src="https://github.com/user-attachments/assets/505464e2-14b9-42e2-a51c-658bf01693f8" />

### The main rendering functions

To render the ocean, module exposes 2 functions:

| Function | Call it… | What it does |
| --- | --- | --- |
| `GenerateMeshes(pos: Vector3)` | roughly every `0.5 s` | Places/reuses skinned-mesh tiles in a grid around `pos`. |
| `RenderWaves()` | on `RenderStepped` | Runs the Gerstner math and moves the bones. |

`GenerateMeshes` lays out mesh tiles in a grid around the given position. The radius is `RENDER_DISTANCE + BORDER_BUFFER` chunks. Tiles that drift out of range are returned to a pool and reused, so travelling across the ocean doesn't keep spawning new instances.

`RenderWaves` is where we have all of the wave computation stuff. For each active bone it sums the configured Gerstner waves, biases them by `WIND`, and writes the result to the bone's `Transform`. Tiles farther from the camera update less often and fade flat toward the render edge.

### Gerstner waves

To put it simply, a Gerstner wave pushes surface points in a **circular orbit** rather than a simple up/down sine, which creates a more natural looking water. We create this wave by adding multiple waves on top of each other, defined in `WAVES`. I also biased these waves toward the global `WIND` direction.

I also found this really cool [gerstner wave simulator](https://madblade.github.io/waves-gerstner/) you can play with on your browser!

<img width="1920" height="631" alt="Trochoidal_wave svg" src="https://github.com/user-attachments/assets/8ce0f1b5-c18d-4e30-8beb-962ad0d4d1e8" />
<img width="1920" height="auto" alt="Forces_in_Trochoidal_wave" src="https://github.com/user-attachments/assets/033ac309-11b4-4e4b-93c5-f16cab279e5d" />


### Level of detail & performance

Along with the base behavior, I used several different techniques to imrpove the general experience of players:

- **Visibility culling**: only meshes on screen (specifically, any mesh with at least 1 corner visible) are animated; the rest are skipped.
- **Neighbouring mesh animation**: meshes just off-screen that border a visible tile still animate, so you never see a flat mesh right on the edge of your screen.
- **Update-rate falloff**: tiles within `RENDER_DISTANCE` update every frame, while the ones past `RENDER_DISTANCE + LOWERED_RENDER_RATE_DISTANCE` have their update rate dropped off with distance (controlled by `RENDER_RATE_FALLOFF`).
- **Edge propagation**: coincident edge bones between neighbouring tiles are linked so a skipped tile still keeps its seam aligned with its animated neighbour, preventing visible tearing. It's accurate but costs more, so it's only enabled at the highest quality levels.
- **Fake horizon**: a static four-part "fan" of flat parts that sits at `SEA_LEVEL` and surrounds the live water meshes. It basically does not have any performance impact, since it doesn't have any bones and is always static (unless the player moves). Its inner edge lines up with the outer edge of the generated tiles, and because the waves already fade flat at the render edge, the join is seamless. Its far edges are meant to disappear into fog/atmosphere.

### Buoyancy

`GetWaterHeightAtPos(x, z)` returns the surface `Y` at a world XZ position: you can use it to float boats, players, or anything else on the waves. It sums the same wave layers as the renderer, but is **independent of graphics quality** and synced to `workspace:GetServerTimeNow()`, so every client sees exactly the same surface.

---

## Module configuration

All settings are stored on the module table and can be edited at the top of `WavesModule`:

| Setting | Type | Description |
| --- | --- | --- |
| `DEBUG` | `boolean` | Tints tiles by state to help debug streaming. (green = visible / yellow = border / red = culled) |
| `WIND` | `Vector3` | Global wind; biases every wave's direction (the XZ components are used). |
| `SEA_LEVEL` | `number` | World `Y` the ocean rests at. |
| `RENDER_DISTANCE` | `number` (chunks) | Radius of fully rendered & animated tiles. Also the radius over which waves fade to flat. |
| `LOWERED_RENDER_RATE_DISTANCE` | `number` (chunks) | Tiles within this update every frame; beyond it, updates thin out. |
| `RENDER_RATE_FALLOFF` | `number` | How quickly update frequency drops with distance past the full-rate zone (higher = cheaper, choppier far away). |
| `BORDER_BUFFER` | `number` (chunks) | Extra ring of tiles generated past `RENDER_DISTANCE` so the visible edge has neighbours to blend against. The fake horizon covers everything beyond it. |
| `EDGE_PROPAGATION` | `boolean` | Links coincident edge bones between tiles to prevent seam tearing. More accurate, but heavier. |
| `WAVES` | `array` | The Gerstner wave layers (see below). |

### Wave layers (`WAVES`)

Each entry in the array is one wave:

| Field | Meaning |
| --- | --- |
| `direction` `{X, Z}` | Direction of travel on the XZ plane. |
| `amplitude` | Wave height. |
| `wavelength` | Wave width (crest-to-crest). |
| `speed` | How fast it completes a cycle. |
| `steepness` | Orbit shape: `0` = pure sine wave, `1` = sharpest possible Gerstner peak. |

<img width="600" height="408" alt="three_waves" src="https://github.com/user-attachments/assets/a7988233-4207-4728-b586-e7129447c7b9" />


More layers = more detail, but more calculation cost. Because `GetWaterHeightAtPos` sums all layers, **keep `WAVES` identical across clients** if your gameplay relies on water height (buoyancy, swimming, etc.).

---

## Quality presets

In the showcase game I also implemented some sea quality level presets that are applied depending on the player's current quality level. "Automatic" quality falls back to a sensible mid-high level.
<img width="802" height="110" alt="image" src="https://github.com/user-attachments/assets/2032e5eb-8852-456c-884c-a87d0e1df870" />

These presets only touch the render / update / distance settings. `WIND`, `SEA_LEVEL`, and `WAVES` are deliberately left alone so the **simulated surface height stays the same on every client** no matter their quality.

---

## Public API

| Function | Returns | Purpose |
| --- | --- | --- |
| `GenerateMeshes(pos: Vector3)` | – | Stream mesh tiles around a position. |
| `RenderWaves()` | – | Animate the waves for this frame. |
| `ResetMeshes()` | – | Pool every tile so they rebuild from scratch. |
| `GetWaterHeightAtPos(x, z)` | `number` | Surface `Y` at a world XZ position (buoyancy). |
| `ApplySettings(settings)` | `boolean` | Apply a quality preset; `true` if a `ResetMeshes()` is needed. |

---

## Basic setup

```
ReplicatedStorage
├── WavesModule        (ModuleScript)    ← this module
│   └── SeaMesh        (MeshPart)        ← the skinned ocean tile
└── SettingPresets     (ModuleScript)    ← quality presets q1–q10

Workspace
└── Sea                (Model)           ← container for generated tiles + horizon
```

### Using your own mesh

I identified that bones named 0,1,2,3 are the corner bones, and that names up to 39 (included) are edge bones. I'm using this knowledge for an incredibly fast but hard-coded relative bone position lookup. If you want to use my infrastructure, you'll have to re-map `EDGE_NAMES` in `WavesModule`. You can quickly check your own mesh corners / edges with this command:
for _, bone in ipairs(workspace.YourMesh:GetDescendants()) do
    if bone:IsA("Bone") then
        local local_pos = workspace.YourMesh.CFrame:PointToObjectSpace(bone.WorldPosition)
        print(bone.Name, math.round(local_pos.X), math.round(local_pos.Z))
    end
end

---

## Update log

Since Roblox limits the game description to 1000 characters, here's the full update log, most recent first:

- **v1.8**: Added presets for every roblox quality level. Added a fake horizon to better give an illusion of an infinite ocean. Adapted UI for smaller devices.
- **v1.7**: Added individual wave adding/removing, plus bulk wave importing/exporting for sharing wave combinations.
- **v1.6**: QoL changes; most notably, you can now drag the Gerstner wave panel around.
- **v1.5**: Made wave-direction and wind-direction UI more intuitive.
- **v1.4**: Added player buoyancy on the wave surface, and UI touchscreen compatibility for phones.
- **v1.3**: Added Gerstner wave visualization panel (a 2D slice of the combined 3D waves).
- **v1.2**: Added Gerstner/sinusoidal wave configuration panel with an integrated graph of the current wave's equation.
- **v1.1**: Added a tab option to modify the current wave equations.

---

## File extension notes

| Extension | Script type |
| --- | --- |
| `.lua` | Module script |
| `.client.lua` | Local script |
| `.server.lua` | Server script |
