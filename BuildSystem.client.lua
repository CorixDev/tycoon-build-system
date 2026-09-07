local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera


local buySound = Instance.new("Sound")
buySound.SoundId = "rbxassetid://97581798253575"; buySound.Volume = 1; buySound.PlaybackSpeed = 1.25; buySound.Parent = SoundService
local eqBuy = Instance.new("EqualizerSoundEffect", buySound); eqBuy.LowGain = 2; eqBuy.MidGain = 0; eqBuy.HighGain = 4

local preloadedClickSound = Instance.new("Sound")
preloadedClickSound.SoundId = "rbxassetid://81772182509811"; preloadedClickSound.Volume = 0.4; preloadedClickSound.PlaybackSpeed = 1.15; preloadedClickSound.Parent = SoundService
local clickEq = Instance.new("EqualizerSoundEffect", preloadedClickSound); clickEq.LowGain = -6; clickEq.MidGain = 0; clickEq.HighGain = 4

local preloadedUpgradeSound = Instance.new("Sound")
preloadedUpgradeSound.SoundId = "rbxassetid://8400923343"; preloadedUpgradeSound.Volume = 0.35; preloadedUpgradeSound.PlaybackSpeed = 1.35; preloadedUpgradeSound.Parent = SoundService

local errorSound = Instance.new("Sound")
errorSound.SoundId = "rbxassetid://3081546938"; errorSound.Volume = 0.5; errorSound.Parent = SoundService

local confettiSound = Instance.new("Sound")
confettiSound.SoundId = "rbxassetid://89481514209130"; confettiSound.Volume = 0.8; confettiSound.Parent = SoundService

local function PlayClickSound() local s = preloadedClickSound:Clone(); s.Parent = SoundService; s:Play(); s.Ended:Connect(function() s:Destroy() end) end
local function PlayBuySound() local s = buySound:Clone(); s.Parent = SoundService; s:Play(); s.Ended:Connect(function() s:Destroy() end) end
local function PlayUpgradeSound() local s = preloadedUpgradeSound:Clone(); s.Parent = SoundService; s:Play(); s.Ended:Connect(function() s:Destroy() end) end
local function PlayErrorSound() local s = errorSound:Clone(); s.Parent = SoundService; s:Play(); s.Ended:Connect(function() s:Destroy() end) end
local function PlayConfettiSound() local s = confettiSound:Clone(); s.Parent = SoundService; s:Play(); s.Ended:Connect(function() s:Destroy() end) end

task.spawn(function() pcall(function() ContentProvider:PreloadAsync({buySound, preloadedClickSound, preloadedUpgradeSound, errorSound, confettiSound}) end) end)

local plotName = player:GetAttribute("AssignedPlot")
while not plotName do task.wait(0.2); plotName = player:GetAttribute("AssignedPlot") end
local PLOT = Workspace:WaitForChild(plotName)

local function GetPlotGround(plot)
	if not plot then return nil end
	if plot:IsA("BasePart") then return plot end
	if plot.PrimaryPart then return plot.PrimaryPart end
	local floor = plot:FindFirstChild("Floor") or plot:FindFirstChild("Base") or plot:FindFirstChild("Ground")
	if floor and floor:IsA("BasePart") then return floor end
	for _, child in pairs(plot:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Entrance" and child.Name ~= "Exit" then return child end
	end
	return plot:FindFirstChildWhichIsA("BasePart")
end

local GROUND = GetPlotGround(PLOT)
while not GROUND do task.wait(0.2); GROUND = GetPlotGround(PLOT) end

local SURFACE_ITEMS = { ["Monitor"] = true }
local CEILING_ITEMS = { ["CeilingLamp"] = true, ["Chandelier"] = true }
local IS_FLOOR = { ["WoodTile"] = true, ["AsphaltTile"] = true, ["CheckeredTile"] = true }

local function IsWallType(name)
	return name == "Wall" or name == "PanoramWall" or name == "DoorWall" or name == "Window" or name == "Door" or name == "CheckeredWall"
end
local function IsSurfaceItem(name) return SURFACE_ITEMS[name] == true end

local ITEM_SORT_ORDER = {
	WoodTile = 1, AsphaltTile = 2, CheckeredTile = 3, 
	Wall = 10, CheckeredWall = 11, Window = 12, DoorWall = 13, PanoramWall = 14, Door = 15, 
	Table = 20, CTable = 21, Desc = 22, ServiceCounter = 23, CashRegister = 24, 
	Chair = 30, Stove = 40, Dispenser = 41, CeilingLamp = 50, Chandelier = 51, 
	Monitor = 60, Elevator = 70
}

local ITEM_PRICES = {
	WoodTile = 15, AsphaltTile = 15, CheckeredTile = 20, 
	Wall = 35, CheckeredWall = 40, Window = 50, DoorWall = 60, PanoramWall = 90,
	Door = 45, Chair = 40, Table = 80, CTable = 200, CeilingLamp = 40,
	Chandelier = 250, CashRegister = 300, Monitor = 200, Elevator = 1000,
	Stove = 1000, Dispenser = 500, ServiceCounter = 650, Desc = 120
}

local MY_PLOT_GRID = player.Name .. "_PlotGridFolder"
local MY_PROC_GRID = player.Name .. "_ProceduralGrid"
local MY_PLANE = player.Name .. "_BuildPlane_Temp"

for _, child in pairs(Workspace:GetChildren()) do
	if child.Name == MY_PLOT_GRID or child.Name == MY_PROC_GRID or child.Name == MY_PLANE then child:Destroy() end
end

local BuildSystem = ReplicatedStorage:WaitForChild("BuildSystem")
local PlaceItemEvent = BuildSystem:WaitForChild("PlaceItem")
local RemoveItemEvent = BuildSystem:WaitForChild("RemoveItem")
local Furniture = BuildSystem:WaitForChild("Furniture")

local BuildEvents = ReplicatedStorage:WaitForChild("BuildEvents")
local GetPlotsFunc = BuildEvents:WaitForChild("GetPlots")
local BuyPlotFunc = BuildEvents:WaitForChild("BuyPlot")
local PlotBought = BuildEvents:WaitForChild("PlotBought")

local GAMEPASS_ID = 1736764083 
local PLOT_PRICE = 50000

local GRID = 5
local HALF_GRID = 2.5
local ROTATION_SNAP = 90
local ITEM_GRID_SIZE = 2.5
local COLLISION_SHRINK = 0.05
local FLOOR_HEIGHT = 12

local LINE_COLOR = Color3.fromRGB(0, 255, 255)
local LINE_TRANSPARENCY = 0.65 

local COLS = {"A", "B", "C", "D", "E", "F", "G"}
local ownedPlots = {}
local plotVisuals = {}
local PlotGridFolder = Instance.new("Folder", Workspace); PlotGridFolder.Name = MY_PLOT_GRID

local hoveredPlotId = nil; local selectedPlotToBuy = nil
local isBuildModeOpen = false; local isPlacing = false; local isDeleting = false; local isMovingMode = false 
local lastHitPos = nil 

local currentItemName = nil; local currentRotation = 0
local ghostsCache = {}; local gridFolder = nil; local buildPlane = nil
local currentFloor = 1; local lastPhysicalFloor = 1   
local premiumUI = nil; local activeMoveInput = nil

local selectionBox = Instance.new("SelectionBox")
selectionBox.LineThickness = 0.15; selectionBox.Color3 = Color3.fromRGB(255, 50, 50); selectionBox.SurfaceTransparency = 0.75; selectionBox.Parent = player.PlayerGui

local CELL_X = GROUND.Size.X / 7; local CELL_Z = GROUND.Size.Z / 7
local SMALL_SIZE = Vector3.new(0.05, 0.2, 0.05); local FULL_SIZE = Vector3.new(CELL_X - 0.5, 0.2, CELL_Z - 0.5)

local COLOR_PREMIUM_1 = Color3.fromRGB(0, 255, 128); local COLOR_PREMIUM_2 = Color3.fromRGB(0, 100, 40)  
local COLOR_GP_1 = Color3.fromRGB(255, 210, 30); local COLOR_GP_2 = Color3.fromRGB(180, 80, 10)

local gradCash = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 255, 150)), ColorSequenceKeypoint.new(1, COLOR_PREMIUM_2)})
local gradGP = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 100)), ColorSequenceKeypoint.new(1, COLOR_GP_2)})

local plotUI = Instance.new("BillboardGui"); plotUI.Name = "PremiumPlotUI"; plotUI.Size = UDim2.fromOffset(260, 125); plotUI.StudsOffset = Vector3.new(0, 1.5, 0); plotUI.AlwaysOnTop = true; plotUI.MaxDistance = 150; plotUI.LightInfluence = 0; plotUI.Enabled = false; plotUI.Parent = player.PlayerGui
local canvasGroup = Instance.new("CanvasGroup", plotUI); canvasGroup.Size = UDim2.fromScale(1, 1); canvasGroup.BackgroundTransparency = 1; canvasGroup.GroupTransparency = 1
local mainFrame = Instance.new("Frame", canvasGroup); mainFrame.Size = UDim2.fromScale(1, 1); mainFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 14)
local bgGradient = Instance.new("UIGradient", mainFrame); bgGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 30, 20)), ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 10, 5))}); bgGradient.Rotation = 45
local uiStroke = Instance.new("UIStroke", mainFrame); uiStroke.Color = COLOR_PREMIUM_1; uiStroke.Thickness = 2.5

