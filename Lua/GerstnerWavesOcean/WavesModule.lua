--!strict
--!native

--- / Module /
local WavesModule = {}

--- / SETTINGS /
local LINK_THRESHOLD = 0.5  -- (studs) bones closer than this are considered shared at a seam
local SPHERICAL_RENDERING = false --could cause problems if set to true (big spaces between meshes and horizon parts)

-- Check the github documentation buddy https://github.com/Nano-Boo23/NanosSampleCode/blob/main/Lua/GerstnerWavesOcean/README.md
local conf = WavesModule --abbreviation purposes
conf.DEBUG = false

conf.WIND = Vector3.new(-10,0,10) --northeast
conf.SEA_LEVEL = 50 --(studs) at what Y level the mesh will generate at
conf.RENDER_DISTANCE = 2 --(chunks) the spherical radius that determines skinned mesh generation and rendering around the camera.
conf.LOWERED_RENDER_RATE_DISTANCE = 2 --(chunks) in what chunk the vertices get updated with less frequency
conf.RENDER_RATE_FALLOFF = 5 -- how many less updates a chunk gets proportional to current distance
conf.EDGE_PROPAGATION = false --propagates the positions of edge bones to adjacent meshes to prevent visible mesh tearing (not performance friendly though)

-- (chunks) extra ring of meshes generated just beyond RENDER_DISTANCE. The rendered edge needs
-- one ring of neighbours past it so IsMeshBorder has meshes to animate against; the fake horizon
-- now covers everything further out, so this small margin is the only generation buffer we need.
-- Effective generation radius = conf.RENDER_DISTANCE + conf.BORDER_BUFFER.
conf.BORDER_BUFFER = 1

conf.WAVES = {
	{direction = {X = -2.0,	Z = 1.0},	amplitude = 7.0,	speed = 0.01,	wavelength = 400,	steepness = 0.1},
	{direction = {X = -1.0,	Z = -10.0},	amplitude = 1.2,	speed = 0.15,	wavelength = 80,	steepness = 0.1},
	{direction = {X = 9.4,	Z = -3.0},	amplitude = 0.2,	speed = 0.3,	wavelength = 12,	steepness = 0.6},
} :: {GerstnerWave}
--direction: direction of the wave on the XZ plane
--amplitude: height of the wave
--wavelength: width of the wave
--speed: frequency of the wave (how fast it completes a cycle)
--steepness: how circular the particle orbit is. 0 = pure sine wave. 1 = sharpest possible Gerstner peak.


--- / Services /
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- / Types /
type WaveQualitySettings = {
	RENDER_DISTANCE: number,
	LOWERED_RENDER_RATE_DISTANCE: number,
	RENDER_RATE_FALLOFF: number,
	EDGE_PROPAGATION: boolean,
}

type GerstnerWave = {
	direction: {X: number, Z: number},
	amplitude: number,
	wavelength: number,
	speed: number,
	steepness: number,
}
type EdgeBones = {minX: {Bone}, maxX: {Bone}, minZ: {Bone}, maxZ: {Bone}}
type MeshData = {
	Bones: {Bone},
	InnerBones: {Bone},
	EdgeBones: EdgeBones,
	Coords: {X: number, Z: number},
}
type EdgeNames = {minX: {string}, maxX: {string}, minZ: {string}, maxZ: {string}}

type Meshes = {[MeshPart]: MeshData}
type PooledMeshes = {[MeshPart]: {Bones: {Bone}}}


--- / Variables /
local BaseMesh: MeshPart = script:WaitForChild("SeaMesh")
local CurrentUpdateCycle = 0

local Meshes: Meshes = {}
local PooledMeshes: PooledMeshes = {}
local Chunks: {[number]: {[number]: MeshPart}} = {}
local VisibleMeshes: {[MeshPart]: boolean} = {}

--mapping to reduce needed calculations
local SharedBonePositions: {Vector3} = {}
for i, bone in ipairs(BaseMesh:GetChildren()) do
	if bone:IsA("Bone") then
		table.insert(SharedBonePositions, bone.Position)
	end
