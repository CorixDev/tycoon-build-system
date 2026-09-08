local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local IS_FLOOR_NAME = { WoodTile = true, AsphaltTile = true, CheckeredTile = true, Cloud = true }
local IS_WALL_NAME = { Wall = true, Window = true, PanoramWall = true, CheckeredWall = true }

local NPCNav = {}
NPCNav.__index = NPCNav

function NPCNav.new(npc, plot, config)
	config = config or {}
	local self = setmetatable({}, NPCNav)

	self.npc = npc
	self.plot = plot
	self.humanoid = npc:WaitForChild("Humanoid")
	self.rootPart = npc:WaitForChild("HumanoidRootPart")

	self.walkAnimation = config.WalkAnimation 
	self.partsToFade = config.PartsToFade or {} 
	self.cloudTemplate = config.CloudTemplate
	self.collisionGroup = config.CollisionGroup or "NPCs"

	self.turnSpeed = config.TurnSpeed or 15
	self.floorHeight = config.FloorHeight or 12
	self.maxStepHeight = config.MaxStepHeight or 1.8
	self.doorSnapRadius = config.DoorSnapRadius or 2.5
	self.floorCacheInterval = config.FloorCacheInterval or 2

	self.checkWalls = config.CheckWalls
	if self.checkWalls == nil then self.checkWalls = true end

	self.treatHumanoidAsValid = config.TreatHumanoidAsValid or false
	self.hasWorkCheck = config.HasWorkCheck 
	self.getPathProfile = config.GetPathProfile or function() return "Default" end

	self._walkSpeed = config.WalkSpeed or 16

	self._isForcedStop = false
	self._isAppearing = false
	self._myWalkCloud = nil

	self._cachedPlotSurfaceY = nil

	self._floorRayParams = RaycastParams.new()
	self._floorRayParams.FilterType = Enum.RaycastFilterType.Include
	self._floorRayParams.CollisionGroup = self.collisionGroup
	self._floorRayParams.RespectCanCollide = true
	self._lastFloorCacheTime = 0

	self._wallRayParams = RaycastParams.new()
	self._wallRayParams.FilterType = Enum.RaycastFilterType.Include
	self._wallRayParams.CollisionGroup = self.collisionGroup
	self._lastWallCacheTime = 0

	self._lastCloudRayTime = 0
	self._cloudShouldBeVisible = false


	self._paths = {}
	local agentParams = {
		AgentRadius = config.AgentRadius or 1.0,
		AgentHeight = config.AgentHeight or 5,
		AgentCanJump = false,
		WaypointSpacing = config.WaypointSpacing or 3,
	}
	for profileName, costs in pairs(config.PathProfiles or {}) do
		local params = table.clone(agentParams)
		params.Costs = costs
		self._paths[profileName] = PathfindingService:CreatePath(params)
	end

	npc.Destroying:Connect(function()
		self:Destroy()
	end)

	return self
end


function NPCNav:Stop()
	self._isForcedStop = true
end

function NPCNav:Destroy()
	self._isForcedStop = true
	if self._myWalkCloud then
		self._myWalkCloud:Destroy()
		self._myWalkCloud = nil
	end
end

function NPCNav:SetWalkSpeed(newSpeed)
	self._walkSpeed = newSpeed
end

function NPCNav:GetWalkSpeed()
	return self._walkSpeed
end

function NPCNav:HideWalkCloud()
	if self._myWalkCloud then
		self._myWalkCloud:PivotTo(CFrame.new(0, -10000, 0))
	end
end


function NPCNav:IsValid(obj)
	if not obj then return true end
	if not obj.Parent then return false end
	if self.treatHumanoidAsValid and obj:FindFirstChild("Humanoid") then return true end
	return obj:IsDescendantOf(self.plot)
end


function NPCNav:_ResolveValidator(watchObjectOrFn)
	if watchObjectOrFn == nil then return nil end
	if typeof(watchObjectOrFn) == "function" then return watchObjectOrFn end
	local obj = watchObjectOrFn
	return function() return self:IsValid(obj) end