local uiTitle = Instance.new("TextLabel", mainFrame); uiTitle.Size = UDim2.new(1, 0, 0, 30); uiTitle.Position = UDim2.new(0, 0, 0, 10); uiTitle.BackgroundTransparency = 1; uiTitle.Font = Enum.Font.GothamMedium; uiTitle.Text = "ZONE EXPANSION"; uiTitle.TextColor3 = Color3.fromRGB(180, 255, 180); uiTitle.TextScaled = true; local tCons = Instance.new("UITextSizeConstraint", uiTitle); tCons.MaxTextSize = 14; tCons.MinTextSize = 8; uiTitle.TextTransparency = 0.2
local priceLabel = Instance.new("TextLabel", mainFrame); priceLabel.Size = UDim2.new(1, -20, 0, 45); priceLabel.Position = UDim2.new(0.5, 0, 0, 35); priceLabel.AnchorPoint = Vector2.new(0.5, 0); priceLabel.BackgroundTransparency = 1; priceLabel.Font = Enum.Font.GothamBlack; priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255); priceLabel.TextScaled = true; local pCons = Instance.new("UITextSizeConstraint", priceLabel); pCons.MaxTextSize = 34; pCons.MinTextSize = 10; local textGradient = Instance.new("UIGradient", priceLabel)
local subText = Instance.new("TextLabel", mainFrame); subText.Size = UDim2.new(1, -20, 0, 20); subText.Position = UDim2.new(0.5, 0, 0, 90); subText.AnchorPoint = Vector2.new(0.5, 0); subText.BackgroundTransparency = 1; subText.Font = Enum.Font.Gotham; subText.Text = "Click AGAIN to purchase!"; subText.TextColor3 = Color3.fromRGB(255, 200, 100); subText.TextScaled = true; local sCons = Instance.new("UITextSizeConstraint", subText); sCons.MaxTextSize = 12; sCons.MinTextSize = 6


local isTutorialMode = not player:GetAttribute("TutorialDone")
local activePointer = nil
local tutorialConnection = nil
local tutorialStep = 1 

local function ClearTutorialPointer()
	if tutorialConnection then
		tutorialConnection:Disconnect()
		tutorialConnection = nil
	end
	if activePointer then
		activePointer:Destroy()
		activePointer = nil
	end
end

local function CreateTutorialPointer(targetGui, mode)
	ClearTutorialPointer()
	if not targetGui then return end

	activePointer = Instance.new("Frame")
	activePointer.Name = "TutorialPointer"
	activePointer.Size = UDim2.new(0, 55, 0, 55) 
	activePointer.BackgroundTransparency = 1
	activePointer.ZIndex = 100000 

	local emojiLabel = Instance.new("TextLabel", activePointer)
	emojiLabel.Size = UDim2.fromScale(1, 1)
	emojiLabel.BackgroundTransparency = 1
	emojiLabel.TextScaled = true
	emojiLabel.ZIndex = 100001

	local constraint = Instance.new("UITextSizeConstraint", emojiLabel)
	constraint.MinTextSize = 20
	constraint.MaxTextSize = 55

	local shadow = Instance.new("UIStroke", emojiLabel)
	shadow.Color = Color3.fromRGB(0, 0, 0)
	shadow.Transparency = 0.3
	shadow.Thickness = 3

	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	if mode == "Down" then
		emojiLabel.Text = "👇"
		activePointer.Parent = targetGui
		activePointer.AnchorPoint = Vector2.new(0.5, 1)
		activePointer.Position = UDim2.new(0.5, 0, 0, -5)

		TweenService:Create(activePointer, tweenInfo, {Position = UDim2.new(0.5, 0, 0, 10)}):Play()
	else
		local tutGui = player.PlayerGui:FindFirstChild("TutorialUI_AAA")
		if not tutGui then
			tutGui = Instance.new("ScreenGui")
			tutGui.Name = "TutorialUI_AAA"
			tutGui.DisplayOrder = 100000 
			tutGui.ResetOnSpawn = false
			tutGui.Parent = player.PlayerGui
		end
		activePointer.Parent = tutGui

		local animOffsetValue = Instance.new("NumberValue", activePointer)

		if mode == "Up" then
		
			emojiLabel.Text = "👆"
			activePointer.AnchorPoint = Vector2.new(0.5, 0) 
			animOffsetValue.Value = 20 

			TweenService:Create(animOffsetValue, tweenInfo, {Value = 5}):Play() 

			tutorialConnection = RunService.RenderStepped:Connect(function()
				if targetGui and targetGui.Parent then
					local absPos = targetGui.AbsolutePosition
					local absSize = targetGui.AbsoluteSize
					activePointer.Position = UDim2.new(0, absPos.X + (absSize.X / 2), 0, absPos.Y + absSize.Y + animOffsetValue.Value)
				else
					ClearTutorialPointer()
				end
			end)

		elseif mode == "Down_Stove" then
			emojiLabel.Text = "👇"
			activePointer.AnchorPoint = Vector2.new(0.5, 1) 
			animOffsetValue.Value = -20 

			TweenService:Create(animOffsetValue, tweenInfo, {Value = -5}):Play() 

			tutorialConnection = RunService.RenderStepped:Connect(function()
				if targetGui and targetGui.Parent then
					local absPos = targetGui.AbsolutePosition
					local absSize = targetGui.AbsoluteSize
					activePointer.Position = UDim2.new(0, absPos.X + (absSize.X / 2), 0, absPos.Y + animOffsetValue.Value)
				else
					ClearTutorialPointer()
				end
			end)
		end
	end
end

local function PlayConfettiDopamine()
	PlayConfettiSound()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ConfettiUI"
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	local colors = {
		Color3.fromRGB(255, 59, 48), Color3.fromRGB(0, 122, 255), 
		Color3.fromRGB(52, 199, 89), Color3.fromRGB(255, 204, 0), Color3.fromRGB(175, 82, 222)
	}

	for i = 1, 60 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.new(0, math.random(8, 14), 0, math.random(8, 14))
		piece.Position = UDim2.new(0.5, 0, 0.5, 0)
		piece.BackgroundColor3 = colors[math.random(1, #colors)]
		piece.BorderSizePixel = 0
		piece.ZIndex = 100

		local corner = Instance.new("UICorner", piece)
		corner.CornerRadius = UDim.new(math.random(0, 1) == 1 and 0 or 0.5, 0)

		piece.Parent = screenGui

		local angle = math.rad(math.random(0, 360))
		local dist = math.random(100, 500)
		local targetX = math.cos(angle) * dist
		local targetY = math.sin(angle) * dist

		local spreadTween = TweenService:Create(piece, TweenInfo.new(math.random(4, 7)/10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, targetX, 0.5, targetY),
			Rotation = math.random(-360, 360)
		})

		spreadTween:Play()
		spreadTween.Completed:Connect(function()
			TweenService:Create(piece, TweenInfo.new(math.random(10, 15)/10, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, targetX + math.random(-50, 50), 1.2, 0),
				Rotation = piece.Rotation + math.random(-360, 360),
				BackgroundTransparency = 1
			}):Play()
		end)
	end

	task.delay(3, function() screenGui:Destroy() end)
end

local function UnlockBuildMenu()
	local gui = player.PlayerGui:FindFirstChild("BuildGui")
	if gui then
		local scroller = gui:FindFirstChild("BottomDock") and gui.BottomDock:FindFirstChild("Content") and gui.BottomDock.Content:FindFirstChild("ItemsScroller")
		if scroller then
			for _, child in pairs(scroller:GetChildren()) do
				if child:IsA("GuiButton") and child.Name:sub(1, 6) == "Button" then
					local itemName = child.Name:sub(7)
					if itemName ~= "Cloud" and itemName ~= "DeprecatedCloud" then
						child.Visible = true
					end
				end
			end
		end
	end
end

player:GetAttributeChangedSignal("TutorialDone"):Connect(function()
	isTutorialMode = not player:GetAttribute("TutorialDone")
	if not isTutorialMode then
		ClearTutorialPointer()
		UnlockBuildMenu()
	end
end)

task.spawn(function()
	if isTutorialMode and tutorialStep == 1 then
		local hud = player.PlayerGui:WaitForChild("TycoonHUD_Ultimate", 10)
		if hud then
			local moneyContainer = hud:WaitForChild("MoneyContainer", 5)
			if moneyContainer then
				local buildBtn = moneyContainer:WaitForChild("BuildButton", 5)
				if buildBtn then
					CreateTutorialPointer(buildBtn, "Up")
				end
			end
		end
	end
end)

local function IsGamepassPlot(col, row) return col == "A" or col == "G" or row == 1 end
local function GetPlotIdFromPos(worldPos)
	local relPos = GROUND.CFrame:PointToObjectSpace(worldPos)
	local colIndex = math.clamp(math.floor((relPos.X + (GROUND.Size.X / 2)) / CELL_X) + 1, 1, 7)
	local rowIndex = math.clamp(math.floor((relPos.Z + (GROUND.Size.Z / 2)) / CELL_Z) + 1, 1, 7)
	return COLS[colIndex] .. tostring(rowIndex)
end

local function GeneratePlots()
	local startY = GROUND.Position.Y + (GROUND.Size.Y / 2) + 0.1
	local cornerCFrame = GROUND.CFrame * CFrame.new(-GROUND.Size.X/2 + CELL_X/2, 0, -GROUND.Size.Z/2 + CELL_Z/2)
	for c = 1, 7 do
		for r = 1, 7 do
			local id = COLS[c] .. tostring(r)
			local hitbox = Instance.new("Part"); hitbox.Name = id; hitbox.Size = Vector3.new(CELL_X, 0.5, CELL_Z)
			hitbox.CFrame = cornerCFrame * CFrame.new((c-1)*CELL_X, startY - GROUND.Position.Y, (r-1)*CELL_Z)
			hitbox.Anchored = true; hitbox.CanCollide = false; hitbox.Transparency = 1; hitbox.Parent = PlotGridFolder

			local visual = Instance.new("Part"); visual.Name = "Visual"; visual.Size = SMALL_SIZE
			visual.CFrame = hitbox.CFrame; visual.Anchored = true; visual.CanCollide = false; visual.CanQuery = false
			visual.Material = Enum.Material.SmoothPlastic; visual.Transparency = 1; visual.Parent = hitbox

			local sg = Instance.new("SurfaceGui", visual); sg.Face = Enum.NormalId.Top; sg.LightInfluence = 0; sg.ZOffset = 1; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 25
			local frame = Instance.new("Frame", sg); frame.Size = UDim2.fromScale(1, 1); frame.BackgroundColor3 = Color3.new(1, 1, 1); frame.BackgroundTransparency = 1; frame.BorderSizePixel = 0; Instance.new("UICorner", frame).CornerRadius = UDim.new(0.05, 0)
			local grad = Instance.new("UIGradient", frame); grad.Rotation = 45
			local outline = Instance.new("UIStroke", frame); outline.Color = Color3.fromRGB(0, 0, 0); outline.Thickness = 2.5; outline.Transparency = 1; outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

			plotVisuals[id] = {Hitbox = hitbox, Visual = visual, Frame = frame, Gradient = grad, Outline = outline}
		end
	end
