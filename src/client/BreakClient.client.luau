-- Client side of the break system:
--  * standing on or next to the next break block / gate auto-swings at it (no clicking)
--  * tool animation for the held tool's AnimType (ReplicatedStorage.Break.ToolAnims; plain slash with no tool),
--    hit effects for that tool type / theme and damage numbers (ReplicatedStorage.Break.Effects)
--  * shows YOUR progress on each block's bar ("597B/25.0T")
-- BreakServer decides the damage. When a block breaks, SkipStageClient hides it and it shatters into flying chunks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BreakFolder = ReplicatedStorage:WaitForChild("Break")
local Config = require(BreakFolder:WaitForChild("Config"))
local Effects = require(BreakFolder:WaitForChild("Effects"))
local ToolAnims = require(BreakFolder:WaitForChild("ToolAnims"))
ToolAnims.Start()
local HitRemote = BreakFolder:WaitForChild("Hit")
local ProgressRemote = BreakFolder:WaitForChild("Progress")
local HitFxRemote = BreakFolder:WaitForChild("HitFx")

local player = Players.LocalPlayer
local digSite = workspace:WaitForChild("DigSite")
local breakFolder = workspace:WaitForChild("break")

---------------------------------------------------------------- progress bars
local blocks = {} -- [part] = true
local progress = {} -- [part] = damage this player has dealt

local BAR_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function refresh(part)
	local gui = part:FindFirstChild("StageGui")
	local bar = gui and gui:FindFirstChild("HealthBar", true)
	if not bar then
		return
	end
	local max = part:GetAttribute("MaxHealth") or 1
	local dealt = progress[part] or 0
	local fill = bar:FindFirstChild("Fill")
	if fill then
		TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(math.clamp(dealt / max, 0, 1), 1) }):Play()
	end
	local text = bar:FindFirstChild("HealthText")
	if text then
		text.Text = Config.Format(dealt) .. "/" .. Config.Format(max)
	end
end

local function register(part)
	if blocks[part] or not Config.Classify(part) then
		return
	end
	blocks[part] = true
	refresh(part)
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			blocks[part] = nil
			progress[part] = nil
		end
	end)
end

for _, d in digSite:GetDescendants() do
	register(d)
end
for _, d in breakFolder:GetChildren() do
	register(d)
end
digSite.DescendantAdded:Connect(register)
breakFolder.ChildAdded:Connect(register)

ProgressRemote.OnClientEvent:Connect(function(part, dealt)
	if part and blocks[part] then
		progress[part] = dealt
		refresh(part)
	end
end)

-- progress changed (block broken, skipped, back to surface): the server forgot that damage, so every block still
-- standing starts from 0. Broken ones keep their full bar while they shatter and reset once they come back.
local function resetProgress()
	for part in blocks do
		if not Config.IsBroken(player, part) and progress[part] then
			progress[part] = nil
			refresh(part)
		end
	end
end
player:GetAttributeChangedSignal("ClearedStage"):Connect(resetProgress)
player:GetAttributeChangedSignal("BrokenLayers"):Connect(resetProgress)

-- other players hitting a block you can still see
HitFxRemote.OnClientEvent:Connect(function(part, point, normal, attacker)
	if attacker then
		ToolAnims.Play(attacker, point)
	end
	if part and blocks[part] and not Config.IsBroken(player, part) then
		Effects.hit(part, point, normal, false, ToolAnims.GetStyle(attacker))
	end
end)

---------------------------------------------------------------- swinging
local swingTrack, swingAnimator

local function getSwingTrack(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if swingAnimator ~= animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R6
			then Config.SwingAnimation.R6
			else Config.SwingAnimation.R15
		swingTrack = animator:LoadAnimation(animation)
		swingTrack.Priority = Enum.AnimationPriority.Action
		swingTrack.Looped = false
		swingAnimator = animator
	end
	return swingTrack
end

local function findTarget(root)
	local best, bestDistance = nil, Config.Reach
	for part in blocks do
		if Config.CanHit(player, part) then
			local distance = Config.Distance(part, root.Position)
			if distance <= bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

local lastSwing = 0

local function swing()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if os.clock() - lastSwing < Config.SwingCooldown then
		return
	end
	local target = findTarget(root)
	if not target then
		return
	end
	lastSwing = os.clock()

	-- the tool's own animation set, or the plain slash with bare hands / a tool without one
	local style = ToolAnims.GetStyle(character)
	local impactDelay = Config.ImpactDelay
	if style and ToolAnims.Play(character, (Config.ImpactPoint(target, root.CFrame))) then
		impactDelay = style.style.impact
	else
		style = nil
		local track = getSwingTrack(humanoid)
		if track then
			track:Play(0.05, 1, 1.4)
		end
	end

	task.delay(impactDelay, function()
		if not blocks[target] or not Config.CanHit(player, target) or not root.Parent then
			return
		end
		HitRemote:FireServer(target)
		local point, normal = Config.ImpactPoint(target, root.CFrame)
		Effects.hit(target, point, normal, true, style)
		Effects.damageNumber(point + normal * 2, Config.GetDamage(player))
	end)
end

-- keeps a drill spinning / the tool aimed while a block is in reach
local function keepAimed()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = root and findTarget(root)
	if target then
		ToolAnims.SetActive(character, (Config.ImpactPoint(target, root.CFrame)))
	end
end

-- auto-swing: keeps hitting while you're in reach of a block (swing() does nothing when nothing is in reach)
task.spawn(function()
	while true do
		task.wait(0.05)
		swing()
		keepAimed()
	end
end)
