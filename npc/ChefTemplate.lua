local ChatService = game:GetService("Chat")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Modules = ServerStorage:WaitForChild("Modules")
local NPCNav = require(Modules:WaitForChild("NPCNavigation"))
local nav

local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")
local rootPart = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")

local plotName = npc:GetAttribute("AssignedPlot")
while not plotName do task.wait(0.5); plotName = npc:GetAttribute("AssignedPlot") end
local PLOT = Workspace:WaitForChild(plotName)

local ActiveOrders = PLOT:FindFirstChild("ActiveOrders") or Instance.new("Folder", PLOT); ActiveOrders.Name = "ActiveOrders"
local ClaimedOrders = PLOT:FindFirstChild("ClaimedOrders") or Instance.new("Folder", PLOT); ClaimedOrders.Name = "ClaimedOrders"
local OrderReady = PLOT:FindFirstChild("OrderReady") or Instance.new("BindableEvent", PLOT); OrderReady.Name = "OrderReady"

local function GetObjectsInPlot(tagName)
	return nav:GetObjectsInPlot(tagName)
end

local CHEF_SPEEDS = {12, 14, 16, 18, 20, 22, 24, 26, 29, 32}
local CHEF_PROFITS = {10, 15, 25, 40, 75, 150, 300, 800, 2000, 5000}

local UPGRADE_CONFIG = {
	Quality = { Stats = {0, 20, 45, 80, 130, 190, 270, 370, 490, 650} },
	Sourcing = { Stats = {0, 10, 25, 45, 70, 105, 150, 205, 275, 360} }
}

local TURN_SPEED = 15; local FLOOR_HEIGHT = 12; local MAX_STEP_HEIGHT = 1.8
local CloudTemplate = ReplicatedStorage:WaitForChild("BuildSystem"):WaitForChild("Furniture"):WaitForChild("Cloud")
local GROUP_NPC = "NPCs"
local PATH_COSTS = {
	["Wall"]=math.huge, ["Window"]=math.huge, ["PanoramWall"]=math.huge, ["CheckeredWall"]=math.huge,
	["Door"]=0, ["Obstacle"]=25,
	["WoodTile"]=0, ["AsphaltTile"]=0, ["CheckeredTile"]=0, ["Cloud"]=0
}
local AddQuestProgress = ServerStorage:WaitForChild("RestaurantEvents"):WaitForChild("AddQuestProgress")

local IsWorking = false; local myCurrentTaskObj = nil; local myCurrentMachine = nil

rootPart.Anchored = true; humanoid.PlatformStand = true
if rootPart:CanSetNetworkOwnership() then pcall(function() rootPart:SetNetworkOwner(nil) end) end

local partsToFade = {}
local function SetupPartPhysics(part)
	if part:IsA("BasePart") then
		part.CollisionGroup = GROUP_NPC; part.Massless = true
		part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
	end
	if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Decal") then
		table.insert(partsToFade, part)
	end
end
for _, v in pairs(npc:GetDescendants()) do SetupPartPhysics(v) end; npc.DescendantAdded:Connect(SetupPartPhysics)

local function LoadAnim(id) local animation = Instance.new("Animation"); animation.AnimationId = id; animation.Parent = npc; return humanoid:LoadAnimation(animation) end
local anims = { walk = LoadAnim("rbxassetid://70637851209232") }
local function Speak(text) pcall(function() ChatService:Chat(head, text, Enum.ChatColor.Yellow) end) end
local function StopAllAnims() for _, t in pairs(humanoid:GetPlayingAnimationTracks()) do t:Stop(0.1) end end

local function IsValid(obj)
	return nav:IsValid(obj)
end

local function HasAvailableWork()
	local children = ActiveOrders:GetChildren(); if #children == 0 then return false end
	local hasStoveFree, hasDispenserFree = false, false
	for _, obj in ipairs(GetObjectsInPlot("Stove")) do if obj:FindFirstChild("TargetPart") and not obj:GetAttribute("Occupied") then hasStoveFree = true; break end end
	for _, obj in ipairs(GetObjectsInPlot("Dispenser")) do if obj:FindFirstChild("TargetPart") and not obj:GetAttribute("Occupied") then hasDispenserFree = true; break end end
	if not hasStoveFree and not hasDispenserFree then return false end

	for _, taskObj in ipairs(children) do
		if taskObj:IsA("StringValue") then
			if taskObj.Value == "Drink" and hasDispenserFree then return true end
			if taskObj.Value ~= "Drink" and hasStoveFree then return true end
		end
	end return false
end

