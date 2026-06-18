--!strict
--!native

-- Module made by @Nano_Boo (discord) / @Nano_BooYT (Roblox)

--- / Module /
local WavesModule = {}

--- / SETTINGS /
local LINK_THRESHOLD = 0.5  -- (studs) bones closer than this are considered shared at a seam
local SPHERICAL_RENDERING = false --could cause problems if set to true (big spaces between meshes and horizon parts)

-- Check the github documentation buddy -> https://github.com/Nano-Boo23/NanosSampleCode/blob/main/Lua/GerstnerWavesOcean/README.md
-- There are more complete explanations in there about the module's public config
local conf = WavesModule --abbreviation purposes
conf.DEBUG = false

conf.WIND = Vector3.new(-10,0,10) --northeast
conf.SEA_LEVEL = 50 --(studs) at what Y level the mesh will generate at
conf.RENDER_DISTANCE = 2 --(chunks) the spherical radius that determines skinned mesh generation and rendering around the camera.
conf.LOWERED_RENDER_RATE_DISTANCE = 2 --(chunks) after what chunk the vertices get updated with less frequency
conf.RENDER_RATE_FALLOFF = 5 -- how many less updates a chunk gets proportional to current distance
conf.EDGE_PROPAGATION = false --propagates the positions of edge bones to adjacent meshes to prevent visible mesh tearing (not performance friendly though)
conf.BORDER_BUFFER = 1 --(chunks) extra ring of meshes generated just beyond RENDER_DISTANCE.

conf.WAVES = {
	{direction = {X = -2.0,	Z = 1.0},	amplitude = 9.9,	speed = 0.01,	wavelength = 400,	steepness = 0.1},
	{direction = {X = -1.0,	Z = -10.0},	amplitude = 1.2,	speed = 0.15,	wavelength = 80,	steepness = 0.1},
	{direction = {X = 9.4,	Z = -3.0},	amplitude = 0.2,	speed = 0.3,	wavelength = 12,	steepness = 0.6},
} :: {GerstnerWave}
--direction: direction of the wave on the XZ plane
--amplitude: height of the wave
--wavelength: width of the wave
--speed: frequency of the wave (how fast it completes a cycle)
--steepness: how circular the particle orbit is. 0 = pure sine wave. 1 = sharpest possible Gerstner peak.

--- / Types /
type WaveQualitySettings = {
	RENDER_DISTANCE: number?,
	LOWERED_RENDER_RATE_DISTANCE: number?,
	RENDER_RATE_FALLOFF: number?,
	EDGE_PROPAGATION: boolean?,
}

type GerstnerWave = {
	direction: {X: number, Z: number},
	amplitude: number,
	wavelength: number,
	speed: number,
	steepness: number,
}
type PrecomputedWave = {
	c: number,
	amplitude: number,
	kDirX: number,
	kDirZ: number,
	aDirX: number,
	aDirZ: number,
	phase: number
}
type EdgeBones = {minX: {Bone}, maxX: {Bone}, minZ: {Bone}, maxZ: {Bone}}
type MeshData = {
	Bones: {Bone},
	EdgeBones: EdgeBones,
	Coords: {X: number, Z: number},
	WorldPos: Vector3
}

type Meshes = {[MeshPart]: MeshData}
type PooledMeshes = {[MeshPart]: {Bones: {Bone}, EdgeBones: EdgeBones}}


--- / Variables /
local BaseMesh: MeshPart = script:WaitForChild("SeaMesh")
local BaseHorizonMesh: MeshPart = script:WaitForChild("HorizonMesh")
local SeaModel: Model = workspace:WaitForChild("Sea")
local CurrentUpdateCycle = 0
local MeshSize = BaseMesh.Size.X
local HalfMeshSize = MeshSize / 2