end

--different, a bit less efficient mapping for other functions that dont do :GetChildren on the mesh
local SharedBoneLocalPosByName: {[string]: Vector3} = {}
for _, bone in ipairs(BaseMesh:GetChildren()) do
	if bone:IsA("Bone") then
		SharedBoneLocalPosByName[bone.Name] = bone.Position
	end
end

-- Hard-coded tables for fast edge bone lookups
local EDGE_NAMES:EdgeNames = {
	-- sorted Z ascending (-50 → 50)
	maxX = {"0","12","11","10","9","8","7","6","5","4","2"},
	minX = {"1","22","23","24","25","26","27","28","29","30","3"},
	-- sorted X ascending (-50 → 50)
	maxZ = {"3","31","32","33","34","35","36","37","38","39","2"},
	minZ = {"1","21","20","19","18","17","16","15","14","13","0"},
}
-- Maps boneName -> list of edge keys it belongs to
-- Corners will have 2 entries, regular edge bones will have 1
local BONE_EDGE_MEMBERSHIP: {[string]: {string}} = {}
for edgeKey, names in EDGE_NAMES :: {[string]: {string}} do
	for _, name in ipairs(names) do
		if not BONE_EDGE_MEMBERSHIP[name] then
			BONE_EDGE_MEMBERSHIP[name] = {}
		end
		table.insert(BONE_EDGE_MEMBERSHIP[name], edgeKey)
	end
end

local function ClassifyBones(mesh: MeshPart, bones: {Bone}): ({Bone}, EdgeBones)
	local inner: {Bone} = {}
	local edge: EdgeBones = {minX = {}, maxX = {}, minZ = {}, maxZ = {}}

	for _, bone in ipairs(bones) do
		local edgeKeys = BONE_EDGE_MEMBERSHIP[bone.Name]
		if edgeKeys then
			-- corner bones get inserted into both their edge lists
			for _, edgeKey in ipairs(edgeKeys) do
				table.insert((edge :: any)[edgeKey], bone)
			end
		else
			table.insert(inner, bone)
		end
	end

	return inner, edge
end


--[[
1-to-many bone links: a bone on one mesh -> list of matching bones on neighboring meshes
At a straight seam, one bone links to one other
At a corner where 4 meshes meet, one bone links to up to three others
]]
local BoneLinks: {[Bone]: {Bone}} = {}

if BaseMesh.Size.X ~= BaseMesh.Size.Z then
	warn(`BaseMesh is not a square: {BaseMesh.Size.X},{BaseMesh.Size.Z}`)
end
local MeshSize = BaseMesh.Size.X
local SeaFolder: Model = workspace:WaitForChild("Sea")




--- / Local Functions /

local function GetWindBiasedDirection(baseDir: {X: number, Z: number}): Vector2
	local GlobalWind = conf.WIND
	if GlobalWind.Magnitude < 0.1 then return Vector2.new(baseDir.X,baseDir.Z) end
	local windDir = Vector2.new(GlobalWind.X, GlobalWind.Z).Unit
	return (Vector2.new(baseDir.X,baseDir.Z) + windDir * 0.6).Unit
end

local function GerstnerWave(wave: GerstnerWave, x: number, z: number, t: number): (number, number, number)
	local biasedDir = GetWindBiasedDirection(wave.direction)
	local k = (2 * math.pi) / wave.wavelength
	local c = math.sqrt(9.8 / k) * wave.speed
	local f = k * (biasedDir.X * x + biasedDir.Y * z) - c * t
	local a = wave.steepness / k

	local dx = a * biasedDir.X * math.cos(f)
	local dy = wave.amplitude * math.sin(f)
	local dz = a * biasedDir.Y * math.cos(f)

	return dx, dy, dz
end

local function CalculateWaves(x: number, z: number, t: number, distanceFromCamera: number): (number, number, number)
	local fade = math.max(0, 1 - (distanceFromCamera / (conf.RENDER_DISTANCE * MeshSize)))

	local totalDX, totalDY, totalDZ = 0, 0, 0
	for _, wave in ipairs(conf.WAVES) do
		local dx, dy, dz = GerstnerWave(wave, x, z, t)
		totalDX += dx
		totalDY += dy
		totalDZ += dz
	end

	return totalDX * fade, totalDY * fade, totalDZ * fade
