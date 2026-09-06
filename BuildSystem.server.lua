--[[
	BuildSystem (server) — grid building for a tycoon plot

	What it does:
	- Places items on the player's plot with server-side price and floor checks
	- Multi-floor plots: floors unlock through the MaxFloor attribute,
	  elevators rebuild themselves upward when a new floor is bought
	- Structural integrity: items stand on a support graph (floor > walls/tables > surface items > ceiling).
	  Remove a support and everything that depended on it collapses with a refund
	- Save slots via DataStore with compact array serialization (see SerializeItem)

	Note: the starter base layout for slot 1 is hardcoded at the bottom of the load handler.
	In a bigger project that lives in a ModuleScript; kept in one file for the sample.

	Author: Corix (Roblox: NekoPeonie)
]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

--// Remotes
-- FindFirstChild-or-create fallbacks exist for studio testing.
-- In production these are created upfront, before any client can fire them.
local BuildSystem = ReplicatedStorage:WaitForChild("BuildSystem")
local PlaceItemEvent = BuildSystem:WaitForChild("PlaceItem")

local RemoveItemEvent = BuildSystem:FindFirstChild("RemoveItem") or Instance.new("RemoteEvent", BuildSystem)
RemoveItemEvent.Name = "RemoveItem"

local ElevatorEvents = ReplicatedStorage:FindFirstChild("ElevatorEvents") or Instance.new("Folder", ReplicatedStorage)
ElevatorEvents.Name = "ElevatorEvents"

local OpenGuiEvent = ElevatorEvents:FindFirstChild("OpenGui") or Instance.new("RemoteEvent", ElevatorEvents)
OpenGuiEvent.Name = "OpenGui"

local FloorBought = ElevatorEvents:FindFirstChild("FloorBought") or Instance.new("BindableEvent", ElevatorEvents)
FloorBought.Name = "FloorBought"

local AutoBuildElevator = ElevatorEvents:FindFirstChild("AutoBuildElevator") or Instance.new("BindableFunction", ElevatorEvents)
AutoBuildElevator.Name = "AutoBuildElevator"

local FurnitureFolder = BuildSystem:WaitForChild("Furniture")

--// Config
local DATA_KEY = "PlayerBuilds_v6_Slots"
local BuildStore = DataStoreService:GetDataStore(DATA_KEY)
local FLOOR_HEIGHT = 12
local REFUND_PERCENT = 0.8

-- Item categories change both placement rules and support behavior
local SURFACE_ITEMS = { ["Monitor"] = true }
local CEILING_ITEMS = { ["CeilingLamp"] = true, ["Chandelier"] = true }
local IS_FLOOR = { ["WoodTile"] = true, ["AsphaltTile"] = true, ["CheckeredTile"] = true }

local function IsWallType(name)
	return name == "Wall" or name == "PanoramWall" or name == "DoorWall" or name == "Window" or name == "Door" or name == "CheckeredWall"
end

local function IsSurfaceItem(name)
	return SURFACE_ITEMS[name] == true
end

local ITEM_PRICES = {
	WoodTile = 15, AsphaltTile = 15, CheckeredTile = 20,
	Wall = 35, CheckeredWall = 40, Window = 50, DoorWall = 60, PanoramWall = 90,
	Door = 45, Chair = 40, Table = 80, CTable = 200, CeilingLamp = 40,
	Chandelier = 250, CashRegister = 300, Monitor = 200, Elevator = 1000,
	Stove = 1000, Dispenser = 500, ServiceCounter = 650, Desc = 120
}

local ITEM_NAMES = {
	"WoodTile", "Wall", "Window", "DoorWall", "PanoramWall", "Door", "Chair", "Table",
	"CTable", "CeilingLamp", "Chandelier", "CashRegister", "Monitor", "Elevator",
	"Stove", "Dispenser", "ServiceCounter", "Desc", "Cloud",
	"AsphaltTile", "CheckeredTile", "CheckeredWall"
}

-- Numeric ids keep serialized entries small (DataStore limits)
local ITEM_IDS = {}
for i, v in ipairs(ITEM_NAMES) do
	ITEM_IDS[v] = i
end

--// Plot helpers
local function GetPlayerPlot(player)
	local plotName = player:GetAttribute("AssignedPlot")
	return plotName and Workspace:FindFirstChild(plotName) or nil
end

-- Plots can be a BasePart or a Model; we need one reference part to build relative CFrames from
local function GetPlotGround(plot)
	if not plot then return nil end
	if plot:IsA("BasePart") then return plot end
	if plot.PrimaryPart then return plot.PrimaryPart end

	local floor = plot:FindFirstChild("Floor") or plot:FindFirstChild("Base") or plot:FindFirstChild("Ground")
	if floor and floor:IsA("BasePart") then return floor end

	for _, child in pairs(plot:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Entrance" and child.Name ~= "Exit" then
			return child
		end
	end
	return plot:FindFirstChildWhichIsA("BasePart")
end

local function GetItemHolder(plot)
	if not plot then return nil end
	local holder = plot:FindFirstChild("PlacedItems")
	if not holder then
		holder = Instance.new("Folder", plot)
		holder.Name = "PlacedItems"
	end
	return holder
end

--// Shared break effect (used by manual removal and integrity collapses)
local function PlayBreakEffect(worldCFrame, color)
	local att = Instance.new("Attachment")
	att.WorldCFrame = worldCFrame
	att.Parent = Workspace.Terrain

	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxassetid://244221440"
	p.Lifetime = NumberRange.new(0.5)
	p.Rate = 0
	p.Speed = NumberRange.new(5)
	p.SpreadAngle = Vector2.new(360, 360)
	if color then
		p.Color = ColorSequence.new(color)
	end
	p.Parent = att
	p:Emit(20)

	Debris:AddItem(att, 1)
end

--// Serialization
-- Compact save format: {id, x, y, z, rx, ry, rz, sx, sy, sz, refund}
-- rotation is only written when non-zero, size only when present — keeps entries short
local function SerializeItem(PLOT, item, itemSize)
	local itemName = item.Name
	local itemCFrame = item:GetPivot()
	local GROUND = GetPlotGround(PLOT)
	local relCF = GROUND.CFrame:ToObjectSpace(itemCFrame)

	local x, y, z = relCF.X, relCF.Y, relCF.Z
	local rx, ry, rz = relCF:ToEulerAnglesYXZ()

	local function round3(n)
		return math.floor(n * 1000) / 1000
	end

	local id = ITEM_IDS[itemName] or itemName
	local arr = { id, round3(x), round3(y), round3(z) }

	local rrX, rrY, rrZ = round3(rx), round3(ry), round3(rz)
	if rrX ~= 0 or rrY ~= 0 or rrZ ~= 0 or itemSize then
		arr[5], arr[6], arr[7] = rrX, rrY, rrZ
	end

	if itemSize then
		arr[8], arr[9], arr[10] = round3(itemSize.X), round3(itemSize.Y), round3(itemSize.Z)
	end

	arr[11] = item:GetAttribute("RefundValue") or 0
	return arr
end

-- Supports both the compact array format and the verbose {Name, Pos, Rot} format
-- (the verbose one is what the starter layout below uses, for readability)
local function DeserializeItem(PLOT, data)
	local GROUND = GetPlotGround(PLOT)
	local name, relCF, size, refund

	if type(data) == "table" and data.Name then
		if not data.Pos or not data.Rot then
			return nil, nil, nil, nil
		end
		relCF = CFrame.new(data.Pos[1], data.Pos[2], data.Pos[3]) * CFrame.fromEulerAnglesYXZ(data.Rot[1], data.Rot[2], data.Rot[3])
		size = data.Size and Vector3.new(data.Size[1], data.Size[2], data.Size[3]) or nil
		name = data.Name
		refund = data.Refund
	else
		name = type(data[1]) == "number" and ITEM_NAMES[data[1]] or data[1]
		relCF = CFrame.new(data[2] or 0, data[3] or 0, data[4] or 0) * CFrame.fromEulerAnglesYXZ(data[5] or 0, data[6] or 0, data[7] or 0)
		size = data[8] and Vector3.new(data[8], data[9], data[10]) or nil
		refund = data[11]
	end

	return name, GROUND.CFrame:ToWorldSpace(relCF), size, refund
end

--// Spawning
local function SpawnItem(player, itemName, targetCFrame, customSize, cost, explicitRefund)
	if itemName == "Cloud" then return nil end

	local PLOT = GetPlayerPlot(player)
	local ItemHolder = GetItemHolder(PLOT)
	if not ItemHolder then return end

	local template = FurnitureFolder:FindFirstChild(itemName)
	if not template then return end

	local newItem = template:Clone()

	local basePrice = cost or ITEM_PRICES[itemName] or 0
	if explicitRefund ~= nil then
		newItem:SetAttribute("RefundValue", explicitRefund)
	else
		newItem:SetAttribute("RefundValue", math.floor(basePrice * REFUND_PERCENT))
	end

	newItem:PivotTo(targetCFrame)
	newItem.Parent = ItemHolder

	for _, part in pairs(newItem:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true

			if part.Name == "Hitbox" or part.Name == "TargetPart" then
				part.Transparency = 1
				part.CanCollide = false
			else
				part.CanCollide = true
			end

			-- Ceiling items hang visually but never block anything
			if CEILING_ITEMS[itemName] then
				part.CanCollide = false
				if part.Name ~= "Hitbox" and part.Name ~= "TargetPart" then
					part.CanQuery = false
				else
					part.CanQuery = true
				end
			end

			-- Tag obstacles/doors so NPC pathfinding routes around them (or through doors)
			if part.Name ~= "Hitbox" and part.Name ~= "TargetPart" then
				local n = string.lower(itemName)
				local isObstacle = string.find(n, "chair") or string.find(n, "table") or string.find(n, "desc") or string.find(n, "register") or string.find(n, "counter") or string.find(n, "stove") or string.find(n, "dispenser") or string.find(n, "monitor")
				local isDoor = string.find(n, "door")

				if isObstacle or isDoor then
					local mod = Instance.new("PathfindingModifier")
					mod.Name = "NPC_PassThrough"
					mod.PassThrough = true
					mod.Label = isObstacle and "Obstacle" or "Door"
					mod.Parent = part
				end
			end
		end
	end

	if itemName == "Elevator" then
		local targetPart = newItem:FindFirstChild("TargetPart")
		if targetPart then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ElevatorPrompt"
			prompt.ActionText = "Open Menu"
			prompt.ObjectText = "Elevator"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.RequiresLineOfSight = false
			prompt.Parent = targetPart

			prompt.Triggered:Connect(function(plr)
				OpenGuiEvent:FireClient(plr, newItem)
			end)
		end
	end

	return newItem
end

--// Structural integrity
-- BFS support check: items touching the ground are "supported", then support floods
-- through floors > walls/tables/elevators > ceiling and surface items.
-- Whatever stays unsupported after the flood collapses with a refund.
local function EnforcePlotIntegrity(PLOT, player)
	local ItemHolder = GetItemHolder(PLOT)
	local GROUND = GetPlotGround(PLOT)
	if not ItemHolder or not GROUND then return end

	local plotSurfaceY = GROUND.Position.Y + (GROUND.Size.Y / 2)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = { ItemHolder }
	overlapParams.FilterType = Enum.RaycastFilterType.Include

	local supported = {}
	local queue = {}

	-- Seed: anything sitting on the plot surface is supported
	for _, item in pairs(ItemHolder:GetChildren()) do
		local prim = item:IsA("Model") and (item.PrimaryPart or item:FindFirstChild("Hitbox")) or item:FindFirstChildWhichIsA("BasePart")
		if not prim then continue end

		local bottomY = prim.Position.Y - (prim.Size.Y / 2)
		if CEILING_ITEMS[item.Name] then
			bottomY = prim.Position.Y + (prim.Size.Y / 2)
		end
		if SURFACE_ITEMS[item.Name] then
			bottomY = prim.Position.Y - (prim.Size.Y / 2)
		end

		if math.abs(bottomY - plotSurfaceY) < 1.0 then
			supported[item] = true
			table.insert(queue, item)
		end
	end

	local head = 1
	while head <= #queue do
		local curr = queue[head]
		head += 1

		local prim = curr:IsA("Model") and (curr.PrimaryPart or curr:FindFirstChild("Hitbox")) or curr:FindFirstChildWhichIsA("BasePart")
		if not prim then continue end

		local cf = prim.CFrame
		local size = prim.Size
		local name = curr.Name

		-- Each item type "gives" support to specific neighbors in specific directions
		local checkCFs = {}

		if IS_FLOOR[name] then
			table.insert(checkCFs, { cf * CFrame.new(0, size.Y/2 + 0.5, 0), Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2)), "AboveFloor" })
			table.insert(checkCFs, { cf * CFrame.new(0, -size.Y/2 - 0.5, 0), Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2)), "BelowFloor" })
			table.insert(checkCFs, { cf, Vector3.new(size.X + 0.5, size.Y + 1.0, math.max(0.1, size.Z - 0.2)), "AdjFloor" })
			table.insert(checkCFs, { cf, Vector3.new(math.max(0.1, size.X - 0.2), size.Y + 1.0, size.Z + 0.5), "AdjFloor" })
		elseif IsWallType(name) then
			table.insert(checkCFs, { cf * CFrame.new(0, size.Y/2 + 0.5, 0), Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2)), "AboveWall" })
		elseif name == "Table" or name == "CTable" or name == "Desc" or name == "ServiceCounter" then
			table.insert(checkCFs, { cf * CFrame.new(0, size.Y/2 + 0.5, 0), Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2)), "AboveTable" })
		elseif name == "Elevator" then
			table.insert(checkCFs, { cf * CFrame.new(0, size.Y/2 + 0.5, 0), Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2)), "AboveFloor" })
			table.insert(checkCFs, { cf, Vector3.new(size.X + 0.5, size.Y + 1.0, math.max(0.1, size.Z - 0.2)), "AdjFloor" })
			table.insert(checkCFs, { cf, Vector3.new(math.max(0.1, size.X - 0.2), size.Y + 1.0, size.Z + 0.5), "AdjFloor" })
		end

		for _, check in ipairs(checkCFs) do
			local boxCF, boxSize, typeCheck = check[1], check[2], check[3]
			local parts = Workspace:GetPartBoundsInBox(boxCF, boxSize, overlapParams)

			for _, p in ipairs(parts) do
				local md = p:FindFirstAncestorOfClass("Model") or p
				if md.Parent == ItemHolder and not supported[md] then
					local valid = false
					local mName = md.Name

					if typeCheck == "AboveFloor" then
						if not CEILING_ITEMS[mName] then valid = true end
					elseif typeCheck == "BelowFloor" then
						if CEILING_ITEMS[mName] then valid = true end
					elseif typeCheck == "AdjFloor" then
						if IS_FLOOR[mName] or mName == "Elevator" then valid = true end
					elseif typeCheck == "AboveWall" then
						if IS_FLOOR[mName] then valid = true end
					elseif typeCheck == "AboveTable" then
						if IsSurfaceItem(mName) then valid = true end
					end

					if valid then
						supported[md] = true
						table.insert(queue, md)
					end
				end
			end
		end
	end

	-- Collapse pass
	local cashObj = player and player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")

	for _, item in ipairs(ItemHolder:GetChildren()) do
		if not supported[item] then
			local refund = item:GetAttribute("RefundValue") or 0
			if cashObj and refund > 0 then
				cashObj.Value += refund
			end

			local prim = item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")) or item
			if prim then
				PlayBreakEffect(prim.CFrame, Color3.fromRGB(255, 50, 50))
			end
			item:Destroy()
		end
	end