local Meshes: Meshes = {}
local PooledMeshes: PooledMeshes = {}
local Chunks: {[number]: {[number]: MeshPart}} = {}
local VisibleMeshes: {[MeshPart]: true?} = {}
local UpdatingThisFrame: {[MeshPart]: boolean} = {} -- table used in RenderWaves()
local PrecomputedWaves:{PrecomputedWave} = {}
local BoneLinks: {[Bone]: {Bone}} = {} --1-to-many bone links: a bone on one mesh -> list of matching bones on neighboring meshes
local HorizonParts: {MeshPart} = {}
local lastHorizonChunkX: number? = nil
local lastHorizonChunkZ: number? = nil
local OriginalMeshColor = BaseMesh.Color
local StudRenderDist = conf.RENDER_DISTANCE * MeshSize --non nil init
local BoneUpdates:{[Bone]: CFrame} = {}
local ShouldAnimate:{[MeshPart]: boolean} = {}

--mapping to reduce needed calculations and lookups. :GetChildren()'s order is consistent, as long as we dont add instances. (which we dont)
local SharedBonePositions: {Vector3} = {}
local NameToIndex: {[string]: number} = {}
do
	local i = 0
	for _, child in ipairs(BaseMesh:GetChildren()) do
		if child:IsA("Bone") then
			i += 1
			SharedBonePositions[i] = child.Position
			NameToIndex[child.Name] = i
		end
	end
end
table.freeze(SharedBonePositions)
table.freeze(NameToIndex)

-- Hard-coded table for fast edge bone lookups. Tracks what bones are in each edges.
local BoneEdgeOwnership = {
	-- sorted Z ascending (-50 -> 50)
	maxX = {"0","12","11","10","9","8","7","6","5","4","2"},
	minX = {"1","22","23","24","25","26","27","28","29","30","3"},
	-- sorted X ascending (-50 -> 50)
	maxZ = {"3","31","32","33","34","35","36","37","38","39","2"},
	minZ = {"1","21","20","19","18","17","16","15","14","13","0"},
}
table.freeze(BoneEdgeOwnership)

local EdgeBoneIndices: {[string]: {number}} = {}
for edgeKey, names in BoneEdgeOwnership :: {[string]: {string}} do
	local idxList = {}
	for _, name in ipairs(names) do
		table.insert(idxList, NameToIndex[name])  -- name -> array index
	end
	EdgeBoneIndices[edgeKey] = idxList
end
table.freeze(EdgeBoneIndices)

-- quick check
if BaseMesh.Size.X ~= BaseMesh.Size.Z then
	warn(`BaseMesh is not a square: {BaseMesh.Size.X},{BaseMesh.Size.Z}`)
end




--- / Local Functions /

local function GetEdgeBones(bones: {Bone}): EdgeBones
	local edge: EdgeBones = {minX = {}, maxX = {}, minZ = {}, maxZ = {}}
	for edgeKey, idxList in EdgeBoneIndices do
		local out = (edge :: any)[edgeKey]
		for _, idx in ipairs(idxList) do
			table.insert(out, bones[idx])
		end
	end
	return edge
end

local function GetWindBiasedDirection(baseDir: {X: number, Z: number}): Vector2
	local GlobalWind = conf.WIND
	if GlobalWind.Magnitude < 0.1 then return Vector2.new(baseDir.X,baseDir.Z) end
	local windDir = Vector2.new(GlobalWind.X, GlobalWind.Z).Unit
	return (Vector2.new(baseDir.X,baseDir.Z) + windDir * 0.6).Unit
end

--[[ old function (documentation purposes)
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
]]

local function CalculateWaves(x: number, z: number): (number, number, number)
	local totalDX, totalDY, totalDZ = 0, 0, 0
	
	for i = 1, #PrecomputedWaves do
		local w = PrecomputedWaves[i]
		local f = w.kDirX * x + w.kDirZ * z - w.phase
		local cosf = math.cos(f)
		totalDX += w.aDirX * cosf
		totalDY += w.amplitude * math.sin(f)
		totalDZ += w.aDirZ * cosf
	end
	
	return totalDX, totalDY, totalDZ
end