end

function NPCNav:GetObjectsInPlot(tagName)
	local valid = {}
	for _, obj in pairs(CollectionService:GetTagged(tagName)) do
		if obj:IsDescendantOf(self.plot) then table.insert(valid, obj) end
	end
	if #valid == 0 then
		local holder = self.plot:FindFirstChild("PlacedItems")
		if holder then
			for _, obj in pairs(holder:GetChildren()) do
				if obj.Name == tagName then table.insert(valid, obj) end
			end
		end
	end
	return valid
end


function NPCNav:GetPlotSurfaceY()
	if self._cachedPlotSurfaceY then return self._cachedPlotSurfaceY end
	local plot = self.plot
	local floor = plot:FindFirstChild("Floor") or plot:FindFirstChild("Base") or plot:FindFirstChild("Ground")
	if not floor then
		for _, child in pairs(plot:GetChildren()) do
			if child:IsA("BasePart") and child.Name ~= "Entrance" and child.Name ~= "Exit" then
				floor = child
				break
			end
		end
	end
	if not floor then floor = plot:FindFirstChildWhichIsA("BasePart") or plot.PrimaryPart end
	self._cachedPlotSurfaceY = floor and (floor.Position.Y + (floor.Size.Y / 2)) or plot:GetPivot().Position.Y
	return self._cachedPlotSurfaceY
end

function NPCNav:GetBaseFloorY(yPos)
	local plotSurfaceY = self:GetPlotSurfaceY()
	local floorIndex = math.floor(((yPos - plotSurfaceY) + 2) / self.floorHeight)
	if floorIndex < 0 then floorIndex = 0 end
	return plotSurfaceY + (floorIndex * self.floorHeight)
end

function NPCNav:GetFloorFromY(yPos)
	local plotSurfaceY = self:GetPlotSurfaceY()
	local floorIndex = math.floor(((yPos - plotSurfaceY) + 2) / self.floorHeight)
	if floorIndex < 0 then floorIndex = 0 end
	return floorIndex + 1
end

function NPCNav:_GetFloorRayParams()
	local now = os.clock()
	if now - self._lastFloorCacheTime > self.floorCacheInterval then
		local cache = {}
		local plot = self.plot
		local ground = plot:FindFirstChild("Floor") or plot:FindFirstChild("Base") or plot:FindFirstChild("Ground") or plot:FindFirstChildWhichIsA("BasePart")
		if ground then table.insert(cache, ground) end
		local holder = plot:FindFirstChild("PlacedItems")
		if holder then
			for _, obj in ipairs(holder:GetChildren()) do
				if IS_FLOOR_NAME[obj.Name] then table.insert(cache, obj) end
			end
		end
		self._floorRayParams.FilterDescendantsInstances = cache
		self._lastFloorCacheTime = now
	end
	return self._floorRayParams
end

function NPCNav:_GetWallRayParams()
	local now = os.clock()
	if now - self._lastWallCacheTime > self.floorCacheInterval then
		local cache = {}
		local holder = self.plot:FindFirstChild("PlacedItems")
		if holder then
			for _, obj in ipairs(holder:GetChildren()) do
				if IS_WALL_NAME[obj.Name] then table.insert(cache, obj) end
			end
		end
		self._wallRayParams.FilterDescendantsInstances = cache
		self._lastWallCacheTime = now
	end
	return self._wallRayParams
end

function NPCNav:GetTargetY(x, z, referenceY)
	local baseFloorY = self:GetBaseFloorY(referenceY)
	local minSafeY = baseFloorY + self.humanoid.HipHeight + (self.rootPart.Size.Y / 2)

	local rayOrigin = Vector3.new(x, baseFloorY + 5, z)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -10, 0), self:_GetFloorRayParams())

	if rayResult and rayResult.Instance.Anchored then
		local detectedY = rayResult.Position.Y + self.humanoid.HipHeight + (self.rootPart.Size.Y / 2)
		if detectedY >= minSafeY - 0.1 and math.abs(detectedY - minSafeY) < self.maxStepHeight then
			return detectedY
		end
	end
	return minSafeY