end

--// Placement (client asks, server re-checks everything)
PlaceItemEvent.OnServerEvent:Connect(function(player, itemName, clientCFrame, rotation)
	local PLOT = GetPlayerPlot(player)
	local GROUND = GetPlotGround(PLOT)
	if not GROUND then return end

	local plotSurfaceY = GROUND.Position.Y + (GROUND.Size.Y / 2)

	-- 0.01 epsilon keeps float noise from pushing an item into the wrong floor bucket
	local floorIndex = math.floor(((clientCFrame.Y - plotSurfaceY) + 0.01) / FLOOR_HEIGHT)

	local attemptFloor = floorIndex + 1
	local maxFloor = player:GetAttribute("MaxFloor") or 1

	-- One floor above current max is allowed, but only for floor tiles (you build the floor first)
	if attemptFloor > maxFloor + 1 then return end
	if attemptFloor == maxFloor + 1 and not IS_FLOOR[itemName] then return end

	local price = ITEM_PRICES[itemName] or 0
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashObj = leaderstats and leaderstats:FindFirstChild("Cash")

	if not cashObj or cashObj.Value < price then return end

	local template = FurnitureFolder:FindFirstChild(itemName)
	if not template then return end

	local hitbox = template.PrimaryPart or template:FindFirstChild("Hitbox")
	local size = hitbox.Size

	cashObj.Value -= price

	-- Y is computed server-side from the floor index; client Y is only trusted for surface items
	local fixedY = plotSurfaceY + (floorIndex * FLOOR_HEIGHT) + (size.Y / 2)

	if SURFACE_ITEMS[itemName] then
		fixedY = clientCFrame.Y
	elseif CEILING_ITEMS[itemName] then
		fixedY = plotSurfaceY + (floorIndex * FLOOR_HEIGHT) + 11.8
	end

	local targetRot
	if itemName == "CeilingLamp" then
		targetRot = CFrame.fromOrientation(0, math.rad(rotation + 90), math.rad(90))
	elseif IS_FLOOR[itemName] then
		targetRot = CFrame.Angles(0, 0, 0)
	else
		targetRot = CFrame.Angles(0, math.rad(rotation), 0)
	end

	SpawnItem(player, itemName, CFrame.new(clientCFrame.X, fixedY, clientCFrame.Z) * targetRot)

	-- small delay lets the spawn settle before the support graph runs
	task.delay(0.05, function()
		if PLOT and player.Parent then
			EnforcePlotIntegrity(PLOT, player)
		end
	end)
end)