--[[
Links spatially coincident edge bones between two meshes.
Uses a list per bone so that corner bones (shared by 4 meshes) link to all 3 partners
]]
local function LinkNeighborBones(meshA: MeshPart, meshB: MeshPart)
	local dataA = Meshes[meshA]
	local dataB = Meshes[meshB]
	if not dataA or not dataB then return end

	local posA = dataA.WorldPos
	local posB = dataB.WorldPos
	local edgesA = dataA.EdgeBones
	local edgesB = dataB.EdgeBones

	-- Flatten B's edge bones + cached world rest positions ONCE (no .Position reads)
	local bBones: {Bone} = {}
	local bWorld: {Vector3} = {}
	local n = 0
	for edgeKey, _ in BoneEdgeOwnership :: {[string]: {any}} do
		local idxList = EdgeBoneIndices[edgeKey]
		local listB = (edgesB :: any)[edgeKey]
		for j = 1, #idxList do
			n += 1
			bBones[n] = listB[j]
			bWorld[n] = posB + SharedBonePositions[idxList[j]]
		end
	end

	for edgeKey, _ in BoneEdgeOwnership :: {[string]: {any}} do
		local idxList = EdgeBoneIndices[edgeKey]
		local listA = (edgesA :: any)[edgeKey]
		for j = 1, #idxList do
			local boneA = listA[j]
			local worldPosA = posA + SharedBonePositions[idxList[j]]
			for k = 1, n do
				if (worldPosA - bWorld[k]).Magnitude < LINK_THRESHOLD then
					local boneB = bBones[k]
					local la = BoneLinks[boneA]; if not la then la = {}; BoneLinks[boneA] = la end
					table.insert(la, boneB)
					local lb = BoneLinks[boneB]; if not lb then lb = {}; BoneLinks[boneB] = lb end
					table.insert(lb, boneA)
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
	for _, bone in ipairs(meshData.Bones) do
		bone.Transform = CFrame.identity
	end
	UnlinkBones(mesh)
	PooledMeshes[mesh] = {Bones = meshData.Bones, EdgeBones = meshData.EdgeBones}
	Meshes[mesh] = nil
	Chunks[meshData.Coords.X][meshData.Coords.Z] = nil
	if next(Chunks[meshData.Coords.X]) == nil then
		Chunks[meshData.Coords.X] = nil --clear x coords if that was the last one in Z axis
	end
	VisibleMeshes[mesh] = nil
	mesh.Transparency = 1
end

local function GetMesh(): (MeshPart, {Bone}, EdgeBones)
	local m = next(PooledMeshes)
	local bones: {Bone} = {}
	local edgeBones: EdgeBones

	if m then
		bones = PooledMeshes[m].Bones
		edgeBones = PooledMeshes[m].EdgeBones
		PooledMeshes[m] = nil
		m.Transparency = 0
	else
		m = BaseMesh:Clone()
		m.Parent = SeaModel
		for _, obj in m:GetChildren() do
			if obj:IsA("Bone") then
				table.insert(bones, obj)
			end
		end
		edgeBones = GetEdgeBones(bones)
	end

	assert(m)
	
	return m, bones, edgeBones
end

local function CreateHorizonPart(): MeshPart
	local p = BaseHorizonMesh:Clone()
	p.Parent = SeaModel
	return p
end

-- Lazily creates / reuses frame part [index] and sets its footprint (centre + XZ size)
local function SetHorizonPart(index: number, centerX: number, centerZ: number, sizeX: number, sizeZ: number)
	local p = HorizonParts[index]
	if not p then
		p = CreateHorizonPart()
		HorizonParts[index] = p
	end
	p.Size = Vector3.new(sizeX, 0.001, sizeZ)
	-- top face sits exactly on SEA_LEVEL
	p.Position = Vector3.new(centerX, conf.SEA_LEVEL, centerZ)
end

