--[[
	Organization Plugin
	
	Lets you pin folders to a list, then reparent your current
	selection into whichever folder you've highlighted.
--]]

const PLUGIN_NAME   = "Pin n Parents"
const PLUGIN_VERSION_NUMBER = 131
const PLUGIN_VERSION_STRING = "v1.3.1"
const PLUGIN_ICON = 114658320494964
const PLUGIN_KEYBIND_ICON = 78200661333783
const INTERNAL_NAME = "PaP.one7and7.roblox"

const toolbar: PluginToolbar = plugin:CreateToolbar(PLUGIN_NAME)
const toggleButton: PluginToolbarButton = toolbar:CreateButton(
	`{PLUGIN_NAME}_Toggle`,
	"Open / Close P&P",
	`rbxassetid://{PLUGIN_ICON}`,
	"P&P"
)
const keybindButton: PluginToolbarButton = toolbar:CreateButton(
	`{PLUGIN_NAME}_Reparent_Keybind`,
	"Reparent your selection",
	`rbxassetid://{PLUGIN_KEYBIND_ICON}`,
	"Reparent"
)

-- ── Consts ────────────────────────────────────────────────────────────────────

const NL = "\n"
const F_M = `<font weight="medium">`
const F_B = `<font weight="BOLD">`
const B_S = `<b>`
const B_E = `</b>`
const F_E = "</font>"

const WIDGET_MAIN_CONTENT_HEIGHT = 201
const WIDGET_HEIGHT = 400
const RAID = "rbxassetid://";

const REPARENTING_IDENTIFIER = "Repareting$"

const VERSION_MODAL_PADDING = UDim.new(0, 8)
const CHANGELOG_URL = "https://github.com/gyfdb/pinsandparents/raw/refs/heads/main/changelog.json"
const FAILED_TO_FETCH_STATUS = "Failed to fetch changelog. Check your internet connection."

-- ── Services ──────────────────────────────────────────────────────────────────

const Players = game:GetService("Players")
const Selection = game:GetService("Selection")
const HttpService = game:GetService("HttpService")
const TextService = game:GetService("TextService")
const TweenService = game:GetService("TweenService")
const ChangeHistoryService = game:GetService("ChangeHistoryService")

-- ── Widget ────────────────────────────────────────────────────────────────────

const widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Left,
	false,   -- initially hidden
	false,   -- don't override saved state
	240,     -- default width
	400,     -- default height
	300,     -- min width
	300      -- min height
)

const widget: ScreenGui = plugin:CreateDockWidgetPluginGuiAsync("Organization", widgetInfo)
widget.Title = PLUGIN_NAME
widget.Name  = INTERNAL_NAME
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ── Colours (Studio dark theme palette) ───────────────────────────────────────

const C = {
	BG             = Color3.fromRGB(25,  26,  31),
	PANEL          = Color3.fromRGB(32,  34,  39),
	ITEM           = Color3.fromRGB(44,  46,  54),
	ITEM_HOVER     = Color3.fromRGB(53,  55,  65),
	ITEM_SEL       = Color3.fromRGB(0,   120, 215),
	ITEM_SEL_HOVER = Color3.fromRGB(0,   145, 255),
	BORDER         = Color3.fromRGB(70,  70,  70),
	TEXT           = Color3.fromRGB(230, 231, 234),
	TEXT_DIM       = Color3.fromRGB(158, 159, 161),
	TEXT_DIMMER    = Color3.fromRGB(111, 112, 113),
	TEXT_SEL       = Color3.fromRGB(255, 255, 255),
	BTN            = Color3.fromRGB(65,  68,  80),
	BTN_HOVER      = Color3.fromRGB(79,  82,  97),
	BTN_DANGER     = Color3.fromRGB(180, 50,  50),
	BTN_DANGER_C   = Color3.fromRGB(255, 71,  71),
	BTN_ACTION     = Color3.fromRGB(0,   110, 200),
	BTN_ACTION_H   = Color3.fromRGB(0,   130, 230),
	BTN_ACTION_C   = Color3.fromRGB(0,   145, 255),
	BTN_NEUTRAL    = Color3.fromRGB(40,  41,  49),
	GREEN          = Color3.fromRGB(40,  160, 80),
	GREEN_H        = Color3.fromRGB(50,  190, 100),
	GREEN_C        = Color3.fromRGB(67,  255, 133),
	SCROLLBAR      = Color3.fromRGB(80,  83,  98),
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

function new(cls: string, props: {any}): Instance
	local i = Instance.new(cls)
	for k, v in pairs(props) do i[k] = v end
	return i
end

function newWithOrder(cls: string, props: {any}, order: number): Instance
	local i: GuiObject = new(cls, props)
	i.LayoutOrder = order
	return i
end

function px(n: number): UDim return UDim.new(0, n) end

function hoverEffect(button: TextButton, normal: Color3, hover: Color3, down: Color3?, d_tcolor, tcolor)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = hover
		if d_tcolor then
			button.TextColor3 = d_tcolor
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = normal
		if tcolor then
			button.TextColor3 = tcolor
		end
	end)
	if down then
		button.MouseButton1Down:Connect(function()
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
			end
			button.BackgroundColor3 = down
			if d_tcolor then
				button.TextColor3 = d_tcolor
			end
		end)
		button.MouseButton1Up:Connect(function()
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = true
			end
			button.BackgroundColor3 = hover
		end)
	end