end

local function ShowPlotUI(hitId)
	if not hitId or not plotVisuals[hitId] then return end
	local isGP = IsGamepassPlot(string.sub(hitId, 1, 1), tonumber(string.sub(hitId, 2, 2)))

	if isGP then
		priceLabel.Text = "★ GAMEPASS"; textGradient.Color = gradGP; uiStroke.Color = COLOR_GP_1; uiTitle.TextColor3 = Color3.fromRGB(255, 240, 150)
	else
		local formattedPrice = tostring(PLOT_PRICE):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
		priceLabel.Text = "💵 $" .. formattedPrice; textGradient.Color = gradCash; uiStroke.Color = COLOR_PREMIUM_1; uiTitle.TextColor3 = Color3.fromRGB(200, 255, 200)
	end

	plotUI.Adornee = plotVisuals[hitId].Visual; plotUI.Enabled = true; plotUI.StudsOffset = Vector3.new(0, 1.5, 0)
	TweenService:Create(plotUI, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {StudsOffset = Vector3.new(0, 4, 0)}):Play()
	TweenService:Create(canvasGroup, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()
end

local function ClosePlotUI()
	if plotUI.Enabled then
		TweenService:Create(canvasGroup, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {GroupTransparency = 1}):Play()
		TweenService:Create(plotUI, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {StudsOffset = Vector3.new(0, 1.5, 0)}):Play()
		task.delay(0.2, function() if not selectedPlotToBuy then plotUI.Enabled = false end end)
	end
end

local function UpdatePlotVisualState(id)
	if not plotVisuals[id] then return end
	local data = plotVisuals[id]; local vis = data.Visual; local hit = data.Hitbox; local frame = data.Frame; local grad = data.Gradient; local outline = data.Outline

	local isGP = IsGamepassPlot(string.sub(id, 1, 1), tonumber(string.sub(id, 2, 2)))
	local cBase = isGP and COLOR_GP_1 or COLOR_PREMIUM_1; local cDark = isGP and COLOR_GP_2 or COLOR_PREMIUM_2
	vis.Color = cBase; if grad then grad.Color = ColorSequence.new(cBase, cDark) end

	if ownedPlots[id] == true or not isBuildModeOpen or isPlacing or isDeleting then
		hit.CanQuery = false
		TweenService:Create(vis, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {Size = SMALL_SIZE, Transparency = 1}):Play()
		if frame then TweenService:Create(frame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play() end
		if outline then TweenService:Create(outline, TweenInfo.new(0.3), {Transparency = 1}):Play() end
		task.delay(0.3, function() if frame and frame.Parent and (ownedPlots[id] == true or not isBuildModeOpen or isPlacing or isDeleting) then frame.Visible = false end end)
		return
	end

	hit.CanQuery = true; if frame then frame.Visible = true end
	local targetTrans = 1; local targetSize = FULL_SIZE 
	local strokeTrans = 0.65; local strokeColor = Color3.fromRGB(0, 0, 0); local targetBgTrans = 1

	if selectedPlotToBuy == id then 
		targetTrans = 0.2; targetSize = FULL_SIZE + Vector3.new(0.5, 0, 0.5); strokeTrans = 0; strokeColor = Color3.new(1, 1, 1); targetBgTrans = 0.2
		vis.Color = Color3.new(1, 1, 1); if grad then grad.Color = ColorSequence.new(Color3.new(1,1,1), cBase) end
	elseif hoveredPlotId == id then
		targetTrans = 0.2; strokeTrans = 0; strokeColor = cBase; targetBgTrans = 0.8
	end

	TweenService:Create(vis, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = targetSize, Transparency = targetTrans}):Play()
	if outline then TweenService:Create(outline, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Transparency = strokeTrans, Color = strokeColor}):Play() end
	if frame then TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = targetBgTrans}):Play() end
end

local function UpdateBuildPlane()
	if buildPlane then buildPlane:Destroy() end

	local yOffset = (currentFloor - 1) * FLOOR_HEIGHT
	if isPlacing and currentItemName and CEILING_ITEMS[currentItemName] then yOffset = yOffset + 11.8 end

	buildPlane = Instance.new("Part", Workspace); buildPlane.Name = MY_PLANE; buildPlane.Anchored = true; buildPlane.CanCollide = false; buildPlane.CanQuery = true; buildPlane.Transparency = 1
	buildPlane.Size = Vector3.new(GROUND.Size.X + 40, 0.1, GROUND.Size.Z + 40)
	buildPlane.Position = Vector3.new(GROUND.Position.X, GROUND.Position.Y + (GROUND.Size.Y / 2) + yOffset, GROUND.Position.Z)
end

local function UpdateGridState(isEnabled)
	if gridFolder then gridFolder:Destroy(); gridFolder = nil end
	if buildPlane then buildPlane:Destroy(); buildPlane = nil end
	if not isEnabled then return end

	UpdateBuildPlane()
	gridFolder = Instance.new("Folder", Workspace); gridFolder.Name = MY_PROC_GRID
	local floorOffset = (currentFloor - 1) * FLOOR_HEIGHT
	local yOffset = floorOffset
	if isPlacing and currentItemName and CEILING_ITEMS[currentItemName] then yOffset = floorOffset + 11.8 end

	local cornerCFrame = GROUND.CFrame * CFrame.new(-GROUND.Size.X/2, (GROUND.Size.Y/2) + yOffset + 0.05, -GROUND.Size.Z/2)
	local createdLines = {} 

	local function AddGridLine(cf, sizeX, sizeZ, isAxisX)
		local localPos = cornerCFrame:PointToObjectSpace(cf.Position)
		local key = string.format("%.2f_%.2f_%s", math.round(localPos.X * 100) / 100, math.round(localPos.Z * 100) / 100, isAxisX and "X" or "Z")
		if not createdLines[key] then
			createdLines[key] = true
			local line = Instance.new("Part", gridFolder); line.Anchored = true; line.CanCollide = false; line.CanQuery = false; line.CastShadow = false
			line.Material = Enum.Material.Neon; line.Color = LINE_COLOR; line.Transparency = LINE_TRANSPARENCY
			line.Size = Vector3.new(sizeX, 0.05, sizeZ); line.CFrame = cf * CFrame.new(0, isAxisX and 0.01 or -0.01, 0)
		end
	end

	for id, isOwned in pairs(ownedPlots) do
		if isOwned ~= true then continue end
		local plotData = plotVisuals[id]
		if not plotData or not plotData.Hitbox then continue end

		local hitbox = plotData.Hitbox
		local localPos = cornerCFrame:PointToObjectSpace(hitbox.Position)
		local minX = localPos.X - hitbox.Size.X/2; local maxX = localPos.X + hitbox.Size.X/2
		local minZ = localPos.Z - hitbox.Size.Z/2; local maxZ = localPos.Z + hitbox.Size.Z/2

		local startX = math.ceil((minX - 0.01) / GRID) * GRID
		for x = startX, maxX + 0.01, GRID do AddGridLine(cornerCFrame * CFrame.new(x, 0, (minZ + maxZ)/2), 0.1, hitbox.Size.Z, false) end
		local startZ = math.ceil((minZ - 0.01) / GRID) * GRID
		for z = startZ, maxZ + 0.01, GRID do AddGridLine(cornerCFrame * CFrame.new((minX + maxX)/2, 0, z), hitbox.Size.X, 0.1, true) end
	end
end

task.spawn(function()
	local success, serverData = pcall(function() return GetPlotsFunc:InvokeServer() end)
	ownedPlots = {}
	if success and type(serverData) == "table" then
		for k, v in pairs(serverData) do if type(k) == "number" then ownedPlots[tostring(v)] = true else ownedPlots[tostring(k)] = (v == true) end end
	end
	GeneratePlots(); for id in pairs(plotVisuals) do UpdatePlotVisualState(id) end
	if isBuildModeOpen then UpdateGridState(true) end 
end)

