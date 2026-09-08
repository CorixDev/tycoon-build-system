local ChatService = game:GetService("Chat")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local NPCNav = require(ServerStorage:WaitForChild("Modules"):WaitForChild("NPCNavigation"))

local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")
local rootPart = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")

CollectionService:AddTag(npc, "Cashier")

local plotName = npc:GetAttribute("AssignedPlot")
while not plotName do task.wait(0.5); plotName = npc:GetAttribute("AssignedPlot") end
local PLOT = Workspace:WaitForChild(plotName)

local ActiveOrders = PLOT:FindFirstChild("ActiveOrders") or Instance.new("Folder", PLOT)
ActiveOrders.Name = "ActiveOrders"

local CASHIER_SPEEDS = {12, 14, 16, 18, 20, 22, 24, 26, 29, 32}
local currentProcessTime = 1.5

local CloudTemplate = ReplicatedStorage:WaitForChild("BuildSystem"):WaitForChild("Furniture"):WaitForChild("Cloud")
local AddQuestProgress = ServerStorage:WaitForChild("RestaurantEvents"):WaitForChild("AddQuestProgress")

local PATH_COSTS = {
	["Wall"] = math.huge, ["Window"] = math.huge, ["PanoramWall"] = math.huge, ["CheckeredWall"] = math.huge,
	["Door"] = 0, ["Obstacle"] = 25,
	["WoodTile"] = 0, ["AsphaltTile"] = 0, ["CheckeredTile"] = 0, ["Cloud"] = 0,
}

rootPart.Anchored = true; humanoid.PlatformStand = true
if rootPart:CanSetNetworkOwnership() then pcall(function() rootPart:SetNetworkOwner(nil) end) end

local partsToFade = {}
local function SetupPartPhysics(part)
	if part:IsA("BasePart") then
		part.CollisionGroup = "NPCs"; part.Massless = true
		part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
	end
	if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Decal") then
		table.insert(partsToFade, part)
	end
end
for _, v in pairs(npc:GetDescendants()) do SetupPartPhysics(v) end
npc.DescendantAdded:Connect(SetupPartPhysics)