end

-- ── State ─────────────────────────────────────────────────────────────────────

local pinnedFolders: {Folder} = {}   -- array of Folder instances
local connections: {RBXScriptConnection} = {}   -- array of Folder instances' removal connection
local selectedIndex = nil  -- currently highlighted row index
local lastAbsoluteWindowSize = widget.AbsoluteSize
local alreadyCheckedVersion = false

-- ── Functionality ─────────────────────────────────────────────────────────────

function reparent()
	if not selectedIndex then
		setStatus("Pick a folder from the list first.", C.BTN_DANGER)
		return
	end

	local targetFolder = pinnedFolders[selectedIndex]

	if not targetFolder or not targetFolder:IsDescendantOf(game) then
		setStatus("Target folder no longer exists!", C.BTN_DANGER)
		-- clean it up
		table.remove(pinnedFolders, selectedIndex)
		selectedIndex = nil
		rebuildList()
		return
	end

	local sel = Selection:Get()
	local selSize = rawlen(sel)
	if selSize == 0 then
		setStatus("Nothing selected in Explorer.", C.BTN_DANGER)
		return
	end

	for _, inst in ipairs(sel) do
		if inst == targetFolder then
			setStatus("Can't reparent a folder into itself.", C.BTN_DANGER)
			return
		end
	end

	local recording = ChangeHistoryService:TryBeginRecording(REPARENTING_IDENTIFIER)

	if not recording then
		setStatus("Cannot reparent, a change is already in progress.", C.BTN_DANGER)
		return
	end

	for i, inst in ipairs(sel) do
		if i % 5 == 4 then task.wait() end
		inst.Parent = targetFolder
	end

	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)

	setStatus(
		(`Moved {F_M}%d item%s{F_E} to {F_M}%s{F_E}`):format(
			selSize,
			selSize == 1 and "" or "s",
			targetFolder.Name
		),
		C.GREEN
	)
end

-- ── Widget Functionality ──────────────────────────────────────────────────────

widget:BindToClose(function()
	widget.Enabled = false
	toggleButton:SetActive(false)
end)

-- ── Toggle Button ─────────────────────────────────────────────────────────────

toggleButton.ClickableWhenViewportHidden = true
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	toggleButton:SetActive(widget.Enabled)

	if widget.Enabled and not alreadyCheckedVersion then
		alreadyCheckedVersion = true
		checkVersion()
	end
end)

-- ── Reparent Button ───────────────────────────────────────────────────────────

keybindButton.ClickableWhenViewportHidden = true
keybindButton.Click:Connect(reparent)

-- ── Root frame ────────────────────────────────────────────────────────────────

const root = new("Frame", {
	Parent           = widget,
	Size             = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.BG,
	BorderSizePixel  = 0,
})

new("UIPadding", {
	Parent        = root,
	PaddingTop    = px(8),
	PaddingBottom = px(8),
	PaddingLeft   = px(8),
	PaddingRight  = px(8),
})

