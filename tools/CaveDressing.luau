-- Cave dressing: gives each DigSite stage's cave a material that fits its Theme attribute and adds detail
-- blocks to the inside of its walls and ceiling, so the caves look rough and alive instead of flat.
-- Edit-time tool, not part of the running game: paste it into Studio's Command Bar and press Enter.
--
--   MODE = "preview"  prints what would change; changes nothing
--   MODE = "apply"    restyles the caves (running it again rebuilds the same result)
--   MODE = "undo"     puts every original material back and removes all detail blocks
--
-- Detail blocks live in Workspace.CaveDetail, outside DigSite, and can't be touched, collided with or hit by
-- raycasts, so the break, skip-stage and loot systems never see them. They stay clear of anything else in the
-- stage (gates, candles, decorations, loot spawns) and are never put on floors. Restyled parts keep their
-- original physics (friction, density), so walking on them feels exactly the same.
local MODE = "preview"
local DETAIL_AMOUNT = 1 -- 0.5 = half as many detail blocks, 2 = twice as many

-- Wall material and accent blocks for each Theme attribute used in DigSite.
-- Accent shapes: "chunk" rock, "vein" thin glowing crack, "shard" crystal sticking out, "speck" tiny dot,
-- "patch" flat moss. chance = share of detail blocks that are accents.
local THEMES = {
	Dirt = { material = "Ground", accent = { material = "Rock", shape = "chunk", chance = 0.15, colors = { "7a6a5a", "8c7b69" } } },
	Stone = { material = "Rock", accent = { material = "Pebble", shape = "chunk", chance = 0.15, colors = { "9a9eae", "b4b8c6" } } },
	Ice = { material = "Glacier", accent = { material = "Neon", shape = "shard", chance = 0.12, colors = { "78e6ff", "c8f5ff" } } },
	Jungle = { material = "Cobblestone", accent = { material = "LeafyGrass", shape = "patch", chance = 0.25, colors = { "5aa050", "3c8c3c" } } },
	Desert = { material = "Sandstone", accent = { material = "Sandstone", shape = "vein", chance = 0.2, colors = { "a07d46", "e8c478" } } },
	Lava = { material = "Basalt", accent = { material = "Neon", shape = "vein", chance = 0.2, colors = { "ff5a1e", "ff8c28" } } },
	Crystal = { material = "Marble", accent = { material = "Neon", shape = "shard", chance = 0.12, colors = { "dc78ff", "aa78e6" } } },
	Candy = { material = "Salt", accent = { material = "SmoothPlastic", shape = "chunk", chance = 0.2, colors = { "ffffff", "ff78c8", "a0dcff" } } },
	Ocean = { material = "Limestone", accent = { material = "Neon", shape = "speck", chance = 0.15, colors = { "78fff0", "3cc8c8" } } },
	Obsidian = { material = "Slate", accent = { material = "Neon", shape = "vein", chance = 0.12, colors = { "ff5ac8", "aa50ff" } } },
	Gold = { material = "Foil", accent = { material = "Neon", shape = "speck", chance = 0.2, colors = { "ffd23c", "fff5aa" } } },
	Toxic = { material = "Mud", accent = { material = "Neon", shape = "vein", chance = 0.15, colors = { "aaff28", "e6ff78" } } },
	Snow = { material = "Snow", accent = { material = "Ice", shape = "shard", chance = 0.2, colors = { "c8f0ff", "e6f8ff" } } },
	Emerald = { material = "Granite", accent = { material = "Neon", shape = "shard", chance = 0.12, colors = { "28ff96", "b4ffdc" } } },
	Galaxy = { material = "Asphalt", accent = { material = "Neon", shape = "speck", chance = 0.3, colors = { "ffffff", "78c8ff", "ff78dc" } } },
}

local WALL_AREA_PER_BLOCK = 30 -- studs² of wall per detail block, before DETAIL_AMOUNT
local CEILING_AREA_PER_BLOCK = 40
local CLEARANCE = 0.5 -- gap kept between detail blocks and anything else in the stage
local ORIGINAL_MATERIAL = "CaveDressingMaterial" -- attribute: the material a part had before dressing
local SET_PHYSICS = "CaveDressingPhysics" -- attribute: dressing set CustomPhysicalProperties on this part

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

local function component(vector, axis)
	return if axis == 1 then vector.X elseif axis == 2 then vector.Y else vector.Z
end

local function vectorOf(values)
	return Vector3.new(values[1], values[2], values[3])
end

