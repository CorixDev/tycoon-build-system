local PhysicsService = game:GetService("PhysicsService")
local ChatService = game:GetService("Chat")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local NPCNavigation = require(ServerStorage:WaitForChild("Modules"):WaitForChild("NPCNavigation"))

local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")
local rootPart = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")

local isAppearing = false
local GROUP_NPC = "NPCs"

local partsToFade = {}
local function SetupPartPhysics(part) 
	if part:IsA("BasePart") then 
		part.CollisionGroup = GROUP_NPC; part.Massless = true; 
		part.CanCollide = false; part.CanTouch = false
		part.CanQuery = false
	end 
end

local function HandleNewDescendant(v)
	if not isAppearing then
		if (v:IsA("BasePart") and v.Name ~= "HumanoidRootPart") or v:IsA("Decal") then 
			v.Transparency = 1 
			table.insert(partsToFade, v)
		end
	end
	SetupPartPhysics(v)
end

for _, v in pairs(npc:GetDescendants()) do HandleNewDescendant(v) end
npc.DescendantAdded:Connect(HandleNewDescendant)

local HairAssets = ReplicatedStorage:WaitForChild("HairAssets") 
local MaleHairIDs = {63690008, 451221329, 138664587209368, 90394168398656, 89531827991462}
local FemaleHairIDs = {1103003368, 2956239660, 96006202480333, 120449449314098, 130169962052673, 15492711982, 132743481214108}  
local MaleNames = {"James", "John", "Robert", "Michael", "David"}
local FemaleNames = {"Mary", "Patricia", "Jennifer", "Linda", "Susan"}
local LastNames = {"Smith", "Johnson", "Williams", "Brown", "Jones"}

local MaleFaces = {"rbxassetid://159665196", "rbxassetid://50725530", "rbxassetid://1108967375"} 
local FemaleFaces = {"rbxassetid://159665196", "rbxassetid://50725530", "rbxassetid://1108967375"} 
local MaleShirts = {"rbxassetid://6852469132", "rbxassetid://18835449568", "rbxassetid://7018767574", "rbxassetid://8894629715"} 
local FemaleShirts = {"rbxassetid://11811768069", "rbxassetid://12120689259", "rbxassetid://7332436321"}
local MalePants = {"rbxassetid://85781244661392", "rbxassetid://16782752862"}
local FemalePants = {"rbxassetid://85781244661392", "rbxassetid://117183131884065", "rbxassetid://9801902326", "rbxassetid://10898368741", "rbxassetid://11425625388", "rbxassetid://14220661736", "rbxassetid://14220740504", "rbxassetid://14058677786"}
local SkinTones = { Color3.fromRGB(253, 234, 212), Color3.fromRGB(238, 199, 148), Color3.fromRGB(202, 146, 101), Color3.fromRGB(138, 86, 51), Color3.fromRGB(87, 51, 28) }

local function applyHair(hum, hairID)
	local hairModel = HairAssets:FindFirstChild("Hair_" .. hairID)
	if hairModel then 
		local accessory = hairModel:FindFirstChildOfClass("Accessory") or hairModel:FindFirstChildWhichIsA("Accessory", true)
		if accessory then hum:AddAccessory(accessory:Clone()) end 
	end
end