new("UIListLayout", {
	Parent        = root,
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder     = Enum.SortOrder.LayoutOrder,
	Padding       = UDim.new(0, 6),
})

-- ── UI helpers ────────────────────────────────────────────────────────────────

function sectionLabel(parent: GuiObject, text: string, order: number): TextLabel
	return newWithOrder("TextLabel", {
		Parent                 = parent,
		Size                   = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text                   = text,
		FontFace               = Font.fromName("Montserrat", Enum.FontWeight.Bold),
		TextSize               = 10,
		TextColor3             = C.TEXT_DIM,
		TextXAlignment         = Enum.TextXAlignment.Left,
	}, order)
end

function divider(n: number): Frame
	return newWithOrder("Frame", {
		Parent           = root,
		Size             = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.BORDER,
		BorderSizePixel  = 0,
	}, n)
end

-- ── Folder list panel ─────────────────────────────────────────────────────────

sectionLabel(root, "PINNED FOLDERS", 1)

const listPanel: ScrollingFrame = newWithOrder("ScrollingFrame", {
	Active               = true,
	Size                 = UDim2.new(1, 0, 0, WIDGET_HEIGHT - WIDGET_MAIN_CONTENT_HEIGHT),
	BackgroundColor3     = C.PANEL,
	BorderSizePixel      = 1,
	BorderColor3         = C.BORDER,
	ClipsDescendants     = true,
	CanvasSize           = UDim2.new(),
	ScrollBarImageColor3 = C.SCROLLBAR,
	TopImage             = RAID.."775999050",
	MidImage             = RAID.."1255822465",
	BottomImage          = RAID.."775999473",
	Parent               = root,
}, 2)

const listLayout: UIListLayout = new("UIListLayout", {
	Parent              = listPanel,
	FillDirection       = Enum.FillDirection.Vertical,
	SortOrder           = Enum.SortOrder.LayoutOrder,
	Padding             = UDim.new(0, 1),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment   = Enum.VerticalAlignment.Top,
})

const listPadding: UIPadding = new("UIPadding", {
	Parent        = listPanel,
})

const emptyLabel: TextLabel = new("TextLabel", {
	Parent                 = listPanel,
	AnchorPoint            = Vector2.new(0.5, 0.5),
	Position               = UDim2.fromScale(0.5, 0.5),
	Size                   = UDim2.fromOffset(200, 50),
	BackgroundTransparency = 1,
	Text                   = `No folders pinned.{NL}Select a Folder in Workspace{NL} and click "Pin Selected Folder".`,
	FontFace               = Font.fromName("Montserrat"),
	TextSize               = 11,
	TextColor3             = C.TEXT_DIM,
	TextXAlignment         = Enum.TextXAlignment.Center,
	TextYAlignment         = Enum.TextYAlignment.Center,
	TextWrapped            = true,
})

divider(3)

-- ── Row rendering ─────────────────────────────────────────────────────────────

local rowFrames: {TextButton} = {}

function upateListSize()
	--listPanel.Size = UDim2.new(1, 0, 0, WIDGET_HEIGHT - WIDGET_MAIN_CONTENT_HEIGHT)
	listPanel.Size = UDim2.new(1, 0, 0, math.max(50, widget.AbsoluteSize.Y - WIDGET_MAIN_CONTENT_HEIGHT))
	listPanel.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y)
	listPanel.ScrollingEnabled = listLayout.AbsoluteContentSize.Y > listPanel.AbsoluteSize.Y
	listPadding.PaddingRight = UDim.new(0, listPanel.ScrollingEnabled and listPanel.ScrollBarThickness or 0)
end