end


function NPCNav:ManageCloudUnderFeet(position)
	if not self.cloudTemplate then return end

	local currentFloor = self:GetFloorFromY(position.Y)
	if currentFloor <= 1 then
		self._cloudShouldBeVisible = false
	else
		local now = os.clock()
		if now - self._lastCloudRayTime > 0.2 then
			self._lastCloudRayTime = now
			local result = workspace:Raycast(position, Vector3.new(0, -6, 0), self:_GetFloorRayParams())
			self._cloudShouldBeVisible = not (result and result.Instance.Anchored)
		end
	end

	if self._cloudShouldBeVisible then
		if not self._myWalkCloud then
			self._myWalkCloud = self.cloudTemplate:Clone()
			self._myWalkCloud.Name = "NPC_Walk_Cloud"
			self._myWalkCloud.Parent = workspace
			for _, part in pairs(self._myWalkCloud:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanTouch = false
					part.CanQuery = false
					part.CastShadow = false
					part.CollisionGroup = self.collisionGroup
				end
			end
		end
		local targetCFrame = CFrame.new(position.X, position.Y - 4.5, position.Z)
		if self._myWalkCloud:IsA("Model") then self._myWalkCloud:PivotTo(targetCFrame) else self._myWalkCloud.CFrame = targetCFrame end
	else
		self:HideWalkCloud()
	end
end


function NPCNav:_FadeModel(startTrans, endTrans, duration)
	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not self.npc or not self.npc.Parent then conn:Disconnect(); return end
		t = t + dt
		local alpha = math.min(t / duration, 1)
		local ease = endTrans == 0 and (1 - math.pow(1 - alpha, 3)) or (alpha * alpha)
		local currentTrans = startTrans + (endTrans - startTrans) * ease
		for _, p in ipairs(self.partsToFade) do
			if p and p.Parent then p.Transparency = currentTrans end
		end
		if alpha >= 1 then conn:Disconnect() end
	end)
end

function NPCNav:_PlayAppearEffect(targetCFrame)
	self._isAppearing = true
	local startCFrame = targetCFrame * CFrame.new(0, -4, 0)
	self.rootPart.CFrame = startCFrame
	for _, p in ipairs(self.partsToFade) do p.Transparency = 1 end

	local tY = startCFrame.Position.Y
	local conn
	local t = 0
	conn = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		local alpha = math.min(t / 0.6, 1)
		local ease = 1 - math.pow(1 - alpha, 3)
		if self.rootPart and self.rootPart.Parent then
			self.rootPart.CFrame = CFrame.new(self.rootPart.Position.X, tY + (4 * ease), self.rootPart.Position.Z) * targetCFrame.Rotation
		else
			conn:Disconnect()
			return
		end
		if alpha >= 1 then conn:Disconnect() end
	end)

	self:_FadeModel(1, 0, 0.6)
	task.wait(0.6)
	self._isAppearing = false
end

function NPCNav:PlaySpawnEffect(customCFrame)
	local endCFrame
	if customCFrame then
		endCFrame = customCFrame
	else
		local tY = self:GetTargetY(self.rootPart.Position.X, self.rootPart.Position.Z, self.rootPart.Position.Y)
		local flatLook = Vector3.new(self.rootPart.CFrame.LookVector.X, 0, self.rootPart.CFrame.LookVector.Z)
		flatLook = flatLook.Magnitude > 0.001 and flatLook.Unit or Vector3.new(0, 0, 1)
		endCFrame = CFrame.lookAt(
			Vector3.new(self.rootPart.Position.X, tY, self.rootPart.Position.Z),
			Vector3.new(self.rootPart.Position.X, tY, self.rootPart.Position.Z) + flatLook
		)
	end
	self:_PlayAppearEffect(endCFrame)
end