-- width, height and how far it sticks out of the wall
local function shapeSize(shape, rng)
	if shape == "hang" then
		return rng:NextNumber(1.2, 3), rng:NextNumber(1.2, 3), rng:NextNumber(0.5, 2.5)
	elseif shape == "vein" then
		local long, thin = rng:NextNumber(2.5, 6), rng:NextNumber(0.4, 0.8)
		if rng:NextNumber() < 0.5 then
			return long, thin, rng:NextNumber(0.1, 0.3)
		end
		return thin, long, rng:NextNumber(0.1, 0.3)
	elseif shape == "shard" then
		return rng:NextNumber(0.6, 1.4), rng:NextNumber(0.6, 1.4), rng:NextNumber(0.8, 2.2)
	elseif shape == "speck" then
		local size = rng:NextNumber(0.3, 0.7)
		return size, size, rng:NextNumber(0.1, 0.3)
	elseif shape == "patch" then
		return rng:NextNumber(2, 5), rng:NextNumber(2, 5), rng:NextNumber(0.1, 0.35)
	end
	return rng:NextNumber(1.5, 4), rng:NextNumber(1.5, 4), rng:NextNumber(0.2, 1)
end

local function shade(color, rng)
	if rng:NextNumber() < 0.6 then
		return color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.05, 0.25))
	end
	return color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0.03, 0.12))
end

-- the cave body of a stage: every part of its Shell, plus Stage_01's shaft walls.
-- Returns { part, center of the room it faces } pairs, and the stage's other parts that detail must avoid.
local function caveOf(stage)
	local surfaces, blockers = {}, {}
	for _, child in stage:GetChildren() do
		if child.Name == "Shell" or child.Name == "Shaft" then
			local center = child:GetBoundingBox().Position
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					if child.Name == "Shell" or d.Name == "ShaftWall" then
						table.insert(surfaces, { d, center })
					else
						table.insert(blockers, d)
					end
				end
			end
		else
			table.insert(blockers, child)
		end
	end
	return surfaces, blockers
end