PlotBought.OnClientEvent:Connect(function(id)
	local isGP = IsGamepassPlot(string.sub(id, 1, 1), tonumber(string.sub(id, 2, 2)))

	if isGP then PlayUpgradeSound() else PlayBuySound() end

	ownedPlots[id] = true
	if isBuildModeOpen then UpdateGridState(true) end

	local wasHovered = (hoveredPlotId == id)
	if wasHovered or selectedPlotToBuy == id then hoveredPlotId = nil; selectedPlotToBuy = nil; ClosePlotUI() end
	UpdatePlotVisualState(id) 

	local data = plotVisuals[id]
	if data and data.Visual then
		local emitColor = isGP and COLOR_GP_1 or COLOR_PREMIUM_1

		task.spawn(function()
			local shockwave = Instance.new("Part"); shockwave.Size = Vector3.new(CELL_X, 0.1, CELL_Z); shockwave.CFrame = data.Hitbox.CFrame; shockwave.Anchored = true; shockwave.CanCollide = false
			shockwave.Material = Enum.Material.Neon; shockwave.Color = emitColor; shockwave.Transparency = 0.1; shockwave.Parent = Workspace
			TweenService:Create(shockwave, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = Vector3.new(CELL_X + 25, 0.1, CELL_Z + 25), Transparency = 1}):Play()
			game.Debris:AddItem(shockwave, 1)

			local light = Instance.new("PointLight", shockwave); light.Color = emitColor; light.Range = 40; light.Brightness = 15
			TweenService:Create(light, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Brightness = 0, Range = 0}):Play()

			local att = Instance.new("Attachment", data.Visual)
			local pe = Instance.new("ParticleEmitter", att); pe.Texture = "rbxassetid://244221440"; pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0)})
			pe.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1,1,1)), ColorSequenceKeypoint.new(0.2, emitColor), ColorSequenceKeypoint.new(1, emitColor)})
			pe.Speed = NumberRange.new(30, 70); pe.Lifetime = NumberRange.new(0.5, 1.2); pe.Drag = 4; pe.EmissionDirection = Enum.NormalId.Top; pe.LightEmission = 1; pe.ZOffset = 1; pe.SpreadAngle = Vector2.new(60, 60)
			pe:Emit(150)
			game.Debris:AddItem(att, 2)
		end)

		data.Visual.Color = Color3.new(1, 1, 1)
		if data.Frame then data.Frame.BackgroundColor3 = Color3.new(1, 1, 1); TweenService:Create(data.Frame, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play() end

		TweenService:Create(data.Visual, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Transparency = 1, Size = FULL_SIZE + Vector3.new(6, 0, 6)}):Play()
		if data.Frame then TweenService:Create(data.Frame, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play() end
		if data.Outline then TweenService:Create(data.Outline, TweenInfo.new(0.4), {Transparency = 1}):Play() end

		task.delay(0.6, function() if data.Visual then data.Visual.Size = SMALL_SIZE; data.Frame.BackgroundColor3 = Color3.new(1,1,1) end end)
	end
end)

local function GetHitbox(model) return model.PrimaryPart or model:FindFirstChild("Hitbox") or model:FindFirstChildWhichIsA("BasePart") end

local function PlayButtonAnimation(btn)
	if not btn then return end; local scale = btn:FindFirstChild("UIScale") or Instance.new("UIScale", btn)
	TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.85}):Play()
	task.delay(0.15, function() if scale.Parent then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play() end end)
end

local function CalculateGridCFrame(hitPosition, size)
	local cornerCF = GROUND.CFrame * CFrame.new(-GROUND.Size.X/2, 0, -GROUND.Size.Z/2); local relPos = cornerCF:PointToObjectSpace(hitPosition)
	local finalX, finalZ; local finalRot = currentRotation

	if IS_FLOOR[currentItemName] then 
		finalX = (math.floor(relPos.X / GRID) * GRID) + HALF_GRID; finalZ = (math.floor(relPos.Z / GRID) * GRID) + HALF_GRID; finalRot = 0
	elseif CEILING_ITEMS[currentItemName] then 
		finalX = math.floor(relPos.X / ITEM_GRID_SIZE + 0.5) * ITEM_GRID_SIZE; finalZ = math.floor(relPos.Z / ITEM_GRID_SIZE + 0.5) * ITEM_GRID_SIZE
	elseif IsWallType(currentItemName) then
		if math.abs(currentRotation - 90) < 0.1 or math.abs(currentRotation - 270) < 0.1 then 
			finalX = (math.floor(relPos.X / GRID) * GRID) + HALF_GRID; finalZ = math.round(relPos.Z / GRID) * GRID
		else 
			finalX = math.round(relPos.X / GRID) * GRID; finalZ = (math.floor(relPos.Z / GRID) * GRID) + HALF_GRID
		end
	else 
		finalX = math.floor(relPos.X / ITEM_GRID_SIZE + 0.5) * ITEM_GRID_SIZE; finalZ = math.floor(relPos.Z / ITEM_GRID_SIZE + 0.5) * ITEM_GRID_SIZE 
	end

	local worldPos = cornerCF:PointToWorldSpace(Vector3.new(finalX, 0, finalZ)); local floorOffset = (currentFloor - 1) * FLOOR_HEIGHT
	if IsSurfaceItem(currentItemName) then worldPos = Vector3.new(worldPos.X, hitPosition.Y + (size.Y / 2), worldPos.Z)
	elseif CEILING_ITEMS[currentItemName] then worldPos = Vector3.new(worldPos.X, GROUND.Position.Y + (GROUND.Size.Y/2) + floorOffset + 11.8, worldPos.Z)
	else worldPos = Vector3.new(worldPos.X, GROUND.Position.Y + (GROUND.Size.Y/2) + (size.Y/2) + floorOffset, worldPos.Z) end

	local rotCF = CFrame.Angles(0, math.rad(finalRot), 0)
	if currentItemName == "CeilingLamp" then rotCF = rotCF * CFrame.Angles(0, 0, math.rad(90)) end
	return CFrame.new(worldPos) * rotCF
end


local function HasSupport(cframe, size, itemName)
	local plotSurfaceY = GROUND.Position.Y + (GROUND.Size.Y / 2)
	local bottomY = cframe.Position.Y - (size.Y / 2)

	if math.abs(bottomY - plotSurfaceY) < 1.0 then return true end

	local supportParams = OverlapParams.new()
	local ItemHolder = PLOT:FindFirstChild("PlacedItems")
	if not ItemHolder then return false end
	supportParams.FilterDescendantsInstances = {ItemHolder}
	supportParams.FilterType = Enum.RaycastFilterType.Include

	if not CEILING_ITEMS[itemName] then
		local belowCF = cframe * CFrame.new(0, -size.Y/2 - 0.5, 0)
		local belowSize = Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2))
		local parts = Workspace:GetPartBoundsInBox(belowCF, belowSize, supportParams)
		for _, p in ipairs(parts) do
			local md = p:FindFirstAncestorOfClass("Model") or p
			if md.Parent == ItemHolder then
				local mdName = md.Name
				if IS_FLOOR[itemName] then
					if IsWallType(mdName) or mdName == "Elevator" then return true end
				elseif IsSurfaceItem(itemName) then
					if IS_FLOOR[mdName] or mdName == "Table" or mdName == "CTable" or mdName == "Desc" or mdName == "ServiceCounter" then return true end
				else
					if IS_FLOOR[mdName] or mdName == "Elevator" then return true end
				end
			end
		end
	end

	if CEILING_ITEMS[itemName] then
		local aboveCF = cframe * CFrame.new(0, size.Y/2 + 0.5, 0)
		local aboveSize = Vector3.new(math.max(0.1, size.X - 0.2), 1.0, math.max(0.1, size.Z - 0.2))
		local parts = Workspace:GetPartBoundsInBox(aboveCF, aboveSize, supportParams)
		for _, p in ipairs(parts) do
			local md = p:FindFirstAncestorOfClass("Model") or p
			if md.Parent == ItemHolder and IS_FLOOR[md.Name] then return true end
		end
	end

	if IS_FLOOR[itemName] then
		local adjCF = cframe
		local adjSizeX = Vector3.new(size.X + 0.5, size.Y + 1.0, math.max(0.1, size.Z - 0.2))
		local partsX = Workspace:GetPartBoundsInBox(adjCF, adjSizeX, supportParams)
		for _, p in ipairs(partsX) do
			local md = p:FindFirstAncestorOfClass("Model") or p
			if md.Parent == ItemHolder and (IS_FLOOR[md.Name] or md.Name == "Elevator") then return true end
		end

		local adjSizeZ = Vector3.new(math.max(0.1, size.X - 0.2), size.Y + 1.0, size.Z + 0.5)
		local partsZ = Workspace:GetPartBoundsInBox(adjCF, adjSizeZ, supportParams)
		for _, p in ipairs(partsZ) do
			local md = p:FindFirstAncestorOfClass("Model") or p
			if md.Parent == ItemHolder and (IS_FLOOR[md.Name] or md.Name == "Elevator") then return true end
		end
	end

	return false
end