RemoveItemEvent.OnServerEvent:Connect(function(player, targetItem)
	local PLOT = GetPlayerPlot(player)
	local ItemHolder = GetItemHolder(PLOT)

	if targetItem and targetItem.Parent == ItemHolder then
		local refundAmount = targetItem:GetAttribute("RefundValue") or 0
		local cashObj = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
		if cashObj and refundAmount > 0 then
			cashObj.Value += refundAmount
		end

		local ep = targetItem.PrimaryPart or targetItem:FindFirstChildWhichIsA("BasePart")
		if ep then
			PlayBreakEffect(ep.CFrame)
		end
		targetItem:Destroy()

		task.delay(0.05, function()
			if PLOT and player.Parent then
				EnforcePlotIntegrity(PLOT, player)
			end
		end)
	end
end)

--// Elevators
-- When a new floor is bought, every elevator on the previous top floor clones itself one level up
FloorBought.Event:Connect(function(player, floorNum)
	local PLOT = GetPlayerPlot(player)
	local GROUND = GetPlotGround(PLOT)
	local ItemHolder = GetItemHolder(PLOT)
	if not GROUND or not ItemHolder then return end

	local plotSurfaceY = GROUND.Position.Y + (GROUND.Size.Y / 2)
	local prevFloorIndex = floorNum - 2

	local elevatorsToClone = {}
	for _, item in pairs(ItemHolder:GetChildren()) do
		if item.Name == "Elevator" then
			local prim = item:IsA("Model") and item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
			if prim then
				if math.floor(((prim.Position.Y - plotSurfaceY) + 0.1) / FLOOR_HEIGHT) == prevFloorIndex then
					table.insert(elevatorsToClone, item:GetPivot())
				end
			end
		end
	end

	for _, pivot in pairs(elevatorsToClone) do
		local targetCFrame = CFrame.new(pivot.Position + Vector3.new(0, FLOOR_HEIGHT, 0)) * pivot.Rotation

		local alreadyExists = false
		for _, ex in pairs(ItemHolder:GetChildren()) do
			if ex.Name == "Elevator" and (ex:GetPivot().Position - targetCFrame.Position).Magnitude < 1 then
				alreadyExists = true
				break
			end
		end

		if not alreadyExists then
			SpawnItem(player, "Elevator", targetCFrame, nil, 0, 0)
		end
	end
end)