--[[
Frames the generated mesh block with the 4-part horizon.
The parts are set into a pinwheel-style into four non-overlapping rectangles
(top / right / bottom / left), each grabbing one corner, so four parts cover
the whole ring with no gaps or overlaps
]]
local MAX_PART_SIZE = 2048 -- (studs) Roblox's part size limit
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

	local E = math.max(0, MAX_PART_SIZE - math.max(innerW, innerD))

	-- 1 top:    [x0-E, x1]  x [z1, z1+E]
	SetHorizonPart(1, (x0 - E + x1) / 2, z1 + E / 2, innerW + E, E)
	-- 2 right:  [x1, x1+E]  x [z0, z1+E]
	SetHorizonPart(2, x1 + E / 2, (z0 + z1 + E) / 2, E, innerD + E)
	-- 3 bottom: [x0, x1+E]  x [z0-E, z0]
	SetHorizonPart(3, (x0 + x1 + E) / 2, z0 - E / 2, innerW + E, E)
	-- 4 left:   [x0-E, x0]  x [z0-E, z1]
	SetHorizonPart(4, x0 - E / 2, (z0 - E + z1) / 2, E, innerD + E)
end

local function IsMeshVisible(mesh: MeshPart, camera: Camera, camPos: Vector3): boolean
	local pos = Meshes[mesh].WorldPos

	if math.abs(camPos.X - pos.X) < HalfMeshSize
		and math.abs(camPos.Z - pos.Z) < HalfMeshSize
		and (pos - camPos).Magnitude < StudRenderDist then
		VisibleMeshes[mesh] = true
		return true
	end

	local corners = {
		Vector3.new(pos.X - HalfMeshSize, pos.Y, pos.Z - HalfMeshSize),
		Vector3.new(pos.X + HalfMeshSize, pos.Y, pos.Z - HalfMeshSize),
		Vector3.new(pos.X - HalfMeshSize, pos.Y, pos.Z + HalfMeshSize),
		Vector3.new(pos.X + HalfMeshSize, pos.Y, pos.Z + HalfMeshSize),
	}
	for _, corner in ipairs(corners) do
		local screenPoint: Vector3, visible = camera:WorldToViewportPoint(corner)
		if visible and screenPoint.Z < StudRenderDist then
			VisibleMeshes[mesh] = true
			return true
		end
	end

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
				return true
			end
		end
	end

	--directly adjacect version (no diagonals) (documentation purposes)
	--[=[
	if Chunks[X] then
		if (Chunks[X][Z - 1] and VisibleMeshes[Chunks[X][Z - 1]])
			or (Chunks[X][Z + 1] and VisibleMeshes[Chunks[X][Z + 1]]) then
			return true
		end
	end
	if Chunks[X - 1] and Chunks[X - 1][Z] and VisibleMeshes[Chunks[X - 1][Z]] then
		return true
	end
	if Chunks[X + 1] and Chunks[X + 1][Z] and VisibleMeshes[Chunks[X + 1][Z]] then
		return true
	end

	]=]

	return false
end


--- / Module Functions /