end

local function GetMeshPos(mesh: MeshPart): Vector3
	return Vector3.new(
		(Meshes[mesh].Coords.X * MeshSize) + (MeshSize / 2),
		conf.SEA_LEVEL,
		(Meshes[mesh].Coords.Z * MeshSize) + (MeshSize / 2)
	)
end

--[[
Links spatially coincident edge bones between two meshes.
Uses a list per bone so that corner bones (shared by 4 meshes) link to all 3 partners
]]
local function LinkNeighborBones(meshA: MeshPart, meshB: MeshPart)
	local dataA = Meshes[meshA]
	local dataB = Meshes[meshB]
	if not dataA or not dataB then return end

	local posA = Vector3.new(dataA.Coords.X * MeshSize, 0, dataA.Coords.Z * MeshSize)
	local posB = Vector3.new(dataB.Coords.X * MeshSize, 0, dataB.Coords.Z * MeshSize)

	local edgesA = {dataA.EdgeBones.minX, dataA.EdgeBones.maxX, dataA.EdgeBones.minZ, dataA.EdgeBones.maxZ}
	local edgesB = {dataB.EdgeBones.minX, dataB.EdgeBones.maxX, dataB.EdgeBones.minZ, dataB.EdgeBones.maxZ}
	
	--task.wait()
	for _, listA in ipairs(edgesA) do
		for _, boneA in ipairs(listA) do
			local worldPosA = posA + boneA.Position
			for _, listB in ipairs(edgesB) do
				for _, boneB in ipairs(listB) do
					
					if (worldPosA - (posB + boneB.Position)).Magnitude < LINK_THRESHOLD then
						if not BoneLinks[boneA] then BoneLinks[boneA] = {} end
						table.insert(BoneLinks[boneA], boneB)
						if not BoneLinks[boneB] then BoneLinks[boneB] = {} end
						table.insert(BoneLinks[boneB], boneA)
					end
				end
			end
		end
	end
end


--[[
Removes all links that involve any bone belonging to this mesh, and clears the
reciprocal entries on the partner bones so the list never holds stale references
]]
local function UnlinkBones(mesh: MeshPart)
	local data = Meshes[mesh]
	if not data then return end

	local allEdgeLists = {data.EdgeBones.minX, data.EdgeBones.maxX, data.EdgeBones.minZ, data.EdgeBones.maxZ}
	for _, list in ipairs(allEdgeLists) do
		for _, bone in ipairs(list) do
			local linked = BoneLinks[bone]
			if linked then
				-- Remove the back-reference from each partner
				for _, partnerBone in ipairs(linked) do
					local partnerLinks = BoneLinks[partnerBone]
					if partnerLinks then
						for i = #partnerLinks, 1, -1 do
							if partnerLinks[i] == bone then
								table.remove(partnerLinks, i)
							end
						end
						-- Clean up empty lists
						if #partnerLinks == 0 then
							BoneLinks[partnerBone] = nil
						end
					end
				end
			end
			BoneLinks[bone] = nil
		end
	end
end

--[[
After a mesh animates its edge bones, copy their transforms to every linked bone
Skipped (rate-limited) meshes get their seam bones updated for free this way
]]
local function PropagateEdges(meshData: MeshData)
	local edges = meshData.EdgeBones
	for _, boneList in ipairs({edges.minX, edges.maxX, edges.minZ, edges.maxZ}) do
		for _, bone in ipairs(boneList) do
			local linked = BoneLinks[bone]
			if linked then
				for _, partnerBone in ipairs(linked) do
					partnerBone.Transform = bone.Transform
				end
			end
		end
	end
end