local function CheckValidity(cframe, size, ghostModel)
	local maxFloor = player:GetAttribute("MaxFloor") or 1
	local plotSurfaceY = GROUND.Position.Y + (GROUND.Size.Y / 2)
	local floorIndex = math.floor(((cframe.Position.Y - plotSurfaceY) + 0.01) / FLOOR_HEIGHT)
	local attemptFloor = floorIndex + 1

	if attemptFloor > maxFloor + 1 then return false end 
	if attemptFloor == maxFloor + 1 and not IS_FLOOR[currentItemName] then return false end 

	local boundsX, boundsZ = size.X, size.Z
	local rotToCheck = IS_FLOOR[currentItemName] and 0 or currentRotation
	if (math.abs(rotToCheck - 90) < 0.1 or math.abs(rotToCheck - 270) < 0.1) then boundsX, boundsZ = size.Z, size.X end

	local logicalBoundsX = boundsX; local logicalBoundsZ = boundsZ
	if IsWallType(currentItemName) then
		if logicalBoundsX > GRID then logicalBoundsX = GRID end
		if logicalBoundsZ > GRID then logicalBoundsZ = GRID end
	end

	local relPos = GROUND.CFrame:PointToObjectSpace(cframe.Position)
	if math.abs(relPos.X) > (GROUND.Size.X/2) + 0.5 or math.abs(relPos.Z) > (GROUND.Size.Z/2) + 0.5 then return false end

	for _, corner in pairs({
		cframe * CFrame.new(logicalBoundsX / 2 - COLLISION_SHRINK, 0, logicalBoundsZ / 2 - COLLISION_SHRINK),
		cframe * CFrame.new(-logicalBoundsX / 2 + COLLISION_SHRINK, 0, logicalBoundsZ / 2 - COLLISION_SHRINK),
		cframe * CFrame.new(logicalBoundsX / 2 - COLLISION_SHRINK, 0, -logicalBoundsZ / 2 + COLLISION_SHRINK),
		cframe * CFrame.new(-logicalBoundsX / 2 + COLLISION_SHRINK, 0, -logicalBoundsZ / 2 + COLLISION_SHRINK)
		}) do if ownedPlots[GetPlotIdFromPos(corner.Position)] ~= true then return false end end

	if not HasSupport(cframe, size, currentItemName) then return false end

	local overlapParams = OverlapParams.new()
	local filter = {player.Character}; for _, g in pairs(ghostsCache) do if g.Model then table.insert(filter, g.Model) end end
	if gridFolder then table.insert(filter, gridFolder) end; if buildPlane then table.insert(filter, buildPlane) end
	if PlotGridFolder then table.insert(filter, PlotGridFolder) end 
	overlapParams.FilterDescendantsInstances = filter; overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local checkSizeX, checkSizeZ = size.X, size.Z
	if IsWallType(currentItemName) then
		checkSizeX = (size.X > GRID) and (GRID - 0.2) or (size.X - 0.1); checkSizeZ = (size.Z > GRID) and (GRID - 0.2) or (size.Z - 0.1)
	else
		checkSizeX = checkSizeX - COLLISION_SHRINK; checkSizeZ = checkSizeZ - COLLISION_SHRINK
	end

	for _, part in pairs(Workspace:GetPartBoundsInBox(cframe, Vector3.new(checkSizeX, math.max(0.1, size.Y - 0.1), checkSizeZ), overlapParams)) do
		if part ~= GROUND and part.Name ~= "Baseplate" and part.Name ~= "Terrain" and part ~= buildPlane then
			if part.Name == "TargetPart" or part.Name == "Hitbox" then continue end
			local hitModelName = part:FindFirstAncestorOfClass("Model") and part:FindFirstAncestorOfClass("Model").Name or ""

			if IS_FLOOR[currentItemName] then if IS_FLOOR[hitModelName] then return false end continue end
			if IS_FLOOR[hitModelName] or (currentItemName == "Chair" and hitModelName == "Chair") then continue end
			if IsSurfaceItem(currentItemName) then if hitModelName == "Desc" or hitModelName == "Table" or hitModelName == "CTable" then continue end end
			return false
		end
	end
	return true
end

local function CreateGhost()
	local template = Furniture:FindFirstChild(currentItemName)
	if not template then return nil end
	local g = template:Clone()

	for _, part in pairs(g:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0.5; part.CanCollide = false; part.CastShadow = false
			if part.Name == "Hitbox" or part.Name == "TargetPart" then part.Transparency = 1 end
		elseif part:IsA("SurfaceGui") then part.AlwaysOnTop = true 
		elseif part:IsA("ImageLabel") or part:IsA("ImageButton") then
			part.ImageTransparency = 0.5; if part.BackgroundTransparency < 1 then part.BackgroundTransparency = 0.5 end
		elseif part:IsA("Frame") then
			if part.BackgroundTransparency < 1 then part.BackgroundTransparency = 0.5 end
		elseif part:IsA("Decal") or part:IsA("Texture") then part.Transparency = 0.5 end
	end
	return g
end

local function UpdateLineVisuals(targetCF, size)
	local template = Furniture:FindFirstChild(currentItemName)
	if not template then return end
	local itemPrice = ITEM_PRICES[currentItemName] or 0
	local cashObj = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
	local currentCash = cashObj and cashObj.Value or 0

	if #ghostsCache == 0 then
		local g = CreateGhost(); if g then g.Parent = Workspace end
		table.insert(ghostsCache, {Model = g, CFrame = nil, IsValid = false}) 
	end

	local ghostData = ghostsCache[1]
	if ghostData.Model then
		ghostData.Model:PivotTo(targetCF); ghostData.CFrame = targetCF
		local isPhysicallyValid = CheckValidity(targetCF, size, ghostData.Model)
		local hasEnoughMoney = currentCash >= itemPrice

		ghostData.IsValid = isPhysicallyValid and hasEnoughMoney
		local color = ghostData.IsValid and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)

		for _, p in pairs(ghostData.Model:GetDescendants()) do 
			if p:IsA("BasePart") and p.Name ~= "Hitbox" then p.Color = color 
			elseif p:IsA("ImageLabel") or p:IsA("ImageButton") then p.ImageColor3 = color; if p.BackgroundTransparency < 1 then p.BackgroundColor3 = color end
			elseif p:IsA("Frame") then if p.BackgroundTransparency < 1 then p.BackgroundColor3 = color end
			elseif p:IsA("Decal") or p:IsA("Texture") then p.Color3 = color end 
		end
	end
end

local function SmartRaycast(x, y)
	local ignoreList = {player.Character}; for _, g in pairs(ghostsCache) do if g.Model then table.insert(ignoreList, g.Model) end end
	if gridFolder then table.insert(ignoreList, gridFolder) end; if PlotGridFolder then table.insert(ignoreList, PlotGridFolder) end
	local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude; local mouseRay = camera:ScreenPointToRay(x, y)
	local currentTry = 0
	while currentTry < 5 do
		currentTry += 1; rayParams.FilterDescendantsInstances = ignoreList; local result = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, rayParams)
		if not result then return nil end
		if result.Instance == buildPlane or result.Instance == GROUND or result.Instance.Name == "Baseplate" or result.Instance.Name == "Terrain" or IsSurfaceItem(currentItemName) then return result end
		table.insert(ignoreList, result.Instance:FindFirstAncestorOfClass("Model") or result.Instance)
	end; return nil
end

local function ClearGhosts() for _, data in pairs(ghostsCache) do if data.Model then data.Model:Destroy() end end; ghostsCache = {} end

local function ConfirmPlacement() 
	if isPlacing then 
		local itemPrice = ITEM_PRICES[currentItemName] or 0
		local leaderstats = player:FindFirstChild("leaderstats")
		local cash = leaderstats and leaderstats:FindFirstChild("Cash")
		local currentCash = cash and cash.Value or 0

		if #ghostsCache > 0 and ghostsCache[1].IsValid and ghostsCache[1].CFrame then
			if currentCash >= itemPrice then
				PlaceItemEvent:FireServer(currentItemName, ghostsCache[1].CFrame, IS_FLOOR[currentItemName] and 0 or currentRotation) 

				if isTutorialMode and tutorialStep == 3 then
					isTutorialMode = false
					ClearTutorialPointer()
					PlayConfettiDopamine()
					UnlockBuildMenu()
					player:SetAttribute("TutorialDone", true)
					pcall(function()
						local ev = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("CompleteTutorial")
						if ev then ev:FireServer() end
					end)
				end
			end
		else
			if premiumUI then
				local btn = premiumUI:FindFirstChild("Container") and premiumUI.Container:FindFirstChild("BtnConfirm")
				if btn then
					local originalPos = btn.Position
					TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), {Position = originalPos + UDim2.new(0, 5, 0, 0)}):Play()
				end
			end
		end
	end 
end

local function SetupPremiumUI()
	if premiumUI then return end
	local template = ReplicatedStorage:FindFirstChild("PremiumSpaceBlackUI")
	if template then 
		premiumUI = template:Clone(); premiumUI.Parent = player.PlayerGui; premiumUI.Active = true; premiumUI.AlwaysOnTop = true; premiumUI.ResetOnSpawn = false; premiumUI.LightInfluence = 0; premiumUI.Enabled = false
		local container = premiumUI:WaitForChild("Container"); local btnMove = container:WaitForChild("BtnMove"); local btnRotate = container:WaitForChild("BtnRotate"); local btnConfirm = container:WaitForChild("BtnConfirm")
		if container:IsA("GuiObject") then container.Active = false; if container.Size.X.Scale == 0 and container.Size.X.Offset == 0 then container.Size = UDim2.fromScale(1, 1) end end
		for _, btn in pairs({btnMove, btnRotate, btnConfirm}) do if not btn:FindFirstChild("UIScale") then Instance.new("UIScale", btn) end end

		btnRotate.Activated:Connect(function() PlayClickSound(); PlayButtonAnimation(btnRotate); if not IS_FLOOR[currentItemName] then currentRotation = (currentRotation + ROTATION_SNAP) % 360 end end)
		btnConfirm.Activated:Connect(function() PlayClickSound(); PlayButtonAnimation(btnConfirm); ConfirmPlacement() end)

		btnMove.InputBegan:Connect(function(input) 
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
				PlayClickSound(); PlayButtonAnimation(btnMove); activeMoveInput = input; isMovingMode = true
			end 
		end)
	end
end

local function StopAction()
	isPlacing = false; isDeleting = false; isMovingMode = false; activeMoveInput = nil; lastHitPos = nil; ClearGhosts()
	if premiumUI then premiumUI.Enabled = false; premiumUI.Adornee = nil end
	selectionBox.Adornee = nil

	if isTutorialMode and tutorialStep == 3 then
		ClearTutorialPointer()
		tutorialStep = 2
		task.spawn(function()
			task.wait(0.1) 
			local gui = player.PlayerGui:FindFirstChild("BuildGui")
			local scroller = gui and gui:FindFirstChild("BottomDock") and gui.BottomDock:FindFirstChild("Content") and gui.BottomDock.Content:FindFirstChild("ItemsScroller")
			local stoveBtn = scroller and scroller:FindFirstChild("ButtonStove")
			if stoveBtn then CreateTutorialPointer(stoveBtn, "Down_Stove") end
		end)
	end

	if selectedPlotToBuy then
		local oldSel = selectedPlotToBuy; selectedPlotToBuy = nil; ClosePlotUI(); UpdatePlotVisualState(oldSel)
	end
	if isBuildModeOpen then for id in pairs(plotVisuals) do UpdatePlotVisualState(id) end end