function WavesModule.GenerateMeshes(GenerateAtPos: Vector3)
	debug.profilebegin("GENERATE MESHES SERIAL")
	local PosGridX = math.round((GenerateAtPos.X - HalfMeshSize) / MeshSize)
	local PosGridZ = math.round((GenerateAtPos.Z - HalfMeshSize) / MeshSize)
	local genDistance = conf.RENDER_DISTANCE + conf.BORDER_BUFFER
	local fakeLimit = genDistance * MeshSize * 1.1
	local fakeLimitSq = fakeLimit * fakeLimit

	-- Return out-of-range meshes to the pool
	-- Use chunk coords instead of mesh.Position to avoid instance property reads
	debug.profilebegin("POOL OUT OF RANGE MESHES")
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
	debug.profileend()

	-- Spawn or reuse meshes within range
	debug.profilebegin("SPAWN/REUSE MESHES")
	for x = -genDistance, genDistance do
		local chunkX = x + PosGridX
		Chunks[chunkX] = Chunks[chunkX] or {}

		for z = -genDistance, genDistance do
			if SPHERICAL_RENDERING and x * x + z * z > (genDistance * 1.2) ^ 2 then continue end
			local chunkZ = z + PosGridZ
			if Chunks[chunkX][chunkZ] then continue end

			-- Compute position
			local worldPosX = chunkX * MeshSize + HalfMeshSize
			local worldPosZ = chunkZ * MeshSize + HalfMeshSize

			if SPHERICAL_RENDERING then
				local fakeDistSq = (genDistance * MeshSize) ^ 2
				local dx = worldPosX - GenerateAtPos.X
				local dz = worldPosZ - GenerateAtPos.Z
				if dx * dx + dz * dz > fakeDistSq then continue end
			end

			local newMesh, newBones, newEdgeBones = GetMesh()
			newMesh.Position = Vector3.new(worldPosX, conf.SEA_LEVEL, worldPosZ)

			--classify bones for edge propagation
			Meshes[newMesh] = {
				Bones = newBones,
				EdgeBones = newEdgeBones,
				Coords = {X = chunkX, Z = chunkZ},
				WorldPos = Vector3.new(
					worldPosX,
					conf.SEA_LEVEL,
					worldPosZ
				)
			}
			Chunks[chunkX][chunkZ] = newMesh

			--link bones
			if conf.EDGE_PROPAGATION then
				for offsetX = -1, 1 do
					for offsetZ = -1, 1 do
						if offsetX == 0 and offsetZ == 0 then continue end

						local neighborMesh = Chunks[chunkX + offsetX] and Chunks[chunkX + offsetX][chunkZ + offsetZ]
						if neighborMesh then
							LinkNeighborBones(newMesh, neighborMesh)
						end
					end
				end
			end

		end
	end
	debug.profileend()

	-- Keep the fake horizon framing the generated block
	debug.profilebegin("UPDATE HORIZON")
	UpdateHorizon(PosGridX, PosGridZ)
	debug.profileend()
	
	debug.profileend()
end



function WavesModule.ResetMeshes()
	for mesh, _ in Meshes do
		PoolMesh(mesh)
		mesh.Color = OriginalMeshColor
	end
end

function WavesModule.RenderWaves()
	task.desynchronize()
	debug.profilebegin("RENDER WAVES PARALLEL")
	StudRenderDist = conf.RENDER_DISTANCE * MeshSize
	CurrentUpdateCycle += 1
	local t = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local camPos = camera.CFrame.Position

	-- Precompute camera chunk coords once for Pass 2 distance checks
	local camChunkX = math.round((camPos.X - HalfMeshSize) / MeshSize)
	local camChunkZ = math.round((camPos.Z - HalfMeshSize) / MeshSize)
	
	-- precompute wave phase
	for i = 1, #PrecomputedWaves do
		PrecomputedWaves[i].phase = PrecomputedWaves[i].c * t
	end
	
	-- Pass 1: Determine which meshes are visible and update this frame
	-- Use chunk coord delta instead of mesh.Position reads
	debug.profilebegin("MESH VISIBILITY & SHOULD UPDATE CHECK")
	table.clear(UpdatingThisFrame)
	local squaredDist = conf.LOWERED_RENDER_RATE_DISTANCE ^ 2
	for mesh, meshData in Meshes do
		IsMeshVisible(mesh, camera, camPos) -- Populate VisibleMeshes
		
		local cx = meshData.Coords.X
		local cz = meshData.Coords.Z
		local chunkDist =(cx - camChunkX) ^ 2 + (cz - camChunkZ) ^ 2
		if chunkDist <= squaredDist then
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
	debug.profileend()
	
	-- Pass 2: Animate using cached local positions
	debug.profilebegin("CALCULATING BONE POS")
	table.clear(BoneUpdates)
	table.clear(ShouldAnimate)
	local fadeStart = (conf.RENDER_DISTANCE + conf.BORDER_BUFFER) * HalfMeshSize
	local fadeEnd = (conf.RENDER_DISTANCE + conf.BORDER_BUFFER) * MeshSize
	for mesh, meshData in Meshes do
		if not UpdatingThisFrame[mesh] then continue end

		ShouldAnimate[mesh] = VisibleMeshes[mesh] or IsMeshBorder(mesh)
		local meshPos = meshData.WorldPos

		if ShouldAnimate[mesh] then
			for i, bone in ipairs(meshData.Bones) do
				local worldPos = meshPos + SharedBonePositions[i]
				local dist = (camPos - worldPos).Magnitude
				local fade = math.clamp(1 - ((dist - fadeStart) / (fadeEnd - fadeStart)), 0, 1)
				local dx, dy, dz = CalculateWaves(worldPos.X, worldPos.Z)
				BoneUpdates[bone] = CFrame.new(dx * fade, dy * fade, dz * fade)
			end
		end
		
	end
	debug.profileend()
	
	debug.profileend()
	task.synchronize()
	debug.profilebegin("RENDER WAVES SERIAL")
	
	-- Pass 3: Apply bone updates
	debug.profilebegin("SET BONE POS")
	--set color if debug is true
	if conf.DEBUG then
		for mesh, _ in Meshes do
			mesh.Color = if VisibleMeshes[mesh] then Color3.new(0,1,1)
				elseif IsMeshBorder(mesh) then Color3.new(1,1,0)
				else Color3.new(1, 0, 0)
		end
	end
	
	for bone, cframe in BoneUpdates do
		bone.Transform = cframe
	end
	debug.profileend()
	
	-- Pass 4: Propagate position to border bones
	debug.profilebegin("PROPAGATION UPDATE")
	if conf.EDGE_PROPAGATION then
		for mesh, animate in ShouldAnimate do
			if animate then
				PropagateEdges(Meshes[mesh])
			end
		end
	end
	debug.profileend()
	
	if CurrentUpdateCycle > 1000 then
		CurrentUpdateCycle = 0
	end
	debug.profileend()