nav = NPCNav.new(npc, PLOT, {
	PathProfiles = { Default = PATH_COSTS },
	PartsToFade = partsToFade,
	CloudTemplate = CloudTemplate,
	WalkAnimation = anims.walk,
	CollisionGroup = GROUP_NPC,
	TurnSpeed = TURN_SPEED,
	FloorHeight = FLOOR_HEIGHT,
	MaxStepHeight = MAX_STEP_HEIGHT,
	DoorSnapRadius = 3, 
	TreatHumanoidAsValid = true, 
	HasWorkCheck = HasAvailableWork, 
})

local currentWalkSpeed = 12; local currentWorkTime = 2

local function ApplyBuffs()
	local lvl = npc:GetAttribute("Level") or 1
	lvl = math.clamp(lvl, 1, 10)
	currentWalkSpeed = CHEF_SPEEDS[lvl]
	currentWorkTime = 2
	nav:SetWalkSpeed(currentWalkSpeed)
end
npc:GetAttributeChangedSignal("Level"):Connect(ApplyBuffs); ApplyBuffs()

npc.Destroying:Connect(function()
	if myCurrentMachine and myCurrentMachine.Parent then myCurrentMachine:SetAttribute("Occupied", false) end
	if myCurrentTaskObj and myCurrentTaskObj.Parent == ClaimedOrders then
		myCurrentTaskObj:SetAttribute("ClaimTime", nil)
		pcall(function() myCurrentTaskObj.Parent = ActiveOrders end)
	end
end)

local function FindClosestAvailable(name)
	local best, minDist = nil, math.huge
	local now = os.clock()
	for _, obj in ipairs(GetObjectsInPlot(name)) do
		if obj:FindFirstChild("TargetPart") then
			local isOccupied = obj:GetAttribute("Occupied")
			if isOccupied then
				local occTime = obj:GetAttribute("OccupiedTime") or 0
				if occTime > 0 and (now - occTime > 45) then
					obj:SetAttribute("Occupied", false)
					isOccupied = false
				end
			end

			if not isOccupied then
				local dist = (rootPart.Position - obj.TargetPart.Position).Magnitude
				if dist < minDist then minDist = dist; best = obj end
			end
		end
	end return best
end