function rebuildList()
	-- clear existing rows
	for _, f in ipairs(rowFrames) do f:Destroy() end
	rowFrames = {}

	emptyLabel.Visible = (#pinnedFolders == 0)
	listLayout.VerticalAlignment = Enum.VerticalAlignment[(#pinnedFolders == 0) and "Center" or "Top"]

	for i, folder in ipairs(pinnedFolders) do
		local isSel = (selectedIndex == i)

		local row: TextButton = newWithOrder("TextButton", {
			Active           = true,
			AutoButtonColor  = false,
			Size             = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = isSel and C.ITEM_SEL or C.ITEM,
			BorderSizePixel  = 0,
			Text             = "",
			Parent           = listPanel,
		}, i)

		if not isSel then
			hoverEffect(row, C.ITEM, C.ITEM_HOVER)
		else
			hoverEffect(row, C.ITEM_SEL, C.ITEM_SEL_HOVER)
		end

		new("UIPadding", {
			Parent      = row,
			PaddingLeft = px(8),
			PaddingRight= px(4),
		})

		-- Folder icon
		new("TextLabel", {
			Parent                 = row,
			Size                   = UDim2.new(0, 18, 1, 0),
			BackgroundTransparency = 1,
			Text                   = "📁",
			FontFace               = Font.fromName("Montserrat"),
			TextSize               = 13,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextYAlignment         = Enum.TextYAlignment.Center,
			TextColor3             = C.TEXT,
		})

		local nameLabel = new("TextLabel", {
			Parent                 = row,
			Position               = UDim2.new(0, 22, 0, 0),
			Size                   = UDim2.new(1, -46, 1, 0),
			BackgroundTransparency = 1,
			Text                   = folder.Name,
			FontFace               = Font.fromName("Montserrat", Enum.FontWeight[isSel and "Bold" or "Regular"]),
			TextSize               = 12,
			TextColor3             = isSel and C.TEXT_SEL or C.TEXT,
			TextXAlignment         = Enum.TextXAlignment.Left,
			TextYAlignment         = Enum.TextYAlignment.Center,
			TextTruncate           = Enum.TextTruncate.AtEnd,
		})

		-- Remove button
		local removeBtn = new("TextButton", {
			Parent                 = row,
			Position               = UDim2.new(1, -22, 0, 4),
			Size                   = UDim2.new(0, 18, 0, 20),
			BackgroundColor3       = Color3.fromRGB(0,0,0),
			BackgroundTransparency = 1,
			Text                   = "×",
			FontFace               = Font.fromName("Montserrat", Enum.FontWeight.Bold),
			TextSize               = 16,
			TextColor3             = C.TEXT_DIM,
			ZIndex                 = 2,
		})

		removeBtn.MouseEnter:Connect(function()
			removeBtn.TextColor3 = Color3.fromRGB(220, 80, 80)
		end)
		removeBtn.MouseLeave:Connect(function()
			removeBtn.TextColor3 = C.TEXT_DIM
		end)

		removeBtn.MouseButton1Click:Connect(function()
			if selectedIndex == i then
				selectedIndex = nil
			elseif selectedIndex and selectedIndex > i then
				selectedIndex = selectedIndex - 1
			end
			table.remove(pinnedFolders, i)
			rebuildList()
		end)

		-- Select row on click
		row.MouseButton1Click:Connect(function(input)
			if selectedIndex == i then
				selectedIndex = nil
			else
				selectedIndex = i
			end
			rebuildList()
			setStatus(`Set <b>{folder.Name}</b> as selected folder.`)
		end)

		table.insert(rowFrames, row)
	end

	upateListSize()
end

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(upateListSize)
widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if lastAbsoluteWindowSize.Y ~= widget.AbsoluteSize.Y then
		upateListSize()
	end 
	lastAbsoluteWindowSize = widget.AbsoluteSize
end)

-- ── Button bar ────────────────────────────────────────────────────────────────

local function makeBtn(parent: GuiObject, text: string, order: number, color: Color3, hcolor: Color3, ccolor: Color3?, tcolor: Color3?): TextButton
	local btn: TextButton = newWithOrder("TextButton", {
		Active           = true,
		AutoButtonColor  = false,
		BackgroundColor3 = color,
		BorderSizePixel  = 0,
		Size             = UDim2.new(1, 0, 0, 28),
		FontFace         = Font.fromName("Montserrat", Enum.FontWeight.Bold),
		Text             = text,
		TextColor3       = tcolor or C.TEXT_SEL,
		TextSize         = 14,
		TextTruncate     = Enum.TextTruncate.SplitWord,
		Parent           = parent,
	}, order)
	new("UICorner", {
		Parent = btn,
		CornerRadius = px(4)
	})
	hoverEffect(btn, color, hcolor, ccolor, C.TEXT_SEL, btn.TextColor3)
	return btn
end

-- Pin selected folder
local pinBtn: TextButton = makeBtn(root, "Pin Folder(s)", 4, C.GREEN, C.GREEN_H, C.GREEN_C)

-- Reparent selection
local reparentBtn: TextButton = makeBtn(root, "Reparent Selection", 5, C.BTN_ACTION, C.BTN_ACTION_H, C.BTN_ACTION_C)

-- Reparent selection
local clearBtn: TextButton = makeBtn(root, "Clear Pinned", 6, C.BTN_NEUTRAL, C.BTN_DANGER, C.BTN_DANGER_C, C.BTN_DANGER_C)
new("UIStroke", {
	Color                = C.BTN_DANGER,
	Thickness            = 2,
	LineJoinMode         = Enum.LineJoinMode.Round,
	BorderStrokePosition = Enum.BorderStrokePosition.Inner,
	ApplyStrokeMode      = Enum.ApplyStrokeMode.Border,
	Parent               = clearBtn
})

divider(7)

-- ── Status bar ────────────────────────────────────────────────────────────────

local statusLabel: TextLabel = newWithOrder("TextLabel", {
	Parent                 = root,
	Size                   = UDim2.new(1, 0, 0, 12),
	BackgroundTransparency = 1,
	Text                   = "Select a Folder(s) in the workspace to begin pinning.",
	FontFace               = Font.fromName("Montserrat"),
	RichText               = true,
	TextSize               = 11,
	TextColor3             = C.TEXT_DIM,
	TextTruncate           = Enum.TextTruncate.SplitWord,
	TextWrapped            = true,
	TextXAlignment         = Enum.TextXAlignment.Left,
	TextYAlignment         = Enum.TextYAlignment.Top,
}, 8)

function setStatus(msg: string, color: Color3)
	statusLabel.Text       = msg
	statusLabel.TextColor3 = color or C.TEXT_DIM
end

divider(9)

-- ── Pin logic ─────────────────────────────────────────────────────────────────

pinBtn.MouseButton1Click:Connect(function()
	local sel = Selection:Get()

	if #sel == 0 then
		setStatus("Nothing selected.", C.BTN_DANGER)
		return
	end

	local added = 0
	for _, inst in ipairs(sel) do
		-- accept Folder instances that live in game (or its descendants)
		if inst.ClassName == "Folder" and inst:IsDescendantOf(game) then
			-- de-duplicate
			if table.find(pinnedFolders, inst) then continue end
			local conn
			conn = inst.AncestryChanged:Connect(function(childing, parenting)
				if parenting == nil then
					for i, pinned: Folder in pinnedFolders do
						if pinned == inst then
							table.remove(pinnedFolders, i)
						end
						setStatus(`Folder "{inst.Name}" no longer exists!`, C.BTN_DANGER)
						rebuildList()
					end
					conn:Disconnect()
				end
			end)
			table.insert(pinnedFolders, inst)
			added += 1
		end
	end

	if added > 0 then
		setStatus(("Pinned %d folder%s."):format(added, added == 1 and "" or "s"), C.TEXT)
		rebuildList()
	else
		setStatus("Select Folder(s) inside Workspace.", C.BTN_DANGER)
	end
end)

-- ── Reparent logic ────────────────────────────────────────────────────────────

reparentBtn.MouseButton1Click:Connect(reparent)

-- ── Clear logic ───────────────────────────────────────────────────────────────

clearBtn.MouseButton1Click:Connect(function()
	table.clear(pinnedFolders)
	rebuildList()
	setStatus(
		"Cleared pinned folder list.",
		C.GREEN
	)
end)

-- ── Version checker ───────────────────────────────────────────────────────────

local backdrop: Frame = new("TextButton", {
	Active                 = true,
	AutoButtonColor        = false,
	BackgroundColor3       = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.4,
	Size                   = UDim2.fromScale(1, 1),
	ZIndex                 = 2,
	Text                   = "",
	Visible                = false,
	Parent                 = widget,
})

local versionModal: Frame = new("Frame", {
	AnchorPoint            = Vector2.one * 0.5,
	AutomaticSize          = Enum.AutomaticSize.XY,
	BackgroundColor3       = C.PANEL,
	Position               = UDim2.fromScale(0.5, 0.5),
	Size                   = UDim2.fromScale(0.9, 0.9),
	ZIndex                 = 3,
	Visible                = false,
	Parent                 = widget,
})

new("UIPadding", {
	PaddingBottom = VERSION_MODAL_PADDING,
	PaddingLeft   = VERSION_MODAL_PADDING,
	PaddingRight  = VERSION_MODAL_PADDING,
	PaddingTop    = VERSION_MODAL_PADDING,
	Parent        = versionModal,
})

new("UICorner", {
	CornerRadius = UDim.new(0, 6),
	Parent       = versionModal,
})

new("UIListLayout", {
	Padding             = UDim.new(0, 6),
	SortOrder           = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalFlex        = Enum.UIFlexAlignment.Fill,
	Parent              = versionModal,
})

new("UISizeConstraint", {
	MaxSize = Vector2.new(350, 300),
	MinSize = Vector2.new(100, 100),
	Parent  = versionModal,
})

new("UIStroke", {
	Color  = C.BORDER,
	Parent = versionModal,
})

local modalTitle: TextLabel = newWithOrder("TextLabel", {
	BackgroundTransparency = 1,
	Size                   = UDim2.new(1, 0, 0, 30),
	FontFace               = Font.fromName("Montserrat", Enum.FontWeight.Bold),
	Text                   = "UPDATE AVAILABLE",
	TextColor3             = C.TEXT_SEL,
	TextSize               = 14,
	Parent                 = versionModal,
}, 1)

local modalScroll: ScrollingFrame = newWithOrder("ScrollingFrame", {
	Active               = true,
	BackgroundColor3     = C.PANEL,
	BorderSizePixel      = 1,
	BorderColor3         = C.BORDER,
	Size                 = UDim2.fromScale(1, 1),
	ClipsDescendants     = true,
	CanvasSize           = UDim2.new(),
	ScrollBarImageColor3 = C.SCROLLBAR,
	TopImage             = RAID.."775999050",
	MidImage             = RAID.."1255822465",
	BottomImage          = RAID.."775999473",
	Parent               = versionModal,
}, 2)

const modalScrollLayout: UIListLayout = new("UIListLayout", {
	FillDirection       = Enum.FillDirection.Vertical,
	SortOrder           = Enum.SortOrder.LayoutOrder,
	Padding             = UDim.new(0, 1),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment   = Enum.VerticalAlignment.Top,
	Parent              = modalScroll,
})

local modalScrollPadding: UIPadding = new("UIPadding", {
	PaddingBottom = VERSION_MODAL_PADDING,
	PaddingLeft   = VERSION_MODAL_PADDING,
	PaddingRight  = VERSION_MODAL_PADDING,
	PaddingTop    = VERSION_MODAL_PADDING,
	Parent = modalScroll,
})

local modalButton: TextButton = makeBtn(versionModal, "Continue", 3, C.BTN_NEUTRAL, C.BTN_DANGER, C.BTN_DANGER_C, C.BTN_DANGER_C)
modalButton.Size = UDim2.new(0.5, 0, 0, 28)
new("UISizeConstraint", {
	MaxSize = Vector2.new(150, math.huge),
	Parent  = modalButton,
})
new("UIStroke", {
	Color                = C.BTN_DANGER,
	Thickness            = 2,
	LineJoinMode         = Enum.LineJoinMode.Round,
	BorderStrokePosition = Enum.BorderStrokePosition.Inner,
	ApplyStrokeMode      = Enum.ApplyStrokeMode.Border,
	Parent               = clearBtn,
})

local exampleChangelogDescription: TextLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Size                   = UDim2.fromScale(1, 1),
	FontFace               = Font.fromName("Montserrat"),
	RichText               = true,
	Text                   = "N/A",
	TextColor3             = C.TEXT,
	TextWrapped            = true,
	TextXAlignment         = Enum.TextXAlignment.Left,
	TextYAlignment         = Enum.TextYAlignment.Top,
	TextSize               = 12,
})