local function PoolMesh(mesh: MeshPart)
	local meshData = Meshes[mesh]
	if not meshData then return end
	
	UnlinkBones(mesh)
	PooledMeshes[mesh] = {Bones = Meshes[mesh].Bones}
	Meshes[mesh] = nil
	Chunks[meshData.Coords.X][meshData.Coords.Z] = nil
	VisibleMeshes[mesh] = nil
	mesh.Transparency = 1 --TODO unsure if this triggers FastClusters. Testing needed
end

local function GetMesh(): (MeshPart, {Bone})
	local m = next(PooledMeshes)
	local bones: {Bone} = {}

	if m then
		bones = PooledMeshes[m].Bones
		PooledMeshes[m] = nil
		m.Transparency = 0
	else
		m = BaseMesh:Clone()
		m.Parent = SeaFolder
		for _, obj in m:GetChildren() do
			if obj:IsA("Bone") then
				table.insert(bones, obj)
			end
		end
	end

	assert(m)
	if not conf.DEBUG then m.Color = Color3.fromRGB(25, 60, 90) end
	return m, bones
end

--- / Fake horizon /
--[[
A 4-part static "picture frame" at SEA_LEVEL that surrounds the live skinned sea. It never
animates (zero bone cost) and is only resized / repositioned when the camera crosses into a
new chunk. Its inner hole is aligned to the OUTER edge of the generated mesh block so the two
tile seamlessly; CalculateWaves already fades the rendered water to flat SEA_LEVEL at that
boundary, so the join is geometrically continuous. The outer edges are meant to terminate
inside fog / atmosphere rather than be seen directly
]]
local MAX_PART_SIZE = 2048 -- (studs) Roblox per-axis Part size limit
local HORIZON_EXTENT = 3000 -- (studs) how far each frame strip reaches outward (clamped to fit MAX_PART_SIZE)
local HORIZON_THICKNESS = 1 -- (studs) vertical thickness of the frame slabs
local HORIZON_COLOR = Color3.fromRGB(25, 60, 90)   -- matches the runtime sea colour
local HORIZON_MATERIAL = Enum.Material.SmoothPlastic

local HorizonParts: {Part} = {}
local lastHorizonChunkX: number? = nil
local lastHorizonChunkZ: number? = nil