function NPCNav:PlayDespawnEffect()
	if self.walkAnimation and self.walkAnimation.IsPlaying then
		pcall(function() self.walkAnimation:Stop(0.2) end)
	end
	self:HideWalkCloud()

	local startY = self.rootPart.Position.Y
	local conn
	local t = 0
	conn = RunService.Heartbeat:Connect(function(dt)
		if not self.rootPart or not self.rootPart.Parent then conn:Disconnect(); return end
		t = t + dt
		local alpha = math.min(t / 0.5, 1)
		local ease = alpha * alpha
		self.rootPart.CFrame = CFrame.new(self.rootPart.Position.X, startY - (4 * ease), self.rootPart.Position.Z) * self.rootPart.CFrame.Rotation
		if alpha >= 1 then conn:Disconnect() end
	end)

	self:_FadeModel(0, 1, 0.5)
	task.wait(0.5)
end

function NPCNav:_SnapToDoorCenter(pos2D)
	local parts = workspace:GetPartBoundsInRadius(Vector3.new(pos2D.X, self.rootPart.Position.Y, pos2D.Z), 3)
	for _, part in pairs(parts) do
		if part.Name == "DoorWall" or part.Name == "Door" or part.Name == "Entrance" or part.Name == "Exit" then
			return Vector3.new(part.Position.X, 0, part.Position.Z)
		end
	end
	return pos2D
end

function NPCNav:_SnapWaypointsToDoors(waypoints)
	local adjusted = {}
	local doors = {}
	local holder = self.plot:FindFirstChild("PlacedItems")
	if holder then
		for _, obj in ipairs(holder:GetChildren()) do
			if string.find(obj.Name, "Door") or string.find(obj.Name, "Entrance") or string.find(obj.Name, "Exit") then
				table.insert(doors, obj)
			end
		end
	end

	for _, wp in ipairs(waypoints) do
		local pos = wp.Position
		for _, door in ipairs(doors) do
			local doorPos = door:IsA("BasePart") and door.Position or door:GetPivot().Position
			if Vector2.new(pos.X - doorPos.X, pos.Z - doorPos.Z).Magnitude < self.doorSnapRadius then
				pos = Vector3.new(doorPos.X, pos.Y, doorPos.Z)
				break
			end
		end
		table.insert(adjusted, pos)
	end
	return adjusted
end