end

local function StartPlacing(name)
	local oldHover = hoveredPlotId; local oldSel = selectedPlotToBuy
	hoveredPlotId = nil; selectedPlotToBuy = nil; ClosePlotUI()
	if oldHover then UpdatePlotVisualState(oldHover) end
	if oldSel then UpdatePlotVisualState(oldSel) end

	StopAction(); isPlacing = true; currentItemName = name; currentRotation = 0; UpdateGridState(true)

	if not premiumUI then SetupPremiumUI() end; premiumUI.Enabled = true

	if isTutorialMode and tutorialStep == 2 and name == "Stove" then
		tutorialStep = 3
		ClearTutorialPointer()
		task.spawn(function()
			task.wait(0.2) 
			if premiumUI and premiumUI.Enabled then
				local btnConfirm = premiumUI:FindFirstChild("Container") and premiumUI.Container:FindFirstChild("BtnConfirm")
				if btnConfirm then
					CreateTutorialPointer(btnConfirm, "Down")
				end
			end
		end)
	end

	local result = SmartRaycast(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	if result then 
		lastHitPos = result.Position; local template = Furniture:FindFirstChild(currentItemName)
		if template then local hitbox = GetHitbox(template); local currentCF = CalculateGridCFrame(lastHitPos, hitbox.Size); UpdateLineVisuals(currentCF, hitbox.Size) end 
	end
	for id in pairs(plotVisuals) do UpdatePlotVisualState(id) end
end

local function StartDeleting() 
	local oldHover = hoveredPlotId; local oldSel = selectedPlotToBuy
	hoveredPlotId = nil; selectedPlotToBuy = nil; ClosePlotUI()
	if oldHover then UpdatePlotVisualState(oldHover) end
	if oldSel then UpdatePlotVisualState(oldSel) end

	local targetState = not isDeleting
	StopAction(); isDeleting = targetState
	for id in pairs(plotVisuals) do UpdatePlotVisualState(id) end
end

local function SetFloor(newFloor)
	local maxFloor = player:GetAttribute("MaxFloor") or 1
	currentFloor = math.clamp(newFloor, 1, maxFloor + 1)

	local gui = player.PlayerGui:FindFirstChild("BuildGui")
	if gui then 
		local displayNum = gui.BottomDock.Controls.FloorDisplay:FindFirstChild("FloorNumber")
		if displayNum then displayNum.Text = tostring(currentFloor) end 
	end
	if isBuildModeOpen then UpdateGridState(true) end
end

player:GetAttributeChangedSignal("MaxFloor"):Connect(function() if isBuildModeOpen then SetFloor(currentFloor) end end)

local function FixViewportSurfaceGuis(vpf)
	if not vpf then return end
	for _, sg in pairs(vpf:GetDescendants()) do
		if sg:IsA("SurfaceGui") then
			local part = sg.Parent
			if part and part:IsA("BasePart") then
				for _, ui in pairs(sg:GetChildren()) do
					if ui:IsA("ImageLabel") or ui:IsA("Frame") then
						local pSize = part.Size; local pCF = part.CFrame
						local face = sg.Face; local fw, fh; local right, up, normal

						if face == Enum.NormalId.Front then fw, fh = pSize.X, pSize.Y; right, up, normal = -pCF.RightVector, pCF.UpVector, -pCF.LookVector
						elseif face == Enum.NormalId.Back then fw, fh = pSize.X, pSize.Y; right, up, normal = pCF.RightVector, pCF.UpVector, pCF.LookVector
						elseif face == Enum.NormalId.Right then fw, fh = pSize.Z, pSize.Y; right, up, normal = pCF.LookVector, pCF.UpVector, pCF.RightVector
						elseif face == Enum.NormalId.Left then fw, fh = pSize.Z, pSize.Y; right, up, normal = -pCF.LookVector, pCF.UpVector, -pCF.RightVector
						elseif face == Enum.NormalId.Top then fw, fh = pSize.X, pSize.Z; right, up, normal = pCF.RightVector, pCF.LookVector, pCF.UpVector
						elseif face == Enum.NormalId.Bottom then fw, fh = pSize.X, pSize.Z; right, up, normal = pCF.RightVector, -pCF.LookVector, -pCF.UpVector end

						local wScale = ui.Size.X.Scale; local hScale = ui.Size.Y.Scale; local xPos = ui.Position.X.Scale; local yPos = ui.Position.Y.Scale
						if wScale == 0 and ui.Size.X.Offset > 0 then wScale = 1 end; if hScale == 0 and ui.Size.Y.Offset > 0 then hScale = 1 end

						local stripWidth = fw * wScale; local stripHeight = fh * hScale
						local centerXScale = xPos + (wScale / 2); local centerYScale = yPos + (hScale / 2)
						local offsetX = (centerXScale - 0.5) * fw; local offsetY = -(centerYScale - 0.5) * fh

						local fakePart = Instance.new("Part"); fakePart.Name = "FakeUI_" .. ui.Name; fakePart.Size = Vector3.new(stripWidth, stripHeight, 0.005); fakePart.Material = Enum.Material.SmoothPlastic; fakePart.CanCollide = false; fakePart.CanQuery = false; fakePart.Anchored = true; fakePart.CastShadow = false

						if ui:IsA("ImageLabel") and ui.Image ~= "" then
							fakePart.Color = ui.BackgroundColor3; fakePart.Transparency = ui.BackgroundTransparency
							local decal = Instance.new("Decal"); decal.Texture = ui.Image; decal.Face = Enum.NormalId.Front; decal.Color3 = ui.ImageColor3; decal.Transparency = ui.ImageTransparency; decal.Parent = fakePart
						else
							fakePart.Color = ui.BackgroundColor3; fakePart.Transparency = ui.BackgroundTransparency
						end

						local faceOffsetDist = (face == Enum.NormalId.Front or face == Enum.NormalId.Back) and (pSize.Z/2) or (face == Enum.NormalId.Left or face == Enum.NormalId.Right) and (pSize.X/2) or (pSize.Y/2)
						local faceCenter = pCF.Position + (normal * (faceOffsetDist + 0.005))
						local finalPos = faceCenter + (right * offsetX) + (up * offsetY)

						fakePart.CFrame = CFrame.fromMatrix(finalPos, -right, up, -normal); fakePart.Parent = part.Parent or vpf
					end
				end
				sg.Enabled = false
			end
		end
	end
end


local function SetupGUI()
	local gui = player.PlayerGui:WaitForChild("BuildGui", 10); if not gui then return end
	local dock = gui:WaitForChild("BottomDock"); local controls = dock:WaitForChild("Controls"); local scroller = dock:WaitForChild("Content"):WaitForChild("ItemsScroller")
	local leaderstats = player:WaitForChild("leaderstats", 10); local cash = leaderstats and leaderstats:WaitForChild("Cash", 10)

	scroller.AutomaticCanvasSize = Enum.AutomaticSize.None 
	scroller.ScrollBarThickness = 5; scroller.ScrollingDirection = Enum.ScrollingDirection.X; scroller.VerticalScrollBarInset = Enum.ScrollBarInset.Always; scroller.BorderSizePixel = 0; scroller.BackgroundTransparency = 1

	for _, child in pairs(scroller:GetChildren()) do if child:IsA("UIListLayout") or child:IsA("UIGridLayout") or child:IsA("UIPadding") then child:Destroy() end end

	local listLayout = Instance.new("UIListLayout"); listLayout.Name = "PerfectListLayout"; listLayout.FillDirection = Enum.FillDirection.Horizontal; listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left; listLayout.VerticalAlignment = Enum.VerticalAlignment.Center; listLayout.SortOrder = Enum.SortOrder.LayoutOrder; listLayout.Padding = UDim.new(0, 16); listLayout.Parent = scroller
	local padding = Instance.new("UIPadding"); padding.Name = "PerfectPadding"; padding.PaddingLeft = UDim.new(0, 20); padding.PaddingRight = UDim.new(0, 20); padding.PaddingTop = UDim.new(0, 6); padding.PaddingBottom = UDim.new(0, 6); padding.Parent = scroller

	local function UpdateCanvasSize() scroller.CanvasSize = UDim2.new(0, listLayout.AbsoluteContentSize.X + padding.PaddingLeft.Offset + padding.PaddingRight.Offset, 0, 0) end
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCanvasSize)

	local function updatePrices()
		if not cash then return end
		for _, child in pairs(scroller:GetChildren()) do
			if child:IsA("GuiButton") and child.Name:sub(1, 6) == "Button" then
				local itemName = child.Name:sub(7)
				if itemName == "Cloud" or itemName == "DeprecatedCloud" then child.Visible = false continue end

				local price = ITEM_PRICES[itemName] or 0; local priceTag = child:FindFirstChild("PriceTag")
				if priceTag then
					local priceLabel = priceTag:FindFirstChild("Price")
					if priceLabel and priceLabel:IsA("TextLabel") then
						priceLabel.TextColor3 = Color3.fromRGB(255, 255, 255) 
						local targetColor = (cash.Value >= price) and Color3.fromRGB(45, 180, 75) or Color3.fromRGB(220, 50, 50)
						TweenService:Create(priceTag, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = targetColor}):Play()
					end
				end
			end
		end
	end

	for _, child in pairs(scroller:GetChildren()) do
		if child:IsA("GuiButton") and child.Name:sub(1, 6) == "Button" then
			local itemName = child.Name:sub(7)
			if itemName == "Cloud" or itemName == "DeprecatedCloud" then child:Destroy() continue end

			if isTutorialMode and itemName ~= "Stove" then
				child.Visible = false
			else
				child.Visible = true
			end

			local vpf = child:FindFirstChildWhichIsA("ViewportFrame", true); if vpf then FixViewportSurfaceGuis(vpf) end

			local price = ITEM_PRICES[itemName] or 0
			child.LayoutOrder = ITEM_SORT_ORDER[itemName] or 999; child.Size = UDim2.new(0, 110, 1, 0) 

			local aspect = child:FindFirstChildWhichIsA("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
			aspect.Name = "PerfectSquare"; aspect.AspectRatio = 1; aspect.DominantAxis = Enum.DominantAxis.Height; aspect.AspectType = Enum.AspectType.FitWithinMaxSize; aspect.Parent = child

			local corner = child:FindFirstChildWhichIsA("UICorner") or Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 14); corner.Parent = child 

			local borderStroke = child:FindFirstChildWhichIsA("UIStroke") or Instance.new("UIStroke")
			borderStroke.Color = Color3.fromRGB(255, 255, 255); borderStroke.Thickness = 1.5; borderStroke.Transparency = 0.85; borderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; borderStroke.Parent = child

			local priceTag = child:FindFirstChild("PriceTag")
			if priceTag then
				local tagCorner = priceTag:FindFirstChildWhichIsA("UICorner") or Instance.new("UICorner")
				tagCorner.CornerRadius = UDim.new(0, 6); tagCorner.Parent = priceTag

				local tagScale = priceTag:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale")
				tagScale.Scale = 1.15
				tagScale.Parent = priceTag

				local tagGradient = priceTag:FindFirstChildWhichIsA("UIGradient") or Instance.new("UIGradient")
				tagGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), 
					ColorSequenceKeypoint.new(1, Color3.new(0.65, 0.65, 0.65)) 
				})
				tagGradient.Rotation = 90
				tagGradient.Parent = priceTag

				local tagStroke = priceTag:FindFirstChildWhichIsA("UIStroke") or Instance.new("UIStroke")
				tagStroke.Color = Color3.fromRGB(0, 0, 0); tagStroke.Thickness = 1.2; tagStroke.Transparency = 0.5; tagStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; tagStroke.Parent = priceTag

				local priceLabel = priceTag:FindFirstChild("Price")
				if priceLabel and priceLabel:IsA("TextLabel") then
					local formattedPrice = tostring(price):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
					priceLabel.Text = "$" .. formattedPrice
					priceLabel.TextScaled = true 
					priceLabel.Font = Enum.Font.GothamBlack
					priceLabel.TextWrapped = false 

					local textPadding = priceLabel:FindFirstChildWhichIsA("UIPadding") or Instance.new("UIPadding")
					textPadding.PaddingLeft = UDim.new(0.04, 0); textPadding.PaddingRight = UDim.new(0.04, 0); textPadding.PaddingTop = UDim.new(0, 0); textPadding.PaddingBottom = UDim.new(0, 0); textPadding.Parent = priceLabel

					local textConstraint = priceLabel:FindFirstChildWhichIsA("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
					textConstraint.MaxTextSize = 45; textConstraint.MinTextSize = 4; textConstraint.Parent = priceLabel

					local textStroke = priceLabel:FindFirstChildWhichIsA("UIStroke") or Instance.new("UIStroke")
					textStroke.Color = Color3.fromRGB(0, 0, 0); textStroke.Thickness = 1; textStroke.Transparency = 0.2; textStroke.Parent = priceLabel

					priceLabel.BackgroundTransparency = 1
				end
			end

			local uiScale = child:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale"); uiScale.Parent = child

			child.MouseEnter:Connect(function() 
				TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.06}):Play()
				TweenService:Create(borderStroke, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Transparency = 0.2, Thickness = 2.5}):Play()
			end)
			child.MouseLeave:Connect(function() 
				TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1.0}):Play()
				TweenService:Create(borderStroke, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Transparency = 0.85, Thickness = 1.5}):Play()
			end)
			child.MouseButton1Click:Connect(function() 
				PlayClickSound(); TweenService:Create(uiScale, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.92}):Play()
				task.delay(0.08, function() if uiScale.Parent then TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.06}):Play() end end)
				if isPlacing and currentItemName == itemName then StopAction() else StartPlacing(itemName) end 
			end)
		end
	end

	if cash then cash.Changed:Connect(updatePrices); updatePrices() end
	for _, btnName in ipairs({"ButtonUp", "ButtonDown", "ButtonRemove"}) do
		local btn = controls:FindFirstChild(btnName)
		if btn then
			local btnScale = btn:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", btn)
			btn.MouseEnter:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.1}):Play() end)
			btn.MouseLeave:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1}):Play() end)
		end
	end

	local btnUp = controls:FindFirstChild("ButtonUp"); if btnUp then btnUp.MouseButton1Click:Connect(function() PlayClickSound(); PlayButtonAnimation(btnUp); SetFloor(currentFloor + 1) end) end
	local btnDown = controls:FindFirstChild("ButtonDown"); if btnDown then btnDown.MouseButton1Click:Connect(function() PlayClickSound(); PlayButtonAnimation(btnDown); SetFloor(currentFloor - 1) end) end
	local btnRemove = controls:FindFirstChild("ButtonRemove"); if btnRemove then btnRemove.MouseButton1Click:Connect(function() PlayClickSound(); PlayButtonAnimation(btnRemove); StartDeleting() end) end

	SetFloor(1); task.delay(0.1, UpdateCanvasSize) 
