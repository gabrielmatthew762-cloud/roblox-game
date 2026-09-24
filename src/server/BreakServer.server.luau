-- Server side of the break system: checks each hit, keeps every player's damage on every block and breaks it at MaxHealth.
-- Breaking uses the same per-player progress as Skip Stage, so SkipStageClient hides (and shatters) the block for that
-- player only:  gate -> ClearedStage = its Stage,  surface layer -> BrokenLayers = its BreakLayer (last layer -> ClearedStage 1).
-- Rules live in ReplicatedStorage.Break.Config. To send a player back to the surface set ClearedStage and BrokenLayers to 0.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakFolder = ReplicatedStorage:WaitForChild("Break")
local Config = require(BreakFolder:WaitForChild("Config"))
local HitRemote = BreakFolder:WaitForChild("Hit")
local ProgressRemote = BreakFolder:WaitForChild("Progress")
local HitFxRemote = BreakFolder:WaitForChild("HitFx")

local SERVER_REACH = Config.Reach + 6 -- leeway for lag / movement
local MIN_INTERVAL = Config.SwingCooldown * 0.7
local FX_RANGE = 120 -- other players this close see your hits

local damage = {} -- [player] = { [part] = damage dealt }
local lastHit = {} -- [player] = os.clock()

local function breakFor(player, part)
	local current = player:GetAttribute("ClearedStage") or 0
	if Config.Classify(part) == "layer" then
		local layer = part:GetAttribute("BreakLayer")
		player:SetAttribute("BrokenLayers", layer)
		if layer >= Config.LayerCount() then
			player:SetAttribute("ClearedStage", math.max(current, 1))
		end
	else
		player:SetAttribute("ClearedStage", math.max(current, part:GetAttribute("Stage")))
	end
end

HitRemote.OnServerEvent:Connect(function(player, part)
	if not Config.Classify(part) or not part:IsDescendantOf(workspace) or not Config.CanHit(player, part) then
		return
	end
	local now = os.clock()
	if now - (lastHit[player] or 0) < MIN_INTERVAL then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if Config.Distance(part, root.Position) > SERVER_REACH then
		return
	end
	lastHit[player] = now

	local dealtByPart = damage[player]
	if not dealtByPart then
		dealtByPart = {}
		damage[player] = dealtByPart
	end
	local maxHealth = part:GetAttribute("MaxHealth") or 1
	local hit = Config.GetDamage(player)
	local dealt = math.min((dealtByPart[part] or 0) + hit, maxHealth)
	local broken = dealt >= maxHealth
	dealtByPart[part] = if broken then nil else dealt

	ProgressRemote:FireClient(player, part, dealt, broken)

	local point, normal = Config.ImpactPoint(part, root.CFrame)
	for _, other in Players:GetPlayers() do
		local otherRoot = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if otherRoot and (otherRoot.Position - point).Magnitude < FX_RANGE then
			HitFxRemote:FireClient(other, part, point, normal, character) -- character: they play its tool animation
		end
	end

	if broken then
		breakFor(player, part)
	end
end)

local function setup(player)
	if player:GetAttribute("BrokenLayers") == nil then
		player:SetAttribute("BrokenLayers", 0)
	end
	player:GetAttributeChangedSignal("ClearedStage"):Connect(function()
		damage[player] = nil -- old progress no longer applies (stage broken, skipped or reset)
		if (player:GetAttribute("ClearedStage") or 0) < 1 then
			player:SetAttribute("BrokenLayers", 0) -- back at the surface: the layers come back
		end
	end)
end

Players.PlayerAdded:Connect(setup)
for _, player in Players:GetPlayers() do
	setup(player)
end

Players.PlayerRemoving:Connect(function(player)
	damage[player] = nil
	lastHit[player] = nil
end)