local function GetDeliveryTarget()
	local bestTarget, bestDist = nil, math.huge
	local targetType = nil

	for _, reg in ipairs(GetObjectsInPlot("CashRegister")) do
		if reg:FindFirstChild("Values") and reg.Values:FindFirstChild("Operator") then
			local operator = reg.Values.Operator.Value
			if operator and operator.Parent and operator:FindFirstChild("HumanoidRootPart") then
				local dist = (rootPart.Position - reg.TargetPart.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestTarget = operator
					targetType = "ActiveCashier"
				end
			end
		end
	end

	if not bestTarget then
		for _, cashier in ipairs(CollectionService:GetTagged("Cashier")) do
			if cashier ~= npc and cashier:GetAttribute("AssignedPlot") == plotName and cashier:FindFirstChild("HumanoidRootPart") then
				local dist = (rootPart.Position - cashier.HumanoidRootPart.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestTarget = cashier
					targetType = "IdleCashier"
				end
			end
		end
	end

	return bestTarget, targetType
end

local function NavigateOrTeleport(targetPos, targetObj, isOptional)
	if nav:NavigateTo(targetPos, targetObj, isOptional) then
		return true
	end
	if not IsValid(targetObj) then return false end

	local targetY = targetPos.Y
	if targetObj:FindFirstChild("TargetPart") then
		targetY = targetObj.TargetPart.Position.Y
	elseif targetObj:FindFirstChild("HumanoidRootPart") then
		targetY = targetObj.HumanoidRootPart.Position.Y
	end

	nav:PlayDespawnEffect()
	local tY = nav:GetTargetY(targetPos.X, targetPos.Z, targetY)
	local flatLook = Vector3.new(targetPos.X - rootPart.Position.X, 0, targetPos.Z - rootPart.Position.Z)
	if flatLook.Magnitude < 0.001 then flatLook = Vector3.new(0, 0, 1) else flatLook = flatLook.Unit end
	nav:PlaySpawnEffect(CFrame.lookAt(Vector3.new(targetPos.X, tY, targetPos.Z), Vector3.new(targetPos.X, tY, targetPos.Z) + flatLook))
	task.wait(0.2)

	return IsValid(targetObj)
end

local function GetRandomAvailableWorkstation()
	local stations = {}
	for _, obj in ipairs(GetObjectsInPlot("Stove")) do if obj:FindFirstChild("TargetPart") and not obj:GetAttribute("Occupied") then table.insert(stations, obj) end end
	for _, obj in ipairs(GetObjectsInPlot("Dispenser")) do if obj:FindFirstChild("TargetPart") and not obj:GetAttribute("Occupied") then table.insert(stations, obj) end end
	return #stations > 0 and stations[math.random(1, #stations)] or nil
end

local function CreateCup()
	local cup = Instance.new("Part"); cup.Name = "Cup"; cup.Size = Vector3.new(0.5, 0.8, 0.5); cup.Color = Color3.fromRGB(255, 255, 255); cup.Material = Enum.Material.Plastic; cup.CanCollide = false; cup.CanTouch = false; cup.CanQuery = false; cup.Massless = true
	local hand = npc:FindFirstChild("RightHand") or npc:FindFirstChild("Right Arm")
	if hand then cup.CFrame = hand.CFrame * CFrame.new(0, -0.5, -0.5) * CFrame.Angles(math.rad(90), 0, 0); local w = Instance.new("WeldConstraint"); w.Part0 = hand; w.Part1 = cup; w.Parent = cup; cup.Parent = npc end; return cup
end

local function GetOrderAndMachine()
	local rawTasks = ActiveOrders:GetChildren(); if #rawTasks == 0 then return nil, nil end

	local tasks = {}
	for _, t in ipairs(rawTasks) do if t:IsA("StringValue") then table.insert(tasks, t) end end
	table.sort(tasks, function(a, b) return (a:GetAttribute("SpawnTime") or 0) < (b:GetAttribute("SpawnTime") or 0) end)

	for _, taskObj in ipairs(tasks) do
		if taskObj.Parent == ActiveOrders then
			local machineName = (taskObj.Value == "Drink") and "Dispenser" or "Stove"
			local machine = FindClosestAvailable(machineName)

			if machine then
				taskObj:SetAttribute("ClaimTime", os.clock()); taskObj.Parent = ClaimedOrders; machine:SetAttribute("Occupied", true); machine:SetAttribute("OccupiedTime", os.clock())
				return {id = taskObj:GetAttribute("TicketID"), type = taskObj.Value, obj = taskObj}, machine
			elseif #GetObjectsInPlot(machineName) == 0 then
				taskObj:Destroy()
			end
		end
	end
	return nil, nil
end

local myIdleStation = nil
local loopCounter = 0

local function MainLoop()
	task.wait(1)
	nav:PlaySpawnEffect()
	nav:ManageCloudUnderFeet(rootPart.Position)

	while true do
		task.wait(0.2); loopCounter = loopCounter + 1

		if loopCounter % 25 == 0 then
			pcall(function()
				for _, taskObj in ipairs(ClaimedOrders:GetChildren()) do
					local claimTime = taskObj:GetAttribute("ClaimTime")
					if claimTime and (os.clock() - claimTime > 60) then taskObj:SetAttribute("ClaimTime", nil); taskObj.Parent = ActiveOrders end
				end
			end)
		end

		if npc:GetAttribute("IsPaused") then
			if myCurrentMachine and myCurrentMachine.Parent then myCurrentMachine:SetAttribute("Occupied", false); myCurrentMachine = nil end
			if myCurrentTaskObj and myCurrentTaskObj.Parent == ClaimedOrders then myCurrentTaskObj.Parent = ActiveOrders; myCurrentTaskObj = nil end
			IsWorking = false; StopAllAnims()

			nav:ManageCloudUnderFeet(rootPart.Position)
			task.wait(1); continue
		end

		if not IsWorking then
			local currentOrder, machine = GetOrderAndMachine()

			if currentOrder and machine then
				IsWorking = true; myIdleStation = nil; myCurrentTaskObj = currentOrder.obj; myCurrentMachine = machine
				local ticketID, orderType = currentOrder.id, currentOrder.type

				if not NavigateOrTeleport(machine.TargetPart.Position, machine, false) then
					if IsValid(machine) then machine:SetAttribute("Occupied", false) end
					currentOrder.obj.Parent = ActiveOrders; IsWorking = false; myCurrentTaskObj = nil; myCurrentMachine = nil; continue
				end

				if not IsValid(machine) or not machine:FindFirstChild("TargetPart") then
					if currentOrder.obj and currentOrder.obj.Parent then currentOrder.obj.Parent = ActiveOrders end
					IsWorking = false; myCurrentTaskObj = nil; myCurrentMachine = nil; continue
				end

				local flatLook = Vector3.new(machine.TargetPart.Position.X - rootPart.Position.X, 0, machine.TargetPart.Position.Z - rootPart.Position.Z)
				if flatLook.Magnitude > 0.001 then rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatLook.Unit) end
				Speak("Preparing " .. (orderType == "Drink" and "drink..." or "food..."))

				local cookedSafely = true
				for i = 1, math.ceil(currentWorkTime * 5) do
					if npc:GetAttribute("IsPaused") or not IsValid(machine) then cookedSafely = false; break end
					task.wait(0.2)
					nav:ManageCloudUnderFeet(rootPart.Position)
				end

				if IsValid(machine) then machine:SetAttribute("Occupied", false) end
				if not cookedSafely then
					if currentOrder.obj and currentOrder.obj.Parent then currentOrder.obj.Parent = ActiveOrders end
					IsWorking = false; myCurrentTaskObj = nil; myCurrentMachine = nil; continue
				end

				local cupModel = (orderType == "Drink") and CreateCup() or nil

				local deliveryTarget, targetType = GetDeliveryTarget()
				local dropPos = nil
				local targetObj = nil

				if deliveryTarget then
					targetObj = deliveryTarget
					local rightVec = deliveryTarget.HumanoidRootPart.CFrame.RightVector
					local sideOffset = (math.random() > 0.5 and 2.5 or -2.5)
					dropPos = deliveryTarget.HumanoidRootPart.Position + (rightVec * sideOffset)
				else
					targetObj = FindClosestAvailable("ServiceCounter") or FindClosestAvailable("CashRegister")
					if targetObj and targetObj:FindFirstChild("TargetPart") then
						dropPos = targetObj.TargetPart.Position
					end
				end

				if dropPos and targetObj then
					NavigateOrTeleport(dropPos, targetObj, false)

					if IsValid(targetObj) then
						if targetType then
							local faceDir = Vector3.new(targetObj.HumanoidRootPart.Position.X - rootPart.Position.X, 0, targetObj.HumanoidRootPart.Position.Z - rootPart.Position.Z)
							if faceDir.Magnitude > 0.001 then rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + faceDir.Unit) end

							Speak("Here is your order!")
							local speakEvent = targetObj:FindFirstChild("SpeakRequested")
							if speakEvent then
								speakEvent:Fire("Got it!", Enum.ChatColor.Green)
							end
							task.wait(0.5)
						else
							Speak("Order's ready!")
						end
					end
				end

				nav:ManageCloudUnderFeet(rootPart.Position)
				if cupModel then cupModel:Destroy() end

				OrderReady:Fire(ticketID, orderType)

				pcall(function()
					local OwnerID = npc:GetAttribute("OwnerID")
					local plr = OwnerID and Players:GetPlayerByUserId(OwnerID)
					if plr then
						if plr:FindFirstChild("leaderstats") then
							local cashObj = plr.leaderstats:FindFirstChild("Cash")

							local qLevel = math.clamp(plr:GetAttribute("Upg_Quality") or 1, 1, 10)
							local sLevel = math.clamp(plr:GetAttribute("Upg_Sourcing") or 1, 1, 10)

							local qualityMult = 1 + ((UPGRADE_CONFIG.Quality.Stats[qLevel] or 0) / 100)
							local sourcingMult = 1 + ((UPGRADE_CONFIG.Sourcing.Stats[sLevel] or 0) / 100)

							local chefLvl = npc:GetAttribute("Level") or 1
							local baseProfit = CHEF_PROFITS[math.clamp(chefLvl, 1, 10)] or 10

							local finalProfit = math.floor(baseProfit * qualityMult * sourcingMult)
							if cashObj then cashObj.Value += finalProfit end
						end
						local EmpID = npc:GetAttribute("EmpID")
						if EmpID then AddQuestProgress:Fire(OwnerID, EmpID, orderType, 1) end
					end
				end)

				if currentOrder.obj and currentOrder.obj.Parent then currentOrder.obj:Destroy() end
				myCurrentTaskObj = nil; myCurrentMachine = nil; IsWorking = false
			else
				if myIdleStation and IsValid(myIdleStation) and not myIdleStation:GetAttribute("Occupied") then
					if (rootPart.Position - myIdleStation.TargetPart.Position).Magnitude > 5 then nav:NavigateTo(myIdleStation.TargetPart.Position, myIdleStation, true) end
					nav:ManageCloudUnderFeet(rootPart.Position)
				else
					myIdleStation = GetRandomAvailableWorkstation()
					if myIdleStation then nav:NavigateTo(myIdleStation.TargetPart.Position, myIdleStation, true) end
					nav:ManageCloudUnderFeet(rootPart.Position)
				end
			end
		end
	end
end

task.spawn(MainLoop)