-- Called from the elevator UI: build a matching elevator on any reachable floor
AutoBuildElevator.OnInvoke = function(player, sourceElevator, targetFloor)
	local PLOT = GetPlayerPlot(player)
	if not PLOT then return nil end

	local GROUND = GetPlotGround(PLOT)
	if not GROUND or not sourceElevator then return nil end

	local plotSurfaceY = GROUND.Position.Y + (GROUND.Size.Y / 2)
	local sourcePrim = sourceElevator:IsA("Model") and sourceElevator.PrimaryPart or sourceElevator:FindFirstChildWhichIsA("BasePart", true)
	if not sourcePrim then return nil end

	local sourceFloorIndex = math.floor(((sourcePrim.Position.Y - plotSurfaceY) + 0.1) / FLOOR_HEIGHT) + 1
	local diffFloors = targetFloor - sourceFloorIndex
	local pivot = sourceElevator:GetPivot()
	local targetCFrame = CFrame.new(pivot.Position + Vector3.new(0, diffFloors * FLOOR_HEIGHT, 0)) * pivot.Rotation

	local newItem = SpawnItem(player, "Elevator", targetCFrame, nil, 0, 0)
	return newItem
end

--// Save slots
local SaveSlotEvents = ReplicatedStorage:WaitForChild("SaveSlotEvents")
local LoadSlotEvent = SaveSlotEvents:WaitForChild("LoadSlot")