end

if player.PlayerGui:FindFirstChild("BuildGui") then SetupGUI() else player.PlayerGui.ChildAdded:Connect(function(child) if child.Name == "BuildGui" then SetupGUI() end end) end

local function RaycastThroughTransparent(origin, direction, distance, ignoreList)
	local params = RaycastParams.new(); params.FilterDescendantsInstances = ignoreList; params.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(origin, direction.Unit * distance, params)
	if result and result.Instance then
		local p = result.Instance
		if p.Name == "Hitbox" or p.Name == "TargetPart" or p.Transparency == 1 then
			table.insert(ignoreList, p)
			return RaycastThroughTransparent(origin, direction, distance, ignoreList)
		end
		return result
	end
	return nil
end

local function GetHoveredPlot(x, y)
	local ray = camera:ScreenPointToRay(x, y); local rayParams = RaycastParams.new(); rayParams.FilterDescendantsInstances = {PlotGridFolder}; rayParams.FilterType = Enum.RaycastFilterType.Include
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)

	if result and result.Instance then
		local ignoreList = {player.Character, gridFolder, buildPlane, PlotGridFolder, GROUND}
		pcall(function()
			if Workspace:FindFirstChild("Baseplate") then table.insert(ignoreList, Workspace.Baseplate) end
			if Workspace:FindFirstChild("Terrain") then table.insert(ignoreList, Workspace.Terrain) end
			local terrainClass = Workspace:FindFirstChildOfClass("Terrain"); if terrainClass then table.insert(ignoreList, terrainClass) end
		end)
		for _, g in pairs(ghostsCache) do if g.Model then table.insert(ignoreList, g.Model) end end

		local rayDistance = math.max(0, result.Distance - 0.5)
		local blockResult = RaycastThroughTransparent(ray.Origin, ray.Direction, rayDistance, ignoreList)
		if blockResult then return nil end
		return result.Instance.Name
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local maxFloor = player:GetAttribute("MaxFloor") or 1
		local detectedFloor = math.clamp(math.floor(((player.Character.HumanoidRootPart.Position.Y - (GROUND.Position.Y + GROUND.Size.Y / 2)) + 1) / FLOOR_HEIGHT) + 1, 1, maxFloor + 1)
		if detectedFloor ~= lastPhysicalFloor then lastPhysicalFloor = detectedFloor; if not isMovingMode then SetFloor(detectedFloor) end end
	end

	local bg = player.PlayerGui:FindFirstChild("BuildGui")
	local currentBuildModeState = false

	if bg and bg:IsA("ScreenGui") and bg.Enabled then
		local dock = bg:FindFirstChild("BottomDock")
		if dock then if dock.Visible and dock.AbsolutePosition.Y < camera.ViewportSize.Y then currentBuildModeState = true end else currentBuildModeState = true end
	end

	if currentBuildModeState ~= isBuildModeOpen then 
		isBuildModeOpen = currentBuildModeState; UpdateGridState(isBuildModeOpen) 

		if isBuildModeOpen and isTutorialMode and tutorialStep == 1 then
			tutorialStep = 2
			ClearTutorialPointer()
			task.spawn(function()
				task.wait(0.3) 
				local scroller = bg and bg:FindFirstChild("BottomDock") and bg.BottomDock:FindFirstChild("Content") and bg.BottomDock.Content:FindFirstChild("ItemsScroller")
				if scroller then
					local stoveBtn = scroller:FindFirstChild("ButtonStove")
					if stoveBtn then CreateTutorialPointer(stoveBtn, "Down_Stove") end
				end
			end)
		end

		if not isBuildModeOpen then
			local oldHover = hoveredPlotId; local oldSel = selectedPlotToBuy; hoveredPlotId = nil; selectedPlotToBuy = nil; ClosePlotUI(); StopAction()
			if oldHover then UpdatePlotVisualState(oldHover) end
			if oldSel then UpdatePlotVisualState(oldSel) end
		end
		for id in pairs(plotVisuals) do UpdatePlotVisualState(id) end
	end

	if isPlacing ~= false or isDeleting ~= false then
		if hoveredPlotId or selectedPlotToBuy then 
			local oldHover = hoveredPlotId; local oldSel = selectedPlotToBuy; 
			hoveredPlotId = nil; selectedPlotToBuy = nil; 
			if oldHover then UpdatePlotVisualState(oldHover) end
			if oldSel and oldSel ~= oldHover then UpdatePlotVisualState(oldSel) end
			ClosePlotUI() 
		end
	end

	if not isBuildModeOpen then return end

	if not isPlacing and not isDeleting then
		local hitId = GetHoveredPlot(mouse.X, mouse.Y)
		if hitId and ownedPlots[hitId] ~= true then
			if selectedPlotToBuy and selectedPlotToBuy ~= hitId then
				local oldSel = selectedPlotToBuy; selectedPlotToBuy = nil; UpdatePlotVisualState(oldSel); ClosePlotUI()
			end
			if hoveredPlotId ~= hitId then
				local oldHover = hoveredPlotId; hoveredPlotId = hitId; if oldHover then UpdatePlotVisualState(oldHover) end; UpdatePlotVisualState(hoveredPlotId)
			end
		else
			if selectedPlotToBuy then local oldSel = selectedPlotToBuy; selectedPlotToBuy = nil; UpdatePlotVisualState(oldSel); ClosePlotUI() end
			if hoveredPlotId then local oldHover = hoveredPlotId; hoveredPlotId = nil; UpdatePlotVisualState(oldHover) end
		end
	end

	if isPlacing and currentItemName then
		if activeMoveInput then
			if activeMoveInput.UserInputState == Enum.UserInputState.End or activeMoveInput.UserInputState == Enum.UserInputState.Cancel then 
				activeMoveInput = nil; isMovingMode = false
			else
				local targetX, targetY = activeMoveInput.Position.X, activeMoveInput.Position.Y
				if activeMoveInput.UserInputType == Enum.UserInputType.MouseButton1 then local ml = UserInputService:GetMouseLocation(); targetX, targetY = ml.X, ml.Y end
				local result = SmartRaycast(targetX, targetY); if result then lastHitPos = result.Position end
			end
		end

		if lastHitPos then
			local template = Furniture:FindFirstChild(currentItemName)
			if template then
				local hitbox = GetHitbox(template); local currentCF = CalculateGridCFrame(lastHitPos, hitbox.Size); UpdateLineVisuals(currentCF, hitbox.Size)
				if premiumUI and #ghostsCache > 0 and ghostsCache[1].Model then
					local hb = GetHitbox(ghostsCache[1].Model); if premiumUI.Adornee ~= hb then premiumUI.Adornee = hb end
					premiumUI.StudsOffsetWorldSpace = Vector3.new(0, hb.Size.Y / 2 + 1.5, 0); premiumUI.Enabled = true
				end
			end
		end

	elseif isDeleting then
		local params = RaycastParams.new(); params.FilterDescendantsInstances = {player.Character, gridFolder, buildPlane, PlotGridFolder}; params.FilterType = Enum.RaycastFilterType.Exclude
		local result = Workspace:Raycast(camera:ScreenPointToRay(mouse.X, mouse.Y).Origin, camera:ScreenPointToRay(mouse.X, mouse.Y).Direction * 1000, params)
		local model = result and result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
		if model and model.Parent and model.Parent.Name == "PlacedItems" and model.Parent.Parent == PLOT and model.Name ~= "PlacedItems" then selectionBox.Adornee = model else selectionBox.Adornee = nil end
	else selectionBox.Adornee = nil end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if isPlacing then
		if input.KeyCode == Enum.KeyCode.R then if not IS_FLOOR[currentItemName] then currentRotation = (currentRotation + ROTATION_SNAP) % 360 end
		elseif input.KeyCode == Enum.KeyCode.Q then StopAction() end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if isBuildModeOpen and not isPlacing and not isDeleting then
			local hitId = GetHoveredPlot(input.Position.X, input.Position.Y)
			if hitId and ownedPlots[hitId] ~= true then
				if selectedPlotToBuy ~= hitId then
					local oldSel = selectedPlotToBuy; selectedPlotToBuy = hitId; PlayClickSound()
					if oldSel then UpdatePlotVisualState(oldSel) end
					local data = plotVisuals[hitId]
					if data and data.Visual then TweenService:Create(data.Visual, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Size = FULL_SIZE - Vector3.new(2, 0, 2)}):Play() end
					UpdatePlotVisualState(hitId); ShowPlotUI(hitId) 
					local oldPos = plotUI.StudsOffset; plotUI.StudsOffset = oldPos - Vector3.new(0, 1, 0)
					TweenService:Create(plotUI, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {StudsOffset = oldPos + Vector3.new(0, 0.5, 0)}):Play()
					return
				end

				local plotIdToBuy = selectedPlotToBuy; selectedPlotToBuy = nil; ClosePlotUI()
				local col = string.sub(plotIdToBuy, 1, 1); local row = tonumber(string.sub(plotIdToBuy, 2, 2)); local data = plotVisuals[plotIdToBuy]

				if data and data.Visual then
					TweenService:Create(data.Visual, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Size = FULL_SIZE - Vector3.new(2, 0, 2)}):Play()
					task.delay(0.1, function() if data.Visual and data.Visual.Parent and ownedPlots[plotIdToBuy] ~= true then TweenService:Create(data.Visual, TweenInfo.new(0.3, Enum.EasingStyle.Back), {Size = FULL_SIZE}):Play() end end)
				end

				if IsGamepassPlot(col, row) then 
					PlayClickSound(); MarketplaceService:PromptGamePassPurchase(player, GAMEPASS_ID)
				else
					if not BuyPlotFunc:InvokeServer(plotIdToBuy) then
						PlayErrorSound(); selectedPlotToBuy = plotIdToBuy; ShowPlotUI(plotIdToBuy)
						local oldColor = uiStroke.Color; local oldGrad = textGradient.Color
						TweenService:Create(uiStroke, TweenInfo.new(0.1), {Color = Color3.fromRGB(255, 50, 50)}):Play(); textGradient.Color = ColorSequence.new(Color3.fromRGB(255, 50, 50))
						local oldPos = plotUI.StudsOffset
						TweenService:Create(plotUI, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), {StudsOffset = oldPos + Vector3.new(0.4, 0, 0)}):Play()
						task.delay(0.3, function() if uiStroke then TweenService:Create(uiStroke, TweenInfo.new(0.3), {Color = oldColor}):Play() end; textGradient.Color = oldGrad; plotUI.StudsOffset = oldPos end)
					end
				end
			else
				if selectedPlotToBuy then local oldSel = selectedPlotToBuy; selectedPlotToBuy = nil; ClosePlotUI(); UpdatePlotVisualState(oldSel) end
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input == activeMoveInput then activeMoveInput = nil; isMovingMode = false end
	if isDeleting and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		if selectionBox.Adornee then RemoveItemEvent:FireServer(selectionBox.Adornee); selectionBox.Adornee = nil end
	end