local function applyAppearance()
	local isMale = math.random(1, 2) == 1
	local gender = isMale and "Male" or "Female"
	local skinColor = SkinTones[math.random(1, #SkinTones)]
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = skinColor; desc.TorsoColor = skinColor; desc.LeftArmColor = skinColor
	desc.RightArmColor = skinColor; desc.LeftLegColor = skinColor; desc.RightLegColor = skinColor; desc.Head = 0

	local faceID, shirtID, pantsID, hairID, fName
	if gender == "Female" then
		desc.LeftArm = 130690308716544; desc.RightArm = 112370903102688
		desc.LeftLeg = 77108585319577; desc.RightLeg = 75413217849816; desc.Torso = 83917837871869
		faceID = FemaleFaces[math.random(1, #FemaleFaces)]; shirtID = FemaleShirts[math.random(1, #FemaleShirts)]
		pantsID = FemalePants[math.random(1, #FemalePants)]; hairID = FemaleHairIDs[math.random(1, #FemaleHairIDs)]; fName = FemaleNames[math.random(1, #FemaleNames)]
	else
		desc.LeftArm = 27112052; desc.RightArm = 27112039
		desc.LeftLeg = 27112056; desc.RightLeg = 27112068; desc.Torso = 27112025
		faceID = MaleFaces[math.random(1, #MaleFaces)]; shirtID = MaleShirts[math.random(1, #MaleShirts)]
		pantsID = MalePants[math.random(1, #MalePants)]; hairID = MaleHairIDs[math.random(1, #MaleHairIDs)]; fName = MaleNames[math.random(1, #MaleNames)]
	end

	local lName = LastNames[math.random(1, #LastNames)]
	humanoid.DisplayName = fName .. " " .. lName; npc.Name = fName .. " " .. lName

	local applySuccess = false
	local applyThread = task.spawn(function()
		local ok, err = pcall(function() humanoid:ApplyDescription(desc) end)
		if not ok then warn("[Customer AI] Error:", err) end
		applySuccess = true
	end)

	local timeout = 0
	while not applySuccess and timeout < 30 do task.wait(0.1); timeout += 1 end
	if not applySuccess then pcall(function() task.cancel(applyThread) end) end

	local bodyColors = npc:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bodyColors.Name = "Body Colors"; bodyColors.Parent = npc
	bodyColors.HeadColor3 = skinColor; bodyColors.TorsoColor3 = skinColor
	bodyColors.LeftArmColor3 = skinColor; bodyColors.RightArmColor3 = skinColor
	bodyColors.LeftLegColor3 = skinColor; bodyColors.RightLegColor3 = skinColor

	for _, part in pairs(npc:GetChildren()) do if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then part.Color = skinColor end end

	local shirt = npc:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", npc); shirt.ShirtTemplate = shirtID
	local pants = npc:FindFirstChildOfClass("Pants") or Instance.new("Pants", npc); pants.PantsTemplate = pantsID
	local graphic = npc:FindFirstChildOfClass("ShirtGraphic"); if graphic then graphic:Destroy() end

	local headPart = npc:FindFirstChild("Head")
	if headPart then
		if headPart:IsA("MeshPart") then headPart.TextureID = "" end
		local face = headPart:FindFirstChild("face") or headPart:FindFirstChildOfClass("Decal")
		if not face then face = Instance.new("Decal", headPart); face.Name = "face" end
		face.Texture = faceID
		local mesh = headPart:FindFirstChildOfClass("SpecialMesh"); if mesh then mesh.MeshType = Enum.MeshType.Head; mesh.MeshId = "" end
	end
	for _, obj in pairs(npc:GetChildren()) do if obj:IsA("Accessory") then obj:Destroy() end end
	if hairID then applyHair(humanoid, hairID) end
end

task.wait() 
local spawnCFrame = rootPart.CFrame
rootPart.CFrame = CFrame.new(0, 5000, 0)
applyAppearance()
rootPart.CFrame = spawnCFrame 

local plotName = npc:GetAttribute("AssignedPlot")
while not plotName do task.wait(0.5); plotName = npc:GetAttribute("AssignedPlot") end
local PLOT = Workspace:WaitForChild(plotName)

local function MakePlotItemsPassable()
	if PLOT:GetAttribute("PathfindingSetupDone") then return end
	PLOT:SetAttribute("PathfindingSetupDone", true)

	local function processPart(obj)
		if obj:IsA("BasePart") then
			local n = string.lower(obj.Name)
			local p = obj.Parent and string.lower(obj.Parent.Name) or ""

			local isObstacle = string.find(n, "chair") or string.find(n, "table") or string.find(n, "seat") or string.find(p, "chair") or string.find(p, "table") or string.find(p, "seat") or string.find(n, "desc") or string.find(p, "desc") or string.find(n, "stove") or string.find(n, "dispenser") or string.find(n, "counter") or string.find(n, "register") or string.find(p, "register")
			local isDoor = string.find(n, "door") or string.find(p, "door") or string.find(n, "entrance") or string.find(n, "exit")
			local isLamp = string.find(n, "lamp") or string.find(n, "chandelier") or string.find(p, "lamp") or string.find(p, "chandelier")

			if isObstacle or isDoor or isLamp then
				local mod = obj:FindFirstChildOfClass("PathfindingModifier")
				if not mod then
					mod = Instance.new("PathfindingModifier")
					mod.Name = "NPC_PassThrough"
					mod.Parent = obj
				end

				if isObstacle then mod.Label = "Obstacle"; mod.PassThrough = true
				elseif isDoor then mod.Label = "Door"; mod.PassThrough = true
				elseif isLamp then mod.Label = "Lamp"; mod.PassThrough = true end
			end
		end
	end
	for _, obj in ipairs(PLOT:GetDescendants()) do processPart(obj) end
	PLOT.DescendantAdded:Connect(function(obj) task.delay(0.1, function() if obj.Parent then processPart(obj) end end) end)
end
task.spawn(MakePlotItemsPassable)

local WALK_SPEED = 16; local TURN_SPEED = 15 
local STAND_DIST = 3.5 
local EAT_TIME_SIT = 10; local EAT_TIME_STAND = 10

local MY_TICKET_ID = HttpService:GenerateGUID(false)
local SHORT_TICKET = string.sub(MY_TICKET_ID, 1, 4)
local QUEUE_SPACING = 3.5; local WAIT_SPACING = 3.5  
local FLOOR_HEIGHT = 12; local MAX_STEP_HEIGHT = 1.8 

local CloudTemplate = ReplicatedStorage:WaitForChild("BuildSystem"):WaitForChild("Furniture"):WaitForChild("Cloud") 

local PATH_COSTS_NORMAL = { 
	["Wall"] = math.huge, ["Window"] = math.huge, ["PanoramWall"] = math.huge, ["CheckeredWall"] = math.huge,
	["DoorWall"] = 0, ["Door"] = 0, ["Entrance"] = 0, ["Exit"] = 0,
	["Obstacle"] = 25, ["Lamp"] = 0,
	["WoodTile"] = 0, ["AsphaltTile"] = 0, ["CheckeredTile"] = 0
}
local PATH_COSTS_LEAVE = { 
	["Wall"] = math.huge, ["Window"] = math.huge, ["PanoramWall"] = math.huge, ["CheckeredWall"] = math.huge,
	["DoorWall"] = 0, ["Door"] = 0, ["Entrance"] = 0, ["Exit"] = 0,
	["Obstacle"] = 0, ["Lamp"] = 0,
	["WoodTile"] = 0, ["AsphaltTile"] = 0, ["CheckeredTile"] = 0
}

local function LoadAnim(id) local animation = Instance.new("Animation"); animation.AnimationId = id; animation.Parent = npc; return humanoid:LoadAnimation(animation) end
local anims = { walk = LoadAnim("rbxassetid://70637851209232"), sit = LoadAnim("rbxassetid://2506281703"), eat = LoadAnim("rbxassetid://507770239") }
anims.sit.Priority = Enum.AnimationPriority.Action4

local nav = NPCNavigation.new(npc, PLOT, {
	WalkSpeed = WALK_SPEED,
	TurnSpeed = TURN_SPEED,
	FloorHeight = FLOOR_HEIGHT,
	MaxStepHeight = MAX_STEP_HEIGHT,
	PartsToFade = partsToFade,
	CloudTemplate = CloudTemplate,
	WalkAnimation = anims.walk,
	PathProfiles = { 
		Default = PATH_COSTS_NORMAL, 
		Leaving = PATH_COSTS_LEAVE 
	},
	GetPathProfile = function()
		return npc:GetAttribute("Status") == "Leaving" and "Leaving" or "Default"
	end
})

local ActiveOrders = PLOT:FindFirstChild("ActiveOrders") or Instance.new("Folder", PLOT); ActiveOrders.Name = "ActiveOrders"
local OrderReady = PLOT:FindFirstChild("OrderReady") or Instance.new("BindableEvent", PLOT); OrderReady.Name = "OrderReady"

local FOOD_MENU = { {Name = "Burger", Price = 18}, {Name = "Pizza", Price = 20} }
local DRINK_MENU = { {Name = "Cola", Price = 10}, {Name = "Juice", Price = 12} }

local hasStove = #nav:GetObjectsInPlot("Stove") > 0
local hasDispenser = #nav:GetObjectsInPlot("Dispenser") > 0

local ORDER_LIST = {}
if hasStove then table.insert(ORDER_LIST, {Item = FOOD_MENU[math.random(1, #FOOD_MENU)], Type = "Food"}) end
if hasDispenser and math.random(1, 100) <= 70 then table.insert(ORDER_LIST, {Item = DRINK_MENU[math.random(1, #DRINK_MENU)], Type = "Drink"}) end
if #ORDER_LIST == 0 then table.insert(ORDER_LIST, {Item = FOOD_MENU[math.random(1, #FOOD_MENU)], Type = "Food"}) end

rootPart.Anchored = true; humanoid.PlatformStand = true 
if rootPart:CanSetNetworkOwnership() then pcall(function() rootPart:SetNetworkOwner(nil) end) end
CollectionService:AddTag(npc, "Customer")

local orderConnection = nil

npc.Destroying:Connect(function()
	if orderConnection then orderConnection:Disconnect(); orderConnection = nil end
	for _, taskObj in ipairs(ActiveOrders:GetChildren()) do
		if taskObj:GetAttribute("TicketID") == MY_TICKET_ID then taskObj:Destroy() end
	end
end)

local function StopAllAnims() for _, t in pairs(humanoid:GetPlayingAnimationTracks()) do t:Stop(0.1) end end
local function Speak(text) pcall(function() ChatService:Chat(head, text, Enum.ChatColor.White) end) end

local isForcedDespawn = false

local function TriggerDespawn()
	if isForcedDespawn then return end
	isForcedDespawn = true
	task.spawn(function()
		pcall(function() StopAllAnims() end)
		pcall(function() nav:PlayDespawnEffect() end)
		if npc and npc.Parent then npc:Destroy() end
	end)
end

PLOT:GetAttributeChangedSignal("PlotOwner"):Connect(function()
	if not PLOT:GetAttribute("PlotOwner") then TriggerDespawn() end
end)

local function EatWithTimer(seconds, isValidFunc)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PremiumEatTimer"; billboard.Adornee = head; billboard.Size = UDim2.new(0, 0, 0, 0); billboard.StudsOffset = Vector3.new(0, 2.8, 0); billboard.AlwaysOnTop = true; billboard.MaxDistance = 65; billboard.LightInfluence = 0
	local bg = Instance.new("Frame", billboard); bg.Size = UDim2.new(1, 0, 1, 0); bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25); bg.BackgroundTransparency = 0.15; bg.BorderSizePixel = 0
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0.4, 0)
	local stroke = Instance.new("UIStroke", bg); stroke.Color = Color3.fromRGB(255, 215, 0); stroke.Thickness = 1.5; stroke.Transparency = 0.2
	local textLabel = Instance.new("TextLabel", bg); textLabel.Size = UDim2.new(1, 0, 0.65, 0); textLabel.Position = UDim2.new(0, 0, 0.05, 0); textLabel.BackgroundTransparency = 1; textLabel.TextColor3 = Color3.fromRGB(255, 255, 255); textLabel.Font = Enum.Font.GothamBold; textLabel.TextScaled = true
	local padding = Instance.new("UIPadding", textLabel); padding.PaddingTop = UDim.new(0.1, 0); padding.PaddingBottom = UDim.new(0.1, 0)
	local barBg = Instance.new("Frame", bg); barBg.Size = UDim2.new(0.8, 0, 0.15, 0); barBg.Position = UDim2.new(0.1, 0, 0.7, 0); barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 45); barBg.BorderSizePixel = 0
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
	local barFill = Instance.new("Frame", barBg); barFill.Size = UDim2.new(1, 0, 1, 0); barFill.BackgroundColor3 = Color3.fromRGB(80, 255, 120); barFill.BorderSizePixel = 0
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

	billboard.Parent = npc

	local tY = 0
	local conn; conn = RunService.Heartbeat:Connect(function(dt)
		tY = tY + dt; local a = math.min(tY/0.4, 1); local ease = 1 - math.pow(1 - a, 3)
		if billboard and billboard.Parent then billboard.Size = UDim2.new(3.5 * ease, 0, 1 * ease, 0) end
		if a >= 1 then conn:Disconnect() end
	end)

	local isStanding = false
	local stopCheck = false

	if isValidFunc then
		task.spawn(function()
			while not stopCheck and not isForcedDespawn and npc.Parent do
				if not isStanding and not isValidFunc() then
					isStanding = true
					if anims.sit.IsPlaying then anims.sit:Stop() end
					if not anims.eat.IsPlaying then anims.eat:Play() end

					local targetFloorY = nav:GetTargetY(rootPart.Position.X, rootPart.Position.Z, rootPart.Position.Y)
					rootPart.CFrame = CFrame.new(rootPart.Position.X, targetFloorY, rootPart.Position.Z) * rootPart.CFrame.Rotation
					Speak("My chair disappeared! I'll eat standing.")
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	for i = seconds, 1, -1 do
		if not npc.Parent or isForcedDespawn then break end

		if i <= 5 then stroke.Color = Color3.fromRGB(255, 80, 80); textLabel.TextColor3 = Color3.fromRGB(255, 150, 150) end
		textLabel.Text = "⌛ " .. i .. "s"
		barFill.Size = UDim2.new(i/seconds, 0, 1, 0)
		nav:ManageCloudUnderFeet(rootPart.Position) 
		task.wait(1)
	end

	stopCheck = true
	if billboard and billboard.Parent then billboard:Destroy() end
end

local function GetTotalQueue(register)
	local count = 0
	for _, otherNPC in pairs(CollectionService:GetTagged("Customer")) do
		if otherNPC:GetAttribute("AssignedPlot") == plotName then
			local targetReg = otherNPC:FindFirstChild("TargetRegister")
			if targetReg and targetReg.Value == register then
				local status = otherNPC:GetAttribute("Status")
				if status == "QueueingRegister" or status == "Ordering" then count = count + 1 end
			end
		end
	end return count
end

local function GetQueueIndex(register, statusFilter)
	local count = 0; local targetPart = register:FindFirstChild("CustomerPart")
	if statusFilter == "WaitingForFood" then targetPart = register:FindFirstChild("WaitingPart") or register:FindFirstChild("CustomerPart") end
	if not targetPart then return 0 end

	for _, otherNPC in pairs(CollectionService:GetTagged("Customer")) do
		if otherNPC ~= npc and otherNPC:GetAttribute("AssignedPlot") == plotName and otherNPC:FindFirstChild("HumanoidRootPart") then
			local s = otherNPC:GetAttribute("Status")
			if s == statusFilter or (statusFilter == "QueueingRegister" and s == "Ordering") then
				local targetReg = otherNPC:FindFirstChild("TargetRegister")
				if targetReg and targetReg.Value == register then
					local otherDist = (otherNPC.HumanoidRootPart.Position - targetPart.Position).Magnitude
					local myDist = (rootPart.Position - targetPart.Position).Magnitude
					if otherDist < myDist then count = count + 1 end
				end
			end
		end
	end return count
end

local function GetSafePosition(originPart, spacing, count)
	local totalDist = 5 + (count * spacing); local direction = originPart.CFrame.LookVector; local startPos = originPart.Position
	local target2D = Vector3.new(startPos.X + (direction.X * totalDist), startPos.Y, startPos.Z + (direction.Z * totalDist))
	local tY = nav:GetTargetY(target2D.X, target2D.Z, startPos.Y)
	return Vector3.new(target2D.X, tY, target2D.Z)
end

local function GetBestRegister()
	local bestReg, minQueue, minDistance = nil, math.huge, math.huge
	for _, obj in ipairs(nav:GetObjectsInPlot("CashRegister")) do
		if obj:FindFirstChild("CustomerPart") and obj:FindFirstChild("Values") then
			local operator = obj.Values:FindFirstChild("Operator")
			if operator and operator.Value ~= nil then
				local q = GetTotalQueue(obj); local dist = (rootPart.Position - obj.CustomerPart.Position).Magnitude
				if q < minQueue then minQueue = q; minDistance = dist; bestReg = obj 
				elseif q == minQueue and dist < minDistance then minDistance = dist; bestReg = obj end
			end
		end
	end return bestReg
end

local itemsReceived = 0; local itemsNeeded = #ORDER_LIST

local function GoToRegister()
	local reg = nil
	repeat 
		reg = GetBestRegister()
		if not reg then nav:ManageCloudUnderFeet(rootPart.Position); task.wait(3) end 
	until reg or isForcedDespawn

	if isForcedDespawn then return nil, nil end

	local targetReg = npc:FindFirstChild("TargetRegister") or Instance.new("ObjectValue")
	targetReg.Name = "TargetRegister"; targetReg.Value = reg; targetReg.Parent = npc

	local customerPart = reg:FindFirstChild("CustomerPart")
	npc:SetAttribute("Status", "QueueingRegister")

	local function isRegValid() 
		return nav:IsValid(reg) and reg:FindFirstChild("Values") and reg.Values:FindFirstChild("Operator") and reg.Values.Operator.Value ~= nil 
	end

	while true do
		if isForcedDespawn then return nil, nil end
		if not isRegValid() then targetReg:Destroy(); npc:SetAttribute("Status", ""); return GoToRegister() end
		local peopleInFront = GetQueueIndex(reg, "QueueingRegister"); if peopleInFront == 0 then break end

		local queuePos = GetSafePosition(customerPart, QUEUE_SPACING, peopleInFront)
		if (Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z) - Vector3.new(queuePos.X, 0, queuePos.Z)).Magnitude > 2 then
			local arrived = nav:NavigateTo(queuePos, isRegValid)
			if not arrived and not isRegValid() then targetReg:Destroy(); npc:SetAttribute("Status", ""); return GoToRegister() end

			if isRegValid() and reg:FindFirstChild("TargetPart") then
				local lookVec = Vector3.new(reg.TargetPart.Position.X, rootPart.Position.Y, reg.TargetPart.Position.Z)
				StopAllAnims(); rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookVec)
			end
		end
		nav:ManageCloudUnderFeet(rootPart.Position); task.wait(0.5)
	end

	npc:SetAttribute("Status", "Ordering")
	local arrived2 = nav:NavigateTo(customerPart.Position, isRegValid)
	if not arrived2 and not isRegValid() then targetReg:Destroy(); npc:SetAttribute("Status", ""); return GoToRegister() end

	if isForcedDespawn then return nil, nil end
	if isRegValid() and reg:FindFirstChild("TargetPart") then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(reg.TargetPart.Position.X, rootPart.Position.Y, reg.TargetPart.Position.Z))
	end
	nav:ManageCloudUnderFeet(rootPart.Position)

	Speak("Order #" .. SHORT_TICKET)

	if orderConnection then orderConnection:Disconnect() end
	orderConnection = OrderReady.Event:Connect(function(id, typeFinished)
		if id == MY_TICKET_ID then itemsReceived = itemsReceived + 1; Speak("Got my " .. (typeFinished == "Drink" and "drink" or "food")) end
	end)

	if nav:IsValid(reg) then
		local requestEvent = reg:FindFirstChild("RequestService")
		if requestEvent then requestEvent:Fire(ORDER_LIST, MY_TICKET_ID) end
	end

	task.wait(2); return reg, targetReg 
end

local function WaitForFood(myRegister, targetReg)
	if not myRegister then return end
	local waitPoint = myRegister:FindFirstChild("WaitingPart") or myRegister:FindFirstChild("CustomerPart") 
	if not waitPoint then return end
	local sideOffset = waitPoint == myRegister:FindFirstChild("CustomerPart") and (waitPoint.CFrame.RightVector * 8) or Vector3.zero
	npc:SetAttribute("Status", "WaitingForFood"); if targetReg then targetReg.Value = myRegister end

	local function isWaitValid()
		return nav:IsValid(myRegister) and nav:IsValid(waitPoint)
	end

	local timer = 0
	while itemsReceived < itemsNeeded and timer < 90 do
		if isForcedDespawn then break end
		if not isWaitValid() then break end

		local peopleAhead = GetQueueIndex(myRegister, "WaitingForFood")
		local targetPos = GetSafePosition(waitPoint, WAIT_SPACING, peopleAhead) + sideOffset

		if (Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude > 2 then
			nav:NavigateTo(targetPos, isWaitValid)
			if not isWaitValid() then break end

			local lookVec = Vector3.new(waitPoint.Position.X, rootPart.Position.Y, waitPoint.Position.Z)
			StopAllAnims(); rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookVec)
		end
		nav:ManageCloudUnderFeet(rootPart.Position); task.wait(0.5); timer = timer + 0.5
	end

	if orderConnection then orderConnection:Disconnect(); orderConnection = nil end
	if targetReg then targetReg:Destroy() end; npc:SetAttribute("Status", "Eating")
end

local function FindChair()
	local chairs = nav:GetObjectsInPlot("Chair")
	local validChairs = {}
	for _, v in ipairs(chairs) do 
		if v:FindFirstChild("Value") and v.Value.Value == false and v:FindFirstChild("Seat") then table.insert(validChairs, v) end 
	end
	if #validChairs > 0 then 
		local c = validChairs[math.random(1, #validChairs)]; c.Value.Value = true; return c 
	end
	return nil
end

local function Main()
	if not PLOT:GetAttribute("PlotOwner") then TriggerDespawn(); return end

	task.wait(math.random(1,2))
	if isForcedDespawn then return end
	nav:PlaySpawnEffect(); nav:ManageCloudUnderFeet(rootPart.Position)

	local myReg, targetReg = GoToRegister(); 
	if isForcedDespawn then return end

	if myReg then
		Speak("Waiting for order...")
		WaitForFood(myReg, targetReg)
	end
	if isForcedDespawn then return end

	local function TrySitAndEat()
		local maxTries = 3
		for i = 1, maxTries do
			local chair = FindChair()
			if chair then
				local function isChairValid()
					return nav:IsValid(chair) and chair:FindFirstChild("Seat") ~= nil
				end

				local arrived = nav:NavigateTo(chair.Seat.Position, isChairValid)
				if isForcedDespawn then return true end

				if arrived and isChairValid() then
					StopAllAnims()
					nav:HideWalkCloud()

					local exactSitY = (chair.Seat.Size.Y / 2) + (rootPart.Size.Y / 2)
					rootPart.CFrame = chair.Seat.CFrame * CFrame.new(0, exactSitY, 0)

					anims.sit:Play(0.1); Speak("Yummy!")

					EatWithTimer(EAT_TIME_SIT, isChairValid)
					if isForcedDespawn then return true end

					anims.sit:Stop()
					anims.eat:Stop()

					if isChairValid() and chair:FindFirstChild("Value") then
						chair.Value.Value = false
					end

					npc:SetAttribute("Status", "Leaving")

					if isChairValid() then
						local flatLook = Vector3.new(chair.Seat.CFrame.LookVector.X, 0, chair.Seat.CFrame.LookVector.Z)
						if flatLook.Magnitude < 0.001 then flatLook = Vector3.new(0, 0, -1) else flatLook = flatLook.Unit end
						local standOffset = flatLook * STAND_DIST 
						local targetPos = chair.Seat.Position + standOffset

						local tY = nav:GetTargetY(targetPos.X, targetPos.Z, chair.Seat.Position.Y)
						rootPart.CFrame = CFrame.lookAt(Vector3.new(targetPos.X, tY, targetPos.Z), Vector3.new(targetPos.X + standOffset.X, tY, targetPos.Z + standOffset.Z))
					else
						local tY = nav:GetTargetY(rootPart.Position.X, rootPart.Position.Z, rootPart.Position.Y)
						rootPart.CFrame = CFrame.new(rootPart.Position.X, tY, rootPart.Position.Z) * rootPart.CFrame.Rotation
					end
					nav:ManageCloudUnderFeet(rootPart.Position)
					return true
				else
					if isChairValid() and chair:FindFirstChild("Value") then chair.Value.Value = false end
					Speak("Where did my chair go?")
				end
			else
				break
			end
		end
		return false
	end

	if not TrySitAndEat() then
		Speak("I'll eat standing."); anims.eat:Play()
		EatWithTimer(EAT_TIME_STAND)
		if isForcedDespawn then return end
		anims.eat:Stop()

		npc:SetAttribute("Status", "Leaving")
	end

	if isForcedDespawn then return end
	local exit = PLOT:FindFirstChild("Exit", true) or PLOT:FindFirstChild("Entrance", true)
	if exit then 
		Speak("Goodbye everyone!")
		local exitPos = exit:IsA("BasePart") and exit.Position or exit:GetPivot().Position
		local exitY = nav:GetTargetY(exitPos.X, exitPos.Z, exitPos.Y)
		nav:NavigateTo(Vector3.new(exitPos.X, exitY, exitPos.Z)) 
	end

	if not isForcedDespawn then
		TriggerDespawn()
	end
end

task.spawn(Main)