function NPCNav:_MoveToCustom(targetPos, isValidFunc, isIdleWalk)
	if self.walkAnimation and not self.walkAnimation.IsPlaying then self.walkAnimation:Play() end
	if self.walkAnimation then self.walkAnimation:AdjustSpeed(self._walkSpeed / 18) end

	local startDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(self.rootPart.Position.X, 0, self.rootPart.Position.Z)).Magnitude
	local timeout = math.max(4, (startDist / self._walkSpeed) + 2)
	local startTime = os.clock()
	local lastIdleCheck = 0

	while true do
		local dt = RunService.Heartbeat:Wait()
		if not self.npc.Parent or self._isForcedStop then return false end

		if self.npc:GetAttribute("IsPaused") then
			if self.walkAnimation and self.walkAnimation.IsPlaying then self.walkAnimation:Stop(0.2) end
			while self.npc:GetAttribute("IsPaused") and self.npc.Parent and not self._isForcedStop do
				self:ManageCloudUnderFeet(self.rootPart.Position)
				task.wait(0.5)
				startTime = os.clock()
			end
			if not self.npc.Parent or self._isForcedStop then return false end
			if self.walkAnimation and not self.walkAnimation.IsPlaying then self.walkAnimation:Play() end
			if self.walkAnimation then self.walkAnimation:AdjustSpeed(self._walkSpeed / 18) end
		end

		if os.clock() - startTime > timeout then return false end

		if isIdleWalk and self.hasWorkCheck and (os.clock() - lastIdleCheck > 0.5) then
			lastIdleCheck = os.clock()
			if self.hasWorkCheck() then return false end
		end

		if isValidFunc and not isValidFunc() then return false end

		local currentPos = self.rootPart.Position
		local target2D = self:_SnapToDoorCenter(Vector3.new(targetPos.X, 0, targetPos.Z))
		local current2D = Vector3.new(currentPos.X, 0, currentPos.Z)
		local dist2D = (target2D - current2D).Magnitude

		if dist2D < 0.2 then break end

		local moveStep = self._walkSpeed * dt
		local dir = (target2D - current2D).Unit

		if self.checkWalls then
			local wallCheck = workspace:Raycast(currentPos, dir * 1.5, self:_GetWallRayParams())
			if wallCheck then return false end
		end

		local newPos2D = (moveStep >= dist2D) and target2D or (current2D + dir * moveStep)

		local currentTargetY = self:GetTargetY(newPos2D.X, newPos2D.Z, currentPos.Y)
		local newY = currentPos.Y + (currentTargetY - currentPos.Y) * (1 - math.exp(-15 * dt))
		local newPos = Vector3.new(newPos2D.X, newY, newPos2D.Z)

		local lookDir = target2D - current2D
		if lookDir.Magnitude > 0.01 then
			local targetLook = lookDir.Unit
			local currentLook = self.rootPart.CFrame.LookVector
			local flatCurrent = Vector3.new(currentLook.X, 0, currentLook.Z)
			flatCurrent = flatCurrent.Magnitude > 0.001 and flatCurrent.Unit or targetLook
			local newLook = flatCurrent:Lerp(targetLook, 1 - math.exp(-self.turnSpeed * dt))
			if newLook.Magnitude > 0.001 then
				self.rootPart.CFrame = CFrame.lookAt(newPos, newPos + newLook.Unit)
			else
				self.rootPart.CFrame = CFrame.lookAt(newPos, newPos + targetLook)
			end
		else
			local currentLook = self.rootPart.CFrame.LookVector
			local flatCurrent = Vector3.new(currentLook.X, 0, currentLook.Z)
			if flatCurrent.Magnitude > 0.001 then
				self.rootPart.CFrame = CFrame.lookAt(newPos, newPos + flatCurrent.Unit)
			else
				self.rootPart.CFrame = CFrame.new(newPos)
			end
		end

		self:ManageCloudUnderFeet(self.rootPart.Position)
		if moveStep >= dist2D then break end
	end

	self:ManageCloudUnderFeet(self.rootPart.Position)
	return true
end

function NPCNav:WalkSmart(targetPos, watchObjectOrFn, isIdleWalk)
	local isValidFunc = self:_ResolveValidator(watchObjectOrFn)
	local profileName = self.getPathProfile()
	local path = self._paths[profileName] or self._paths.Default
	local moveResult = true

	if path then
		local success = pcall(function() path:ComputeAsync(self.rootPart.Position, targetPos) end)
		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = self:_SnapWaypointsToDoors(path:GetWaypoints())
			if self.walkAnimation and not self.walkAnimation.IsPlaying then self.walkAnimation:Play() end
			for i, pos in ipairs(waypoints) do
				if i > 1 then
					moveResult = self:_MoveToCustom(pos, isValidFunc, isIdleWalk)
					if not moveResult then break end
				end
			end
		else
			moveResult = self:_MoveToCustom(targetPos, isValidFunc, isIdleWalk)
		end
	else
		moveResult = self:_MoveToCustom(targetPos, isValidFunc, isIdleWalk)
	end

	if self.walkAnimation then self.walkAnimation:Stop(0.2) end
	self:ManageCloudUnderFeet(self.rootPart.Position)
	return moveResult
end


function NPCNav:_GetNearestElevator()
	local curFloor = self:GetFloorFromY(self.rootPart.Position.Y)
	local closest, minDist = nil, math.huge
	local sameFloorClosest, sameFloorMinDist = nil, math.huge

	for _, obj in ipairs(self:GetObjectsInPlot("Elevator")) do
		if obj:FindFirstChild("TargetPart") then
			local dist = (Vector3.new(self.rootPart.Position.X, 0, self.rootPart.Position.Z) - Vector3.new(obj.TargetPart.Position.X, 0, obj.TargetPart.Position.Z)).Magnitude
			if dist < minDist then minDist = dist; closest = obj end
			if self:GetFloorFromY(obj.TargetPart.Position.Y) == curFloor and dist < sameFloorMinDist then
				sameFloorMinDist = dist
				sameFloorClosest = obj
			end
		end
	end

	return sameFloorClosest or closest