end

function WavesModule.GetWaterHeightAtPos(xPos: number, zPos:number): number
	local t = workspace:GetServerTimeNow()
	
	-- precompute wave phase
	for i = 1, #PrecomputedWaves do
		PrecomputedWaves[i].phase = PrecomputedWaves[i].c * t
	end
	
	--[[
	Gerstner waves move points sideways as well as up/down, so the vertex that actually sits
	above (xPos, zPos) is NOT the one whose REST position is (xPos, zPos). Invert the horizontal
	displacement with a few fixed-point steps to find the right one. Converges quickly while the
	combined steepness stays below ~1; above that the surface self-intersects and is multivalued
	]]
	local gx, gz = xPos, zPos
	for _ = 1, 8 do
		local dx, _, dz = CalculateWaves(gx, gz)
		gx = xPos - dx
		gz = zPos - dz
	end

	local _, dy = CalculateWaves(gx, gz)
	return dy + conf.SEA_LEVEL
end

function WavesModule.RecomputeWaves()
	table.clear(PrecomputedWaves)
	
	for _, wave in ipairs(conf.WAVES) do
		local k = (2 * math.pi) / wave.wavelength
		local c = math.sqrt(9.8 / k) * wave.speed
		local a = wave.steepness / k
		local dir = GetWindBiasedDirection(wave.direction)
		table.insert(PrecomputedWaves, {
			c = c, amplitude = wave.amplitude,
			kDirX = k * dir.X, kDirZ = k * dir.Y,
			aDirX = a * dir.X, aDirZ = a * dir.Y,
			phase = 0,  -- refreshed once per frame
		})
	end
end
WavesModule.RecomputeWaves() --trigger at least once to set up variables

--[[
Applies a quality preset (or any partial settings table) onto the live config.
Only known, safe-to-change-at-runtime keys are copied; anything else is ignored.
Takes effect on the next GenerateMeshes / RenderWaves call.
]]
function WavesModule.ApplySettings(settings: WaveQualitySettings)
	if type(settings) ~= "table" then return end

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
	
	WavesModule.RecomputeWaves()
	
	if needsReset then
		WavesModule.ResetMeshes()
	end
end

--- / Module return /
return WavesModule