function hideVersionModal()
	versionModal.Visible = false
	backdrop.Visible = false
end

function showVersionModal()
	versionModal.Visible = true
	backdrop.Visible = true
end

function updateChangelogList()
	modalScroll.CanvasSize = UDim2.fromOffset(0, modalScrollLayout.AbsoluteContentSize.Y)
	modalScroll.ScrollingEnabled = modalScrollLayout.AbsoluteContentSize.Y > modalScroll.AbsoluteSize.Y
	modalScrollPadding.PaddingRight = UDim.new(0, modalScroll.ScrollingEnabled and (VERSION_MODAL_PADDING.Offset + modalScroll.ScrollBarThickness) or 0)
end

function getVersions()
	local res = HttpService:GetAsync(CHANGELOG_URL, true)
	return HttpService:JSONDecode(res)
end

function createVersionLog(versionData)
	local versionDescription: TextLabel = exampleChangelogDescription:Clone()
	local newLabel = (versionData.versionNumber > PLUGIN_VERSION_NUMBER) and "(NEW) - " or ""
	local versionText = `{B_S}{newLabel}Version {versionData.versionString}{B_E}\n{versionData.description}`
	versionDescription.Text = versionText 
	versionDescription.Parent = modalScroll

	local content = versionDescription.ContentText
	local params = Instance.new("GetTextBoundsParams")
	params.Size = 12
	params.Text = versionText
	params.Width = versionDescription.AbsoluteSize.X - (VERSION_MODAL_PADDING.Offset + modalScroll.ScrollBarThickness)
	params.Font = Font.fromName("Montserrat")
	params.RichText = true

	local success, bounds: Vector2 = pcall(TextService.GetTextBoundsAsync, TextService, params)

	if success then
		versionDescription.Size = UDim2.new(1, 0, 0, bounds.Y + 20)
	else
		local newLines = #versionText:split("\n")
		versionDescription.Size = UDim2.new(1, 0, 0, (newLines * 20) + 40)
	end

	workspace.Destroy(params)