end

function NPCNav:_UseElevator(targetFloor, isValidFunc)
	if self._isForcedStop then return false end
	local elevator = self:_GetNearestElevator()
	if not elevator then return false end
	local tPart = elevator.TargetPart
	local baseFloorY = self:GetBaseFloorY(self.rootPart.Position.Y)

	local entryPos = Vector3.new(tPart.Position.X, baseFloorY, tPart.Position.Z) + (tPart.CFrame.LookVector * 2.5)

	if not self:WalkSmart(entryPos, elevator, false) then return false end
	task.wait(0.2)
	if not self:IsValid(elevator) or not self:IsValid(tPart) or self._isForcedStop then return false end
	if isValidFunc and not isValidFunc() then return false end

	local faceDir = Vector3.new(-tPart.CFrame.LookVector.X, 0, -tPart.CFrame.LookVector.Z)
	if faceDir.Magnitude > 0.001 then
		self.rootPart.CFrame = CFrame.lookAt(self.rootPart.Position, self.rootPart.Position + faceDir.Unit)
	end

	self:HideWalkCloud()
	self:PlayDespawnEffect()

	local plotSurfaceY = self:GetPlotSurfaceY()
	local teleFloorY = plotSurfaceY + ((targetFloor - 1) * self.floorHeight)

	local telePos2D = Vector3.new(tPart.Position.X, teleFloorY, tPart.Position.Z) + (tPart.CFrame.LookVector * 2.5)
	local tY = self:GetTargetY(telePos2D.X, telePos2D.Z, teleFloorY)
	local telePos = Vector3.new(telePos2D.X, tY, telePos2D.Z)

	local lookOut = Vector3.new(tPart.CFrame.LookVector.X, 0, tPart.CFrame.LookVector.Z)
	lookOut = lookOut.Magnitude < 0.001 and Vector3.new(0, 0, 1) or lookOut.Unit

	self:PlaySpawnEffect(CFrame.lookAt(telePos, telePos + lookOut))

	local exitPos = telePos + (lookOut * 5)
	self:WalkSmart(exitPos, elevator, false)
	return true
end

function NPCNav:NavigateTo(targetPos, watchObjectOrFn, isIdleWalk)
	if self._isForcedStop then return false end
	local isValidFunc = self:_ResolveValidator(watchObjectOrFn)
	if isValidFunc and not isValidFunc() then return false end

	local curFloor = self:GetFloorFromY(self.rootPart.Position.Y)
	local tarFloor = self:GetFloorFromY(targetPos.Y)

	if curFloor ~= tarFloor then
		local success = self:_UseElevator(tarFloor, isValidFunc)
		if not success and not self._isForcedStop then
			if isValidFunc and not isValidFunc() then return false end

			local plotSurfaceY = self:GetPlotSurfaceY()
			local teleFloorY = plotSurfaceY + ((tarFloor - 1) * self.floorHeight)
			local tY = self:GetTargetY(self.rootPart.Position.X, self.rootPart.Position.Z, teleFloorY)

			self:HideWalkCloud()
			self:PlayDespawnEffect()
			local flatLook = Vector3.new(self.rootPart.CFrame.LookVector.X, 0, self.rootPart.CFrame.LookVector.Z)
			flatLook = flatLook.Magnitude < 0.001 and Vector3.new(0, 0, 1) or flatLook.Unit
			self:PlaySpawnEffect(CFrame.lookAt(
				Vector3.new(self.rootPart.Position.X, tY, self.rootPart.Position.Z),
				Vector3.new(self.rootPart.Position.X, tY, self.rootPart.Position.Z) + flatLook
				))
		end
	end

	return self:WalkSmart(targetPos, watchObjectOrFn, isIdleWalk)
end

return NPCNav