local PHRASES = { GREETING = {"Hello!", "I can help the next customer!"}, PROCESS = {"Just a moment...", "Ringing that up..."}, DONE = {"Order sent to kitchen!", "Please wait."} }
local function LoadAnim(id) local animation = Instance.new("Animation"); animation.AnimationId = id; animation.Parent = npc; return humanoid:LoadAnimation(animation) end
local anims = { walk = LoadAnim("rbxassetid://70637851209232") }
local function Speak(key) local list = PHRASES[key]; if list then pcall(function() ChatService:Chat(head, list[math.random(1, #list)], Enum.ChatColor.Green) end) end end

local nav = NPCNav.new(npc, PLOT, {
	WalkSpeed = CASHIER_SPEEDS[1],
	PathProfiles = { Default = PATH_COSTS },
	PartsToFade = partsToFade,
	CloudTemplate = CloudTemplate,
	WalkAnimation = anims.walk,
	CollisionGroup = "NPCs",
})

local function ApplyBuffs()
	local lvl = math.clamp(npc:GetAttribute("Level") or 1, 1, 10)
	nav:SetWalkSpeed(CASHIER_SPEEDS[lvl])
	currentProcessTime = math.max(0.2, 1.5 - ((lvl - 1) * 0.12))
end
npc:GetAttributeChangedSignal("Level"):Connect(ApplyBuffs); ApplyBuffs()

local function FindEmptyRegister()
	local best, minDist = nil, math.huge
	for _, obj in ipairs(nav:GetObjectsInPlot("CashRegister")) do
		if obj:FindFirstChild("TargetPart") then
			local values = obj:FindFirstChild("Values")
			if values and values:FindFirstChild("Operator") and values.Operator.Value == nil then
				local dist = (rootPart.Position - obj.TargetPart.Position).Magnitude
				if dist < minDist then minDist = dist; best = obj end
			end
		end
	end
	return best
end

local function NavigateOrTeleport(targetPos, targetObj)
	if nav:NavigateTo(targetPos, targetObj, false) then return true end
	if not nav:IsValid(targetObj) then return false end

	local targetPart = targetObj:FindFirstChild("TargetPart") or targetObj:FindFirstChild("HumanoidRootPart")
	local targetY = targetPart and targetPart.Position.Y or targetPos.Y

	nav:PlayDespawnEffect()
	local tY = nav:GetTargetY(targetPos.X, targetPos.Z, targetY)

	local lookVec = Vector3.new(0, 0, 1)
	if targetObj:FindFirstChild("TargetPart") then
		lookVec = Vector3.new(targetObj.TargetPart.CFrame.LookVector.X, 0, targetObj.TargetPart.CFrame.LookVector.Z)
	end
	lookVec = lookVec.Magnitude < 0.001 and Vector3.new(0, 0, 1) or lookVec.Unit

	nav:PlaySpawnEffect(CFrame.lookAt(Vector3.new(targetPos.X, tY, targetPos.Z), Vector3.new(targetPos.X, tY, targetPos.Z) + lookVec))
	task.wait(0.2)
	return true
end

local function MainLoop()
	task.wait(1)
	nav:PlaySpawnEffect()

	while true do
		if npc:GetAttribute("IsPaused") then nav:ManageCloudUnderFeet(rootPart.Position); task.wait(1); continue end

		local myRegister = FindEmptyRegister()
		if myRegister then
			local operatorVal = myRegister.Values.Operator
			operatorVal.Value = npc

			local arrived = NavigateOrTeleport(myRegister.TargetPart.Position, myRegister)

			if arrived and nav:IsValid(myRegister) then
				local tPart = myRegister.TargetPart
				local tY = nav:GetTargetY(tPart.Position.X, tPart.Position.Z, tPart.Position.Y)
				local perfectPos = Vector3.new(tPart.Position.X, tY, tPart.Position.Z)

				local targetLook = Vector3.new(tPart.CFrame.LookVector.X, 0, tPart.CFrame.LookVector.Z)
				targetLook = targetLook.Magnitude < 0.001 and Vector3.new(0, 0, 1) or targetLook.Unit

				rootPart.CFrame = CFrame.lookAt(perfectPos, perfectPos + targetLook)
				anims.walk:Stop(0.2)

				local requestEvent = myRegister:WaitForChild("RequestService")
				local connection = requestEvent.Event:Connect(function(orderList, ticketId)
					Speak("GREETING"); task.wait(0.5); Speak("PROCESS"); task.wait(currentProcessTime)

					for _, order in ipairs(orderList) do
						local expectedTaskName = "Task_" .. tostring(ticketId) .. "_" .. order.Type
						if not ActiveOrders:FindFirstChild(expectedTaskName) then
							local newOrder = Instance.new("StringValue")
							newOrder.Name = expectedTaskName
							newOrder.Value = order.Type
							newOrder:SetAttribute("TicketID", ticketId)
							newOrder:SetAttribute("SpawnTime", os.clock())
							newOrder.Parent = ActiveOrders
						end
						task.wait(0.1)
					end
					Speak("DONE")

					local OwnerID = npc:GetAttribute("OwnerID"); local EmpID = npc:GetAttribute("EmpID")
					if OwnerID and EmpID then pcall(function() AddQuestProgress:Fire(OwnerID, EmpID, "Customer", 1); AddQuestProgress:Fire(OwnerID, EmpID, "Item", #orderList) end) end
				end)

				while nav:IsValid(myRegister) and operatorVal.Value == npc do
					if npc:GetAttribute("IsPaused") then break end
					nav:ManageCloudUnderFeet(rootPart.Position); task.wait(0.5)
				end

				if connection then connection:Disconnect() end
				nav:HideWalkCloud()
				if nav:IsValid(myRegister) and operatorVal.Value == npc then operatorVal.Value = nil end
			else
				operatorVal.Value = nil
				nav:HideWalkCloud()
				task.wait(2)
			end
		else
			nav:ManageCloudUnderFeet(rootPart.Position); task.wait(2)
		end
	end
end

task.spawn(MainLoop)
