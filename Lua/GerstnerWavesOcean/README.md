# What's this project?
***(documentation still in progress)*** <br>
This client-server module simulates an infinite ocean by dynamically placing skinned meshes based on the player's current camera position, and moving the bones in those meshes using a Gerstner / Trochoidal wave equation to simulate the movement of realistic waves.
<br>
# How does the module work?
That probably sounded like _a mouthful of random words_ to some readers, so let me break down **how the module works**: <br>
<br>
Before anything, the module needs _something_ to move, so (in my case) I utilized a skinned mesh, which is basically a mesh with a bunch of bones that you can move. I created it in Blender by subdividing a mesh, placing armatures (also called bones) on those vertices, and exporting it to Roblox Studio. This allows movement of that mesh via editing the properties of the bones.
<br>
<br>
The module has 2 main functions, which I reccomend calling every `0.5` seconds and at `RenderStepped` respectively: <br>
\- `GenerateMeshes(Pos: Vector3)` <br>
\- `RenderWaves()` <br>
<br>
`GenerateMeshes` places the skinned meshes in a grid pattern around the passed `Vector3`. The radius of this mesh placement is based on the `FAKE_RENDER_DISTANCE` setting. <br>
`RenderWaves` is where all the wave computation happens. (here is where Gerster waves r used)

# Module configuration 
If you want to play around with the showcase game you'll have to understand what some of the settings affect:
- (settings here)

Showcase game:
https://www.roblox.com/games/86081630361588/M-E-O-W#!/game-instances

### File extension notes:
`.lua` -> Module script <br>
`.client.lua` -> Local script <br>
`.server.lua` -> Server script <br>