local activeSlots = {}

LoadSlotEvent.OnServerEvent:Connect(function(player, slotId)
	activeSlots[player.UserId] = slotId
	player:SetAttribute("ActiveSlot", slotId)

	-- plot assignment can lag behind the load request, wait for it
	local plotName = player:GetAttribute("AssignedPlot")
	while not plotName do
		task.wait(0.5)
		if not player.Parent then return end
		plotName = player:GetAttribute("AssignedPlot")
	end

	local PLOT = GetPlayerPlot(player)
	local ItemHolder = GetItemHolder(PLOT)
	if not PLOT or not ItemHolder then return end

	local saveKey = "B_" .. player.UserId .. "_" .. slotId
	local success, data = pcall(function()
		return BuildStore:GetAsync(saveKey)
	end)

	ItemHolder:ClearAllChildren()

	-- First ever load on this slot: give the player a starter base (free, refund 0)
	if success and data == nil then
		data = {
			{ Name = "Stove", Pos = {19.5, 2.098, 34.5}, Rot = {-0, 3.141, 0} },
			{ Name = "Dispenser", Pos = {19.5, 3.75, 39.5}, Rot = {-0, -1.571, 0} },
			{ Name = "Wall", Pos = {19.5, 6.5, 31.999}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {14.5, 6.5, 31.999}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 34.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 39.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 44.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {19.5, 6.5, 47}, Rot = {-0, 3.141, 0} },
			{ Name = "CTable", Pos = {7, 1.75, 72}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {4.5, 6.5, 47}, Rot = {-0, 3.141, 0} },
			{ Name = "Wall", Pos = {-0.5, 6.5, 47}, Rot = {-0, 3.141, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 44.5}, Rot = {-0, -1.571, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 39.5}, Rot = {-0, -1.571, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 34.5}, Rot = {-0, -1.571, 0} },
			{ Name = "Wall", Pos = {-0.5, 6.5, 32}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {9.5, 6.5, 32}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {4.5, 6.5, 32}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Desc", Pos = {4.5, 1.5, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "CashRegister", Pos = {12, 1.549, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "DoorWall", Pos = {4.5, 6.5, 82}, Rot = {-0, 3.141, 0} },
			{ Name = "Desc", Pos = {-0.5, 1.5, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {-3, 6.5, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Wall", Pos = {-0.5, 6.5, 82}, Rot = {-0, 3.141, 0} },
			{ Name = "Wall", Pos = {19.5, 6.5, 82}, Rot = {-0, 3.141, 0} },
			{ Name = "Wall", Pos = {14.5, 6.5, 82}, Rot = {-0, 3.141, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 74.5}, Rot = {-0, -1.571, 0} },
			{ Name = "Wall", Pos = {22, 6.5, 79.5}, Rot = {-0, -1.571, 0} },
			{ Name = "DoorWall", Pos = {9.5, 6.5, 82}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 79.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 79.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 79.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 79.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 79.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 74.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 74.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 74.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 74.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 74.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 69.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 69.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 69.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 69.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 69.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 64.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 64.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 64.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 64.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 64.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 59.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 54.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 54.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 54.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 54.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 54.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 49.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 49.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 49.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 49.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 44.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 39.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {-0.5, 0.55, 34.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 34.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 34.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 34.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 34.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 39.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {19.5, 0.55, 44.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 44.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 44.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 44.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {4.5, 0.55, 39.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {9.5, 0.55, 39.5}, Rot = {-0, 0, 0} },
			{ Name = "WoodTile", Pos = {14.5, 0.55, 39.5}, Rot = {-0, 0, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 0.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 0.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 0.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 0.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 49.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 59.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 54.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 0.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 34.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 39.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 44.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 0.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 0.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 0.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 0.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 0.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 0.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "DoorWall", Pos = {9.5, 6.5, 47}, Rot = {-0, 3.141, 0} },
			{ Name = "CeilingLamp", Pos = {19.5, 12.3, 52}, Rot = {-0, 1.57, 1.57} },
			{ Name = "Wall", Pos = {14.5, 6.5, 47}, Rot = {-0, 3.141, 0} },
			{ Name = "CTable", Pos = {17, 1.75, 72}, Rot = {-0, 0, 0} },
			{ Name = "CeilingLamp", Pos = {19.5, 12.3, 39.5}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {4.5, 12.3, 39.5}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {4.5, 12.3, 52}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {12, 12.3, 39.5}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {12, 12.3, 52}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {12, 12.3, 64.5}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {19.5, 12.3, 64.5}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {19.5, 12.3, 77}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {12, 12.3, 77}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {4.5, 12.3, 64.5}, Rot = {-0, 1.57, 1.57} },
			{ Name = "CeilingLamp", Pos = {4.5, 12.3, 77}, Rot = {-0, 1.57, 1.57} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 34.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 34.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 34.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 34.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 34.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 39.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 39.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 39.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 39.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 39.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 44.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 44.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 44.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 44.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 44.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 49.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 54.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 59.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {19.5, 12.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {-0.5, 12.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {4.5, 12.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {9.5, 12.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {14.5, 12.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 84.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 79.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 74.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 69.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 64.5}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 59.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 54.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 49.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 44.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 39.499}, Rot = {-0, 1.57, 0} },
			{ Name = "AsphaltTile", Pos = {24.5, 12.55, 34.499}, Rot = {-0, 1.57, 0} },
			{ Name = "PanoramWall", Pos = {27, 6.5, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "PanoramWall", Pos = {-3, 6.5, 89.5}, Rot = {-0, 1.57, 0} },
			{ Name = "Elevator", Pos = {24.5, 6.5, 34.499}, Rot = {-0, 0, 0} },
		}
		for _, itemData in pairs(data) do
			itemData.Refund = 0
		end
	end

	if success and data then
		for _, d in pairs(data) do
			local name, cf, sz, refund = DeserializeItem(PLOT, d)
			if name == "Cloud" then continue end
			if cf and name then
				SpawnItem(player, name, cf, sz, ITEM_PRICES[name], refund)
			end
		end

		task.delay(0.5, function()
			if PLOT then
				EnforcePlotIntegrity(PLOT, player)
			end
		end)
	end
end)

--// Saving
local isSavingPlot = {}

local function SavePlot(player)
	local slotId = activeSlots[player.UserId] or player:GetAttribute("ActiveSlot")
	local PLOT = GetPlayerPlot(player)
	local ItemHolder = PLOT and GetItemHolder(PLOT)

	if not slotId or not PLOT or not ItemHolder then return end
	if isSavingPlot[player.UserId] then return end

	isSavingPlot[player.UserId] = true

	local itemsData = {}
	for _, item in pairs(ItemHolder:GetChildren()) do
		if item.Name == "Cloud" then continue end
		local s = (item:IsA("BasePart") and item.Size or (item:IsA("Model") and item.PrimaryPart and item.PrimaryPart.Size)) or nil
		table.insert(itemsData, SerializeItem(PLOT, item, s))
	end

	local saveKey = "B_" .. player.UserId .. "_" .. slotId
	pcall(function()
		BuildStore:SetAsync(saveKey, itemsData)
	end)

	isSavingPlot[player.UserId] = nil
end

Players.PlayerRemoving:Connect(function(player)
	SavePlot(player)
	activeSlots[player.UserId] = nil
end)

game:BindToClose(function()
	for _, p in pairs(Players:GetPlayers()) do
		SavePlot(p)
	end
	task.wait(2)
end)

-- Autosave every 30s, staggered per player so we don't spike the DataStore budget
task.spawn(function()
	while true do
		task.wait(30)
		for _, p in pairs(Players:GetPlayers()) do
			SavePlot(p)
			task.wait(0.2)
		end
	end
end)