end)

local EventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
if EventsFolder then
	local PromptWhaleSafe = EventsFolder:WaitForChild("PromptWhaleSafe", 5)
	if PromptWhaleSafe then
		PromptWhaleSafe.OnClientEvent:Connect(function()
			local sg = player.PlayerGui:FindFirstChild("WhaleSafeUI")
			if not sg then
				sg = Instance.new("ScreenGui", player.PlayerGui); sg.Name = "WhaleSafeUI"
				local bg = Instance.new("Frame", sg); bg.Size = UDim2.fromScale(1,1); bg.BackgroundColor3 = Color3.fromRGB(0,0,0); bg.BackgroundTransparency = 0.5; bg.Active = true

				local main = Instance.new("Frame", bg); main.Size = UDim2.fromOffset(420, 220); main.AnchorPoint = Vector2.new(0.5, 0.5); main.Position = UDim2.fromScale(0.5, 0.5); main.BackgroundColor3 = Color3.fromRGB(20, 20, 25); Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
				local stroke = Instance.new("UIStroke", main); stroke.Color = Color3.fromRGB(255, 215, 0); stroke.Thickness = 3

				local title = Instance.new("TextLabel", main); title.Size = UDim2.new(1, -40, 0, 90); title.Position = UDim2.new(0, 20, 0, 15); title.BackgroundTransparency = 1; title.Text = "Need more cash to upgrade your Chef?\nOpen the Safe for an instant $100,000!"; title.TextColor3 = Color3.new(1,1,1); title.Font = Enum.Font.GothamBold; title.TextScaled = true; title.TextWrapped = true; local tCons = Instance.new("UITextSizeConstraint", title); tCons.MaxTextSize = 20; tCons.MinTextSize = 10
				local buyBtn = Instance.new("TextButton", main); buyBtn.Size = UDim2.fromOffset(220, 50); buyBtn.Position = UDim2.new(0.5, -110, 1, -90); buyBtn.BackgroundColor3 = Color3.fromRGB(48, 209, 88); buyBtn.Text = "Buy for 1,499 R$"; buyBtn.TextColor3 = Color3.new(1,1,1); buyBtn.Font = Enum.Font.GothamBlack; buyBtn.TextScaled = true; Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0,10); local bCons = Instance.new("UITextSizeConstraint", buyBtn); bCons.MaxTextSize = 18; bCons.MinTextSize = 10;
				local closeBtn = Instance.new("TextButton", main); closeBtn.Size = UDim2.fromOffset(100, 30); closeBtn.Position = UDim2.new(0.5, -50, 1, -25); closeBtn.BackgroundTransparency = 1; closeBtn.Text = "Close"; closeBtn.TextColor3 = Color3.fromRGB(150, 150, 150); closeBtn.Font = Enum.Font.GothamMedium; closeBtn.TextScaled = true; local cCons = Instance.new("UITextSizeConstraint", closeBtn); cCons.MaxTextSize = 14; cCons.MinTextSize = 10

				buyBtn.MouseButton1Click:Connect(function() PlayClickSound(); MarketplaceService:PromptProductPurchase(player, 3550880952); sg.Enabled = false end)
				closeBtn.MouseButton1Click:Connect(function() PlayClickSound(); sg.Enabled = false end)
			end
			sg.Enabled = true
		end)
	end
end