local function CreateHorizonPart(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = HORIZON_MATERIAL
	p.Color = HORIZON_COLOR
	p.Parent = SeaFolder
	return p
end

-- Lazily creates / reuses frame part [index] and sets its footprint (centre + XZ size)
local function SetHorizonPart(index: number, centerX: number, centerZ: number, sizeX: number, sizeZ: number)
	local p = HorizonParts[index]
	if not p then
		p = CreateHorizonPart()
		HorizonParts[index] = p
	end
	p.Size = Vector3.new(sizeX, HORIZON_THICKNESS, sizeZ)
	-- top face sits exactly on SEA_LEVEL
	p.Position = Vector3.new(centerX, conf.SEA_LEVEL - HORIZON_THICKNESS / 2, centerZ)
end

--[[
Frames the generated mesh block with the 4-part horizon.
The parts are set into a pinwheel-style into four non-overlapping rectangles
(top / right / bottom / left), each grabbing one corner, so four parts cover
the whole ring with no gaps or overlaps
]]
local function UpdateHorizon(centerChunkX: number, centerChunkZ: number)
	if centerChunkX == lastHorizonChunkX and centerChunkZ == lastHorizonChunkZ then
		return
	end
	lastHorizonChunkX = centerChunkX
	lastHorizonChunkZ = centerChunkZ

	local genDistance = conf.RENDER_DISTANCE + conf.BORDER_BUFFER

	-- Inner hole = exact outer bounds of the generated mesh block, so frame and sea tile
	local x0 = (centerChunkX - genDistance) * MeshSize
	local x1 = (centerChunkX + genDistance + 1) * MeshSize
	local z0 = (centerChunkZ - genDistance) * MeshSize
	local z1 = (centerChunkZ + genDistance + 1) * MeshSize
	local innerW = x1 - x0
	local innerD = z1 - z0

	-- Clamp reach so no strip exceeds the 2048-stud Part limit (keeps the frame seamless)
	local E = math.max(0, math.min(HORIZON_EXTENT, MAX_PART_SIZE - math.max(innerW, innerD)))

	-- 1 top:    [x0-E, x1]  x [z1, z1+E]
	SetHorizonPart(1, (x0 - E + x1) / 2, z1 + E / 2, innerW + E, E)
	-- 2 right:  [x1, x1+E]  x [z0, z1+E]
	SetHorizonPart(2, x1 + E / 2, (z0 + z1 + E) / 2, E, innerD + E)
	-- 3 bottom: [x0, x1+E]  x [z0-E, z0]
	SetHorizonPart(3, (x0 + x1 + E) / 2, z0 - E / 2, innerW + E, E)
	-- 4 left:   [x0-E, x0]  x [z0-E, z1]
	SetHorizonPart(4, x0 - E / 2, (z0 - E + z1) / 2, E, innerD + E)
end

local function IsMeshVisible(mesh: MeshPart, camera: Camera): boolean
	local half = MeshSize / 2
	local pos = GetMeshPos(mesh)
	local camPos = camera.CFrame.Position
	local studRenderDist = conf.RENDER_DISTANCE * MeshSize
	
	if math.abs(camPos.X - pos.X) < half
		and math.abs(camPos.Z - pos.Z) < half
		and (pos - camPos).Magnitude < studRenderDist then
		if conf.DEBUG then mesh.Color = Color3.new(0, 1, 1) end
		VisibleMeshes[mesh] = true
		return true
	end

	local corners = {
		Vector3.new(pos.X - half, pos.Y, pos.Z - half),
		Vector3.new(pos.X + half, pos.Y, pos.Z - half),
		Vector3.new(pos.X - half, pos.Y, pos.Z + half),
		Vector3.new(pos.X + half, pos.Y, pos.Z + half),
	}
	for _, corner in ipairs(corners) do
		local screenPoint: Vector3, visible = camera:WorldToViewportPoint(corner)
		if visible and screenPoint.Z < studRenderDist then
			if conf.DEBUG then mesh.Color = Color3.new(0, 1, 1) end
			VisibleMeshes[mesh] = true
			return true
		end
	end

	--if conf.DEBUG then mesh.Color = Color3.new(1, 0, 0) end
	VisibleMeshes[mesh] = nil
	return false
end

local function IsMeshBorder(mesh: MeshPart): boolean
	local X: number = Meshes[mesh].Coords.X
	local Z: number = Meshes[mesh].Coords.Z

	if VisibleMeshes[mesh] then return false end
	
	for i= -1, 1 do
		for j= -1, 1 do
			
			if i == 0 and j == 0 then
				continue
			end
			
			if Chunks[X + i] and Chunks[X + i][Z + j] and VisibleMeshes[Chunks[X + i][Z + j]] then
				if conf.DEBUG then mesh.Color = Color3.new(1, 1, 0) end
				return true
			end
		end
	end
	
	--directly adjacect version (no diagonals)
	--[=[
	if Chunks[X] then
		if (Chunks[X][Z - 1] and VisibleMeshes[Chunks[X][Z - 1]])
			or (Chunks[X][Z + 1] and VisibleMeshes[Chunks[X][Z + 1]]) then
			if conf.DEBUG then mesh.Color = Color3.new(1, 1, 0) end
			return true
		end
	end
	if Chunks[X - 1] and Chunks[X - 1][Z] and VisibleMeshes[Chunks[X - 1][Z]] then
		if conf.DEBUG then mesh.Color = Color3.new(1, 1, 0) end
		return true
	end
	if Chunks[X + 1] and Chunks[X + 1][Z] and VisibleMeshes[Chunks[X + 1][Z]] then
		if conf.DEBUG then mesh.Color = Color3.new(1, 1, 0) end
		return true
	end

	]=]
	
	if conf.DEBUG then mesh.Color = Color3.new(1, 0, 0) end
	return false
end


--- / Module Functions /

function WavesModule.GenerateMeshes(GenerateAtPos: Vector3)
	local PosGridX = math.round((GenerateAtPos.X - MeshSize / 2) / MeshSize)
	local PosGridZ = math.round((GenerateAtPos.Z - MeshSize / 2) / MeshSize)
	local offset = MeshSize / 2
	local genDistance = conf.RENDER_DISTANCE + conf.BORDER_BUFFER
	local fakeLimit = genDistance * MeshSize * 1.1
	local fakeLimitSq = fakeLimit * fakeLimit

	-- Return out-of-range meshes to the pool
	-- Use chunk coords instead of mesh.Position to avoid instance property reads
	for x, chunksZ in Chunks do
		for z, mesh in chunksZ do
			local dx = (x - PosGridX) * MeshSize
			local dz = (z - PosGridZ) * MeshSize
			local outOfRange = if SPHERICAL_RENDERING
				then dx * dx + dz * dz > fakeLimitSq
				else math.abs(dx) > fakeLimit or math.abs(dz) > fakeLimit
			if outOfRange then
				PoolMesh(mesh)
			end
		end
	end

	-- Spawn or reuse meshes within range
	local fakeDistSq = (genDistance * MeshSize) ^ 2
	for x = -genDistance, genDistance do
		local chunkX = x + PosGridX
		Chunks[chunkX] = Chunks[chunkX] or {}

		for z = -genDistance, genDistance do
			if SPHERICAL_RENDERING and x * x + z * z > (genDistance * 1.2) ^ 2 then continue end
			local chunkZ = z + PosGridZ
			if Chunks[chunkX][chunkZ] then continue end

			-- Compute position
			local posX = chunkX * MeshSize + offset
			local posZ = chunkZ * MeshSize + offset

			if SPHERICAL_RENDERING then
				local dx = posX - GenerateAtPos.X
				local dz = posZ - GenerateAtPos.Z
				if dx * dx + dz * dz > fakeDistSq then continue end
			end

			local newMesh, newBones = GetMesh()
			newMesh.Position = Vector3.new(posX, conf.SEA_LEVEL, posZ)
			
			--classify bones for edge propagation
			local innerBones, edgeBones = ClassifyBones(newMesh, newBones)
			Meshes[newMesh] = {
				Bones = newBones,
				InnerBones = innerBones,
				EdgeBones = edgeBones,
				Coords = {X = chunkX, Z = chunkZ},
			}
			Chunks[chunkX][chunkZ] = newMesh
			
			--link bones
			if conf.EDGE_PROPAGATION then
				for offsetX = -1, 1 do
					for offsetY = -1, 1 do
						if offsetX == 0 and offsetY == 0 then continue end
						
						local neighborMesh = Chunks[chunkX + offsetX] and Chunks[chunkX + offsetX][chunkZ + offsetY]
						if neighborMesh then
							LinkNeighborBones(newMesh, neighborMesh)
						end
					end
				end
			end
			
		end
	end

	-- Keep the fake horizon framing the generated block (no-ops unless the chunk changed)
	UpdateHorizon(PosGridX, PosGridZ)
end



function WavesModule.ResetMeshes()
	for mesh, _ in Meshes do
		PoolMesh(mesh)
	end
end

function WavesModule.RenderWaves()
	CurrentUpdateCycle += 1
	local t = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local camPos = camera.CFrame.Position

	-- Precompute camera chunk coords once for Pass 2 distance checks
	local camChunkX = math.round((camPos.X - MeshSize / 2) / MeshSize)
	local camChunkZ = math.round((camPos.Z - MeshSize / 2) / MeshSize)

	-- Pass 1: Populate VisibleMeshes
	for mesh in Meshes do
		IsMeshVisible(mesh, camera)
	end

	-- Pass 2: Determine which meshes update this frame
	-- Use chunk coord delta instead of mesh.Position reads
	local UpdatingThisFrame: {[MeshPart]: boolean} = {}
	for mesh, meshData in Meshes do
		local cx = meshData.Coords.X
		local cz = meshData.Coords.Z
		local chunkDist =(cx - camChunkX) ^ 2 + (cz - camChunkZ) ^ 2
		if chunkDist <= conf.LOWERED_RENDER_RATE_DISTANCE ^ 2 then
			UpdatingThisFrame[mesh] = true
		else
			--[[
			Frames-between-updates scales with how many chunk-rings the mesh sits BEYOND
			the full-rate zone, so the falloff starts counting at LOWERED_RENDER_RATE_DISTANCE
			rather than at chunk 0. The boundary ring stays near every-frame and ramps out
			from there. max(1, ...) guarantees a valid (never zero/negative) modulo divisor
			]]
			local ringDist = math.round(math.sqrt(chunkDist))
			local interval = math.max(1, conf.RENDER_RATE_FALLOFF * (ringDist - conf.LOWERED_RENDER_RATE_DISTANCE))
			UpdatingThisFrame[mesh] = (CurrentUpdateCycle % interval == 0)
		end
	end

	-- Pass 3: Animate using cached local positions (no WorldPosition calls now)
	for mesh, meshData in Meshes do
		if not UpdatingThisFrame[mesh] then continue end

		local shouldAnimate = VisibleMeshes[mesh] or IsMeshBorder(mesh)
		local meshPos = GetMeshPos(mesh)

		if shouldAnimate then
			for i, bone in ipairs(meshData.Bones) do
				local worldPos = meshPos + SharedBonePositions[i]
				local dist = (camPos - worldPos).Magnitude
				local dx, dy, dz = CalculateWaves(worldPos.X, worldPos.Z, t, dist)
				bone.Transform = CFrame.new(dx, dy, dz)
			end
		else
			for _, bone in ipairs(meshData.Bones) do
				bone.Transform = CFrame.identity
			end
		end
		
		--[[
		Propagate edge bone transforms to linked neighbors after updating,
		whether animated or reset. This keeps seams (including 4-mesh corners) in
		sync without running any wave math on the skipped mesh
		]]
		if conf.EDGE_PROPAGATION then
			PropagateEdges(meshData)
		end
	end

	if CurrentUpdateCycle > 1000 then
		CurrentUpdateCycle = 0
	end
end


function WavesModule.GetWaterHeightAtPos(xPos: number, zPos:number): number
	local t = workspace:GetServerTimeNow()
	
	local dx, dy, dz = CalculateWaves(xPos, zPos, t, 0)
	return dy + conf.SEA_LEVEL
end

--[[
Applies a quality preset (or any partial settings table) onto the live config.
Only known, safe-to-change-at-runtime keys are copied; anything else is ignored.
Takes effect on the next GenerateMeshes / RenderWaves call.
]]
function WavesModule.ApplySettings(settings: WaveQualitySettings): boolean
	if type(settings) ~= "table" then return false end

	--[[
	A reset is only needed when EDGE_PROPAGATION flips: bone links have to be (re)built
	on the already-loaded meshes. Distance changes self-heal on the next GenerateMeshes
	call, and the rate settings are read fresh every frame, so neither needs a reset
	]]
	local needsReset = settings.EDGE_PROPAGATION ~= nil
		and settings.EDGE_PROPAGATION ~= conf.EDGE_PROPAGATION

	--[[
	A render-distance change resizes the generated block (and so the horizon's inner hole),
	so force the frame to rebuild on the next GenerateMeshes call
	]]
	if settings.RENDER_DISTANCE ~= nil and settings.RENDER_DISTANCE ~= conf.RENDER_DISTANCE then
		lastHorizonChunkX = nil
		lastHorizonChunkZ = nil
	end

	if settings.RENDER_DISTANCE ~= nil then conf.RENDER_DISTANCE = settings.RENDER_DISTANCE end
	if settings.LOWERED_RENDER_RATE_DISTANCE ~= nil then conf.LOWERED_RENDER_RATE_DISTANCE = settings.LOWERED_RENDER_RATE_DISTANCE end
	if settings.RENDER_RATE_FALLOFF ~= nil then conf.RENDER_RATE_FALLOFF = settings.RENDER_RATE_FALLOFF end
	if settings.EDGE_PROPAGATION ~= nil then conf.EDGE_PROPAGATION = settings.EDGE_PROPAGATION end

	return needsReset
end

--- / Module return /
return WavesModule