end

function loadVersions(data)
	local versions = {}

	for _, versionData in data do
		table.insert(versions, versionData)
	end

	table.sort(versions, function(a, b)
		return a.versionNumber > b.versionNumber
	end)

	if versions[1].versionNumber ~= PLUGIN_VERSION_NUMBER then
		showVersionModal()

		for _, versionData in versions do
			createVersionLog(versionData)
		end

		task.delay(0.1, updateChangelogList)
	end
end

function checkVersion()
	local success, data = pcall(getVersions)

	if not success then
		setStatus(FAILED_TO_FETCH_STATUS, C.BTN_DANGER_C)

		task.wait(15)

		if statusLabel.Text == FAILED_TO_FETCH_STATUS then
			setStatus("Select a Folder(s) in the workspace to begin pinning.", C.TEXT_DIM)
		end
	else
		loadVersions(data)
	end
end

modalButton.MouseButton1Click:Connect(function()
	hideVersionModal()
end)

-- ── Creator ───────────────────────────────────────────────────────────────────

do
	local success, creator_name = pcall(Players.GetNameFromUserIdAsync, Players, 5836169454)
	if not success then
		creator_name = "one7and7"
	end
	local created_by = `Created by <b>{creator_name}</b>.`

	local creator_label: TextLabel = newWithOrder("TextLabel", {
		Parent                 = root,
		Size                   = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text                   = created_by,
		FontFace               = Font.fromName("Montserrat"),
		RichText               = true,
		TextSize               = 12,
		TextColor3             = C.TEXT_DIMMER,
		TextTruncate           = Enum.TextTruncate.SplitWord,
		TextXAlignment         = Enum.TextXAlignment.Center,
		TextYAlignment         = Enum.TextYAlignment.Center,
	}, 9)

	local cl_t = 0

	local function changeText(now: number)
		if cl_t ~= now then return end
		creator_label.Text = `{PLUGIN_VERSION_STRING} • All Rights Reserved`
	end

	creator_label.MouseEnter:Connect(function()
		local now = tick()
		cl_t = now

		task.delay(3, changeText, now)
	end)
	creator_label.MouseLeave:Connect(function()
		cl_t = 0
		creator_label.Text = created_by
	end)
end

-- ── Initial render ────────────────────────────────────────────────────────────

rebuildList()