local function planFace(part, center, theme, rng, overlap, blocks)
	local size = part.Size
	local dims = { size.X, size.Y, size.Z }
	local thin = 1
	for axis = 2, 3 do
		if dims[axis] < dims[thin] then
			thin = axis
		end
	end
	local u, v = thin % 3 + 1, (thin + 1) % 3 + 1
	if dims[thin] > 4 or dims[u] < 6 or dims[v] < 6 then
		return -- trim or pillar, not a wall or ceiling slab
	end
	local side = if component(part.CFrame:PointToObjectSpace(center), thin) >= 0 then 1 else -1
	local normal = part.CFrame:VectorToWorldSpace(AXES[thin] * side)
	if normal.Y > 0.7 then
		return -- a floor: walking surfaces stay clear
	end
	local ceiling = normal.Y < -0.7
	local areaPerBlock = if ceiling then CEILING_AREA_PER_BLOCK else WALL_AREA_PER_BLOCK
	local count = math.floor(dims[u] * dims[v] / areaPerBlock * DETAIL_AMOUNT + rng:NextNumber())

	for _ = 1, count do
		local accent = if theme.accent and rng:NextNumber() < theme.accent.chance then theme.accent else nil
		local shape = if accent then accent.shape elseif ceiling then "hang" else "chunk"
		local width, height, out = shapeSize(shape, rng)
		if width > dims[u] or height > dims[v] then
			continue
		end
		local depth = out + math.min(rng:NextNumber(0.3, 0.8), dims[thin] * 0.45)
		local offset, blockSize = {}, {}
		offset[thin], blockSize[thin] = side * (dims[thin] / 2 + out - depth / 2), depth
		offset[u], blockSize[u] = rng:NextNumber(-(dims[u] - width) / 2, (dims[u] - width) / 2), width
		offset[v], blockSize[v] = rng:NextNumber(-(dims[v] - height) / 2, (dims[v] - height) / 2), height

		local cframe = part.CFrame * CFrame.new(vectorOf(offset))
		local sizeVector = vectorOf(blockSize)
		if #workspace:GetPartBoundsInBox(cframe, sizeVector + Vector3.one * CLEARANCE * 2, overlap) > 0 then
			continue -- would cover a gate, candle, decoration or sign
		end
		table.insert(blocks, {
			cframe = cframe,
			size = sizeVector,
			material = if accent then accent.material else theme.material,
			color = if accent
				then Color3.fromHex(accent.colors[rng:NextInteger(1, #accent.colors)])
				else shade(part.Color, rng),
			accent = accent ~= nil,
		})
	end
end

local function buildPlan(digSite)
	local plan = {}
	for _, stage in digSite:GetChildren() do
		local themeName = stage:GetAttribute("Theme")
		if themeName == nil then
			continue
		end
		local theme = THEMES[themeName]
		if not theme then
			warn(`{stage.Name}: no look defined for Theme "{themeName}", skipped`)
			continue
		end
		local surfaces, blockers = caveOf(stage)
		local surfaceBreak = workspace:FindFirstChild("break")
		if surfaceBreak then
			table.insert(blockers, surfaceBreak)
		end
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = blockers

		local stageNumber = stage:GetAttribute("Stage") or 0
		local parts, blocks = {}, {}
		for _, entry in surfaces do
			local part, center = entry[1], entry[2]
			table.insert(parts, part)
			local p = part.Position
			local rng = Random.new(stageNumber * 100003 + math.floor(p.X * 31 + p.Y * 17 + p.Z * 7))
			planFace(part, center, theme, rng, overlap, blocks)
		end
		table.insert(plan, { stage = stage, themeName = themeName, theme = theme, parts = parts, blocks = blocks })
	end
	table.sort(plan, function(a, b)
		return (a.stage:GetAttribute("Stage") or 0) < (b.stage:GetAttribute("Stage") or 0)
	end)
	return plan
end

local function report(plan)
	local totalParts, totalBlocks = 0, 0
	for _, stagePlan in plan do
		local accents = 0
		for _, block in stagePlan.blocks do
			if block.accent then
				accents += 1
			end
		end
		totalParts += #stagePlan.parts
		totalBlocks += #stagePlan.blocks
		print(
			`{stagePlan.stage.Name} ({stagePlan.themeName}): {#stagePlan.parts} parts -> {stagePlan.theme.material}, `
				.. `{#stagePlan.blocks} detail blocks ({accents} {stagePlan.theme.accent.material} accents)`
		)
	end
	print(`Total: {#plan} caves, {totalParts} parts restyled, {totalBlocks} detail blocks`)
end

local function apply(plan)
	local old = workspace:FindFirstChild("CaveDetail")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "CaveDetail"
	for _, stagePlan in plan do
		for _, part in stagePlan.parts do
			if part:GetAttribute(ORIGINAL_MATERIAL) == nil then
				part:SetAttribute(ORIGINAL_MATERIAL, part.Material.Name)
				if part.CustomPhysicalProperties == nil then
					part.CustomPhysicalProperties = PhysicalProperties.new(part.Material) -- keep the old feel
					part:SetAttribute(SET_PHYSICS, true)
				end
			end
			part.Material = Enum.Material[stagePlan.theme.material]
		end

		local folder = Instance.new("Folder")
		folder.Name = stagePlan.stage.Name
		for _, block in stagePlan.blocks do
			local detail = Instance.new("Part")
			detail.Name = if block.accent then "Accent" else "Detail"
			detail.Anchored = true
			detail.CanCollide = false
			detail.CanTouch = false
			detail.CanQuery = false
			detail.CastShadow = false
			detail.Locked = true -- clicking a wall in Studio selects the wall, not its detail
			detail.Material = Enum.Material[block.material]
			detail.Color = block.color
			detail.Size = block.size
			detail.CFrame = block.cframe
			detail.Parent = folder
		end
		folder.Parent = root
	end
	root.Parent = workspace
end

local function undo(digSite)
	local restored = 0
	for _, d in digSite:GetDescendants() do
		local original = d:IsA("BasePart") and d:GetAttribute(ORIGINAL_MATERIAL)
		if original then
			d.Material = Enum.Material[original]
			if d:GetAttribute(SET_PHYSICS) then
				d.CustomPhysicalProperties = nil
			end
			d:SetAttribute(ORIGINAL_MATERIAL, nil)
			d:SetAttribute(SET_PHYSICS, nil)
			restored += 1
		end
	end
	local detail = workspace:FindFirstChild("CaveDetail")
	if detail then
		detail:Destroy()
	end
	print(`Undo: {restored} parts back to their original material, detail blocks removed`)
end

local digSite = workspace:FindFirstChild("DigSite")
if not digSite then
	warn("CaveDressing: Workspace.DigSite not found, nothing done")
elseif MODE == "preview" then
	report(buildPlan(digSite))
	print("Preview only: nothing was changed. Set MODE to \"apply\" to make these changes.")
elseif MODE == "apply" or MODE == "undo" then
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	local ok, recording = pcall(ChangeHistoryService.TryBeginRecording, ChangeHistoryService, `CaveDressing {MODE}`)
	if MODE == "apply" then
		local plan = buildPlan(digSite)
		apply(plan)
		report(plan)
		print("Applied. Undo with Ctrl+Z, or run this script again with MODE = \"undo\".")
	else
		undo(digSite)
	end
	if ok and recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
else
	warn(`CaveDressing: unknown MODE "{MODE}", use "preview", "apply" or "undo"`)
end
