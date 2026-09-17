-- CHATBOX WINDOW_2.lua
do
    local ChatOpen = false
    local ChatMessages = {}
    local ReplyTarget = nil
    local NicknameTarget = nil
    local MuteDurationTarget = nil
    local ActiveMessageRows = {}
local DeniedInviteIds = {}
    local MutedUsernamesMap = {}
    local LocalMuteExpiration = 0

    -- Move HttpRequest declaration to the top so all functions can access it
    local HttpRequest = request or http_request or (syn and syn.request) or nil

    local NICKNAME_FILE = "chatbox_nicknames.json"
    local CustomNicknames = {}

    local function LoadNicknames()
        if isfile and readfile and isfile(NICKNAME_FILE) then
            pcall(function()
                CustomNicknames = game:GetService("HttpService"):JSONDecode(readfile(NICKNAME_FILE)) or {}
            end)
        end
    end

    local function SaveNicknames()
        if writefile then
            pcall(function()
                writefile(NICKNAME_FILE, game:GetService("HttpService"):JSONEncode(CustomNicknames))
            end)
        end
    end

    LoadNicknames()

    local function GetDisplayName(username)
        return CustomNicknames[username] or username
    end

    local function FormatDuration(seconds)
        if not seconds or seconds <= 0 then return "0s" end
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        local secs = math.floor(seconds % 60)

        local parts = {}
        if days > 0 then table.insert(parts, days .. "d") end
        if hours > 0 then table.insert(parts, hours .. "h") end
        if mins > 0 then table.insert(parts, mins .. "m") end
        if secs > 0 or #parts == 0 then table.insert(parts, secs .. "s") end
        return table.concat(parts, " ")
    end

    local AdminUserIds = {
        [11117216138] = true,
        [6136594189] = true,
        [2327711124] = true,
    }

    local function IsAdmin(userId, username)
        if userId then
            local numId = tonumber(userId)
            if numId and AdminUserIds[numId] then return true end
        end
        if username then
            local success, fetchedId = pcall(function()
                return game:GetService("Players"):GetUserIdFromNameAsync(username)
            end)
            if success and fetchedId and AdminUserIds[fetchedId] then return true end
        end
        return false
    end

    -- Cache of users for @mentions (populated strictly via VPS KnownUsers)
    local SeenUsers = {}
    local function RegisterSeenUser(username)
        if username and type(username) == "string" and username ~= "" then
            SeenUsers[username] = true
        end
    end

    -- Function to register user to the VPS for cross-server visibility
    local function RegisterUserToVPS(username)
        if not HttpRequest then return end
        task.spawn(function()
            pcall(function()
                HttpRequest({
                    Url = "http://167.99.144.89:8081/chatbox/register",
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                    },
                    Body = game:GetService("HttpService"):JSONEncode({ Username = username })
                })
            end)
        end)
    end

    -- Send ONLY the local player's username to the VPS on load and add to local mentions
    if game:GetService("Players").LocalPlayer then
        RegisterSeenUser(game:GetService("Players").LocalPlayer.Name)
        RegisterUserToVPS(game:GetService("Players").LocalPlayer.Name)
    end

    local ChatGui = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = "BackgroundColor",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(380, 480),
        Visible = false,
        ZIndex = 500,
        Parent = ScreenGui,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius), Parent = ChatGui })
    New("UIStroke", { Color = "OutlineColor", Thickness = 1, Parent = ChatGui })
    table.insert(Library.Scales, New("UIScale", { Parent = ChatGui }))

    local ChatTitleBar = New("Frame", {
        BackgroundColor3 = "MainColor",
        Size = UDim2.new(1, 0, 0, 36),
        ZIndex = 501,
        Parent = ChatGui,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius), Parent = ChatTitleBar })
    New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = "MainColor",
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, Library.CornerRadius),
        ZIndex = 501,
        Parent = ChatTitleBar,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "Global Chat",
        TextColor3 = "FontColor",
        TextSize = 15,
        ZIndex = 502,
        Parent = ChatTitleBar,
    })

    local MailBtn = New("TextButton", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = "MainColor",
        Position = UDim2.new(0, 36, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        Text = "",
        ZIndex = 510,
        Parent = ChatTitleBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = MailBtn })
    New("UIStroke", { Color = "OutlineColor", Parent = MailBtn })

    -- Discord-style notification badge elements
    local MailBadge = New("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Color3.fromRGB(237, 66, 69),
        Position = UDim2.new(1, 4, 0, -4),
        Size = UDim2.fromOffset(18, 18),
        Visible = false,
        ZIndex = 515,
        Parent = MailBtn,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = MailBadge })
    New("UIStroke", { Color = Color3.fromRGB(54, 57, 63), Thickness = 1.5, Parent = MailBadge })

    local MailBadgeText = New("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "0",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        ZIndex = 516,
        Parent = MailBadge,
    })

    local MailIcon = Library:GetIcon("mail")
    if MailIcon then
        New("ImageLabel", {
            BackgroundTransparency = 1,
            Image = MailIcon.Url,
            ImageColor3 = "FontColor",
            ImageRectOffset = MailIcon.ImageRectOffset,
            ImageRectSize = MailIcon.ImageRectSize,
            Size = UDim2.new(1, -6, 1, -6),
            Position = UDim2.fromOffset(3, 3),
            ZIndex = 511,
            Parent = MailBtn,
        })
    else
        MailBtn.Text = "✉"
        MailBtn.TextSize = 13
    end

-- Smooth Hover Highlight Effect (Matches Settings button color seamlessly)
    local TweenService = game:GetService("TweenService")
    local hoverTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    MailBtn.MouseEnter:Connect(function()
        TweenService:Create(MailBtn, hoverTweenInfo, { BackgroundColor3 = Color3.fromRGB(88, 101, 242) }):Play()
    end)

    MailBtn.MouseLeave:Connect(function()
        -- Revert back to using the resolved Color3 table property instead of a raw string
        TweenService:Create(MailBtn, hoverTweenInfo, { BackgroundColor3 = Library.Scheme.MainColor or Color3.fromRGB(30, 31, 34) }):Play()
    end)
  -- Larger MailPanel positioned on the left side of the chat window (increased to 380x480)
    local MailPanel = New("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = "BackgroundColor",
        Position = UDim2.fromOffset(-10, 0),
        Size = UDim2.fromOffset(380, 480),
        Visible = false,
        ZIndex = 600,
        Parent = ChatGui,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius), Parent = MailPanel })
    New("UIStroke", { Color = "OutlineColor", Thickness = 1, Parent = MailPanel })

    New("UIPadding", {
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 0),
        Parent = MailPanel,
    })

    local MailScroll = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromScale(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarImageColor3 = "OutlineColor",
        ScrollBarThickness = 4,
        ZIndex = 601,
        Parent = MailPanel,
    })

    -- Balanced padding to safely prevent stroke clipping on all sides
    New("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
        Parent = MailScroll,
    })

    New("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = MailScroll,
    })

    -- Discord-style smart auto-scroll tracker
    local UserIsScrolledUp = false
    MailScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        local scrollPos = MailScroll.CanvasPosition.Y
        local maxScroll = MailScroll.AbsoluteCanvasSize.Y - MailScroll.AbsoluteWindowSize.Y
        if maxScroll > 0 then
            UserIsScrolledUp = (scrollPos < (maxScroll - 30))
        end
    end)

   local MarketplaceService = game:GetService("MarketplaceService")
    local LastRenderedInviteSignature = ""
    local LastSeenSignature = "" -- Tracks IDs of invites that have been viewed/acknowledged
    local LatestInvitesList = nil -- Keeps a live reference to the latest invites array

    local function RenderInvites(invitesList)
        LatestInvitesList = invitesList -- Store reference globally for the click event
        local currentSignature = ""
        local unreadCount = 0
        local activeSignature = ""

        -- Helper function to send delete request to VPS
        local function deleteInviteOnVPS(inviteId)
            LastRenderedInviteSignature = ""
            if HttpRequest then
                task.spawn(function()
                    pcall(function()
                        HttpRequest({
                            Url = "http://167.99.144.89:8081/chatbox/invites/delete",
                            Method = "POST",
                            Headers = {
                                ["Content-Type"] = "application/json",
                                ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                            },
                            Body = game:GetService("HttpService"):JSONEncode({
                                Id = inviteId,
                                Username = LocalPlayer.Name
                            })
                        })
                    end)
                end)
            end
        end

-- Check if invites setting is turned OFF
        local invitesEnabled = true
        if ChatSettings and ChatSettings.EnableInvites ~= nil then
            invitesEnabled = ChatSettings.EnableInvites
        elseif _G.Settings and _G.Settings.InvitesEnabled ~= nil then
            invitesEnabled = _G.Settings.InvitesEnabled
        elseif Toggles and Toggles.InvitesEnabled then
            invitesEnabled = Toggles.InvitesEnabled.Value
        end

if not invitesEnabled then
    for _, child in ipairs(MailScroll:GetChildren()) do
        if child:IsA("GuiObject") and child.Name == "InviteRowTag" then
            child:Destroy()
        end
    end

    if invitesList then
        for _, inv in ipairs(invitesList) do
            if inv.InvitedUsername and inv.InvitedUsername:lower() == LocalPlayer.Name:lower() then
                local invIdStr = tostring(inv.Id)
                if not DeniedInviteIds[invIdStr] then
                    DeniedInviteIds[invIdStr] = true
                    if HttpRequest then
                        task.spawn(function()
                            pcall(function()
                                HttpRequest({
                                    Url = "http://167.99.144.89:8081/chatbox/invites/delete",
                                    Method = "POST",
                                    Headers = {
                                        ["Content-Type"] = "application/json",
                                        ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                                    },
                                    Body = game:GetService("HttpService"):JSONEncode({
                                        Id = inv.Id,
                                        Username = LocalPlayer.Name
                                    })
                                })
                            end)
                        end)
                    end
                end
            end
        end
    end

    MailBadge.Visible = false
    MailBadgeText.Text = "0"
    return
end
        if invitesList then
            for _, inv in ipairs(invitesList) do
                if inv.InvitedUsername and inv.InvitedUsername:lower() == LocalPlayer.Name:lower() then
                    local invIdStr = tostring(inv.Id)
                    activeSignature = activeSignature .. invIdStr
                    currentSignature = currentSignature .. invIdStr

                    -- Count as unread only if the mail panel is closed AND it hasn't been seen yet
                    if not MailOpen and not string.find(LastSeenSignature, invIdStr) then
                        unreadCount = unreadCount + 1
                    end
                end
            end
        end

        -- If mail panel is open, automatically mark everything currently present as seen
        if MailOpen then
            LastSeenSignature = activeSignature
            unreadCount = 0
        end

        -- Update badge state dynamically
        if unreadCount > 0 then
            MailBadgeText.Text = tostring(unreadCount)
            MailBadge.Visible = true
        else
            MailBadge.Visible = false
        end

        if currentSignature == LastRenderedInviteSignature then
            return
        end

        -- Check if user was at the bottom before refreshing content
        local wasAtBottom = not UserIsScrolledUp
        LastRenderedInviteSignature = currentSignature

        for _, child in ipairs(MailScroll:GetChildren()) do
            if child:IsA("GuiObject") and child.Name == "InviteRowTag" then
                child:Destroy()
            end
        end

        if not invitesList or currentSignature == "" then
            New("TextLabel", {
                Name = "InviteRowTag",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 40),
                Text = "No messages yet.",
                TextColor3 = "FontColor",
                TextSize = 14,
                TextTransparency = 0.5,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 602,
                Parent = MailScroll,
            })
            return
        end

        for _, inv in ipairs(invitesList) do
            if inv.InvitedUsername and inv.InvitedUsername:lower() == LocalPlayer.Name:lower() then
                local InviteRow = New("Frame", {
                    Name = "InviteRowTag",
                    BackgroundColor3 = Color3.fromRGB(30, 32, 38),
                    Size = UDim2.new(1, -6, 0, 115),
                    ZIndex = 602,
                    Parent = MailScroll,
                })
                New("UICorner", { CornerRadius = UDim.new(0, 6), Parent = InviteRow })
                New("UIStroke", { Color = Color3.fromRGB(88, 101, 242), Thickness = 1, Parent = InviteRow })
                New("UIPadding", { PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), Parent = InviteRow })

                New("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 20),
                    Text = tostring(inv.SenderUsername) .. " invited you to game",
                    TextColor3 = Color3.fromRGB(220, 221, 222),
                    TextSize = 13,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 603,
                    Parent = InviteRow,
                })

                local InfoContainer = New("Frame", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0, 24),
                    Size = UDim2.new(1, 0, 0, 50),
                    ZIndex = 603,
                    Parent = InviteRow,
                })

                local IconLabel = New("ImageLabel", {
                    BackgroundColor3 = Color3.fromRGB(20, 20, 20),
                    Size = UDim2.fromOffset(50, 50),
                    Position = UDim2.new(0, 0, 0, 0),
                    Image = "",
                    ZIndex = 604,
                    Parent = InfoContainer,
                })
                New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = IconLabel })

                local DetailsContainer = New("Frame", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 58, 0, 0),
                    Size = UDim2.new(1, -58, 1, 0),
                    ZIndex = 604,
                    Parent = InfoContainer,
                })

                local NameLabel = New("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 26),
                    Text = "Loading Game...",
                    TextColor3 = Color3.fromRGB(255, 255, 255),
                    TextSize = 13,
                    Font = Enum.Font.GothamSemibold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 605,
                    Parent = DetailsContainer,
                })

                local playerCountText = inv.Players and tostring(inv.Players) or "Unknown"
                local PlayersLabel = New("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0, 26),
                    Size = UDim2.new(1, 0, 0, 20),
                    Text = "Players Here: " .. playerCountText,
                    TextColor3 = Color3.fromRGB(150, 151, 156),
                    TextSize = 12,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 605,
                    Parent = DetailsContainer,
                })

                task.spawn(function()
                    local placeId = tonumber(inv.PlaceId)
                    if placeId then
                        local success, productInfo = pcall(function()
                            return MarketplaceService:GetProductInfo(placeId)
                        end)
                        if success and productInfo then
                            NameLabel.Text = productInfo.Name or "Unknown Game"
                            if productInfo.IconImageAssetId and productInfo.IconImageAssetId > 0 then
                                IconLabel.Image = "rbxassetid://" .. tostring(productInfo.IconImageAssetId)
                            else
                                IconLabel.Image = string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", placeId)
                            end
                        else
                            NameLabel.Text = "Game ID: " .. tostring(placeId)
                            IconLabel.Image = string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", placeId)
                        end
                    end
                end)

                local ButtonHolder = New("Frame", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0, 78),
                    Size = UDim2.new(1, 0, 0, 24),
                    ZIndex = 603,
                    Parent = InviteRow,
                })
                New("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 8),
                    Parent = ButtonHolder,
                })

                -- Accept Button (Green)
                local AcceptBtn = New("TextButton", {
                    BackgroundColor3 = Color3.fromRGB(46, 204, 113),
                    Size = UDim2.new(0.5, -4, 1, 0),
                    Text = "Accept",
                    TextColor3 = Color3.fromRGB(255, 255, 255),
                    TextSize = 12,
                    Font = Enum.Font.GothamBold,
                    ZIndex = 604,
                    Parent = ButtonHolder,
                })
                New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = AcceptBtn })

                AcceptBtn.MouseButton1Click:Connect(function()
                    deleteInviteOnVPS(inv.Id) -- Deletes from VPS when accepted
                    InviteRow:Destroy()
                    pcall(function()
                        local TeleportService = game:GetService("TeleportService")
                        local placeId = tonumber(inv.PlaceId)
                        local jobId = inv.JobId

                        if placeId and jobId then
                            TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                        end
                    end)
                end)

                -- Deny Button (Red)
                local DenyBtn = New("TextButton", {
                    BackgroundColor3 = Color3.fromRGB(231, 76, 60),
                    Size = UDim2.new(0.5, -4, 1, 0),
                    Text = "Deny",
                    TextColor3 = Color3.fromRGB(255, 255, 255),
                    TextSize = 12,
                    Font = Enum.Font.GothamBold,
                    ZIndex = 604,
                    Parent = ButtonHolder,
                })
                New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = DenyBtn })

                DenyBtn.MouseButton1Click:Connect(function()
                    deleteInviteOnVPS(inv.Id)
                    InviteRow:Destroy()
                end)
            end
        end

        -- Auto-scroll down only if user was already at the bottom
        if wasAtBottom then
            task.defer(function()
                MailScroll.CanvasPosition = Vector2.new(0, MailScroll.AbsoluteCanvasSize.Y)
            end)
        end
    end

    local MailOpen = false
    MailBtn.MouseButton1Click:Connect(function()
        MailOpen = not MailOpen
        MailPanel.Visible = MailOpen

        if MailOpen then
            -- Immediately clear badge and update LastSeenSignature when opened
            MailBadge.Visible = false
            MailBadgeText.Text = "0"

            -- Instantly lock in current invites as seen so they don't pop back up as unread
            if LatestInvitesList then
                local snapshotSig = ""
                for _, inv in ipairs(LatestInvitesList) do
                    if inv.InvitedUsername and inv.InvitedUsername:lower() == LocalPlayer.Name:lower() then
                        snapshotSig = snapshotSig .. tostring(inv.Id)
                    end
                end
                LastSeenSignature = snapshotSig
            end
        end

        if MailOpen and SettingsOpen then
            SettingsOpen = false
            SettingsPanel.Visible = false
        end
    end)

    Library:GiveSignal(UserInputService.InputBegan:Connect(function(Input)
        if not IsClickInput(Input) or not MailOpen then return end
        local mousePos = Input.Position
        if not Library:MouseIsOverFrame(MailPanel, mousePos) and not Library:MouseIsOverFrame(MailBtn, mousePos) then
            MailOpen = false
            MailPanel.Visible = false
        end
    end))

    local GearBtn = New("TextButton", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = "MainColor",
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        Text = "",
        ZIndex = 510,
        Parent = ChatTitleBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = GearBtn })
    New("UIStroke", { Color = "OutlineColor", Parent = GearBtn })
    local GearIcon = Library:GetIcon("settings")
    if GearIcon then
        New("ImageLabel", {
            BackgroundTransparency = 1,
            Image = GearIcon.Url,
            ImageColor3 = "FontColor",
            ImageRectOffset = GearIcon.ImageRectOffset,
            ImageRectSize = GearIcon.ImageRectSize,
            Size = UDim2.new(1, -6, 1, -6),
            Position = UDim2.fromOffset(3, 3),
            ZIndex = 511,
            Parent = GearBtn,
        })
    else
        GearBtn.Text = "⚙"
        GearBtn.TextSize = 13
    end

    -- Smooth Hover Effect for Gear Button (Matches the Mail button)
    GearBtn.MouseEnter:Connect(function()
        TweenService:Create(GearBtn, hoverTweenInfo, { BackgroundColor3 = Color3.fromRGB(88, 101, 242) }):Play()
    end)

    GearBtn.MouseLeave:Connect(function()
        TweenService:Create(GearBtn, hoverTweenInfo, { BackgroundColor3 = Library.Scheme.MainColor or Color3.fromRGB(30, 31, 34) }):Play()
    end)

-- Settings panel
    local CHATSETTINGS_FILE = "chatbox_settings.json"
    local ChatSettings = {
        EnablePings = false,
        EnableInvites = false, -- <--- ADD THIS
        ChatTextSize = 14,
    }
local function SaveChatSettings()
        if writefile then
            pcall(function()
                writefile(CHATSETTINGS_FILE, game:GetService("HttpService"):JSONEncode(ChatSettings))
            end)
        end
    end
    local function LoadChatSettings()
        if isfile and readfile and isfile(CHATSETTINGS_FILE) then
            pcall(function()
                local loaded = game:GetService("HttpService"):JSONDecode(readfile(CHATSETTINGS_FILE))
                if type(loaded) == "table" then
                    if typeof(loaded.EnablePings) == "boolean" then
                        ChatSettings.EnablePings = loaded.EnablePings
                    end
                    if typeof(loaded.EnableInvites) == "boolean" then -- <--- ADD THIS
                        ChatSettings.EnableInvites = loaded.EnableInvites
                    end
                    if typeof(loaded.ChatTextSize) == "number" then
                        ChatSettings.ChatTextSize = math.clamp(loaded.ChatTextSize, 10, 22)
                    end
                end
            end)
        end
    end
    LoadChatSettings()

-- NEW: Nuke any pending invites on load if invites are disabled
if not ChatSettings.EnableInvites and HttpRequest then
    task.spawn(function()
        pcall(function()
            HttpRequest({
                Url = "http://167.99.144.89:8081/chatbox/invites/deleteall",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                },
                Body = game:GetService("HttpService"):JSONEncode({
                    Username = game:GetService("Players").LocalPlayer.Name
                })
            })
        end)
    end)
end


    local SettingsPanel = New("Frame", {
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = "BackgroundColor",
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.fromOffset(220, 140),
        Visible = false,
        ZIndex = 600,
        Parent = ChatGui,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius), Parent = SettingsPanel })
    New("UIStroke", { Color = "OutlineColor", Thickness = 1, Parent = SettingsPanel })
    New("UIPadding", {
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 10),
        Parent = SettingsPanel,
    })
    New("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = SettingsPanel,
    })

    -- Enable Pings toggle row
    local PingToggleRow = New("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 18),
        ZIndex = 601,
        Parent = SettingsPanel,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -42, 1, 0),
        Text = "Enable Pings",
        TextColor3 = "FontColor",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 602,
        Parent = PingToggleRow,
    })

    local PingSwitch = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = "MainColor",
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(32, 18),
        ZIndex = 602,
        Parent = PingToggleRow,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = PingSwitch })
    New("UIStroke", { Color = "OutlineColor", Parent = PingSwitch })
    Library:RemoveFromRegistry(PingSwitch)
    New("UIPadding", {
        PaddingBottom = UDim.new(0, 2),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 2),
        PaddingTop = UDim.new(0, 2),
        Parent = PingSwitch,
    })

    local PingBall = New("Frame", {
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = "FontColor",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        SizeConstraint = Enum.SizeConstraint.RelativeYY,
        ZIndex = 603,
        Parent = PingSwitch,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = PingBall })

    local PingSwitchBtn = New("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        ZIndex = 604,
        Parent = PingSwitch,
    })

    local function UpdatePingSwitch()
        local on = ChatSettings.EnablePings
        TweenService:Create(PingSwitch, Library.TweenInfo, {
            BackgroundColor3 = on and Library.Scheme.AccentColor or Library.Scheme.MainColor,
        }):Play()
        TweenService:Create(PingBall, Library.TweenInfo, {
            AnchorPoint = Vector2.new(on and 1 or 0, 0),
            Position = UDim2.fromScale(on and 1 or 0, 0),
        }):Play()
    end

    PingSwitchBtn.MouseButton1Click:Connect(function()
        ChatSettings.EnablePings = not ChatSettings.EnablePings
        UpdatePingSwitch()
        SaveChatSettings()
    end)
    task.spawn(function()
        task.wait()
        local on = ChatSettings.EnablePings
        PingSwitch.BackgroundColor3 = on and Library.Scheme.AccentColor or Library.Scheme.MainColor
        PingBall.AnchorPoint = Vector2.new(on and 1 or 0, 0)
        PingBall.Position = UDim2.fromScale(on and 1 or 0, 0)
    end)

-- Enable Invites toggle row
    local InviteToggleRow = New("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = 2, -- <--- Shifted order
        Size = UDim2.new(1, 0, 0, 18),
        ZIndex = 601,
        Parent = SettingsPanel,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -42, 1, 0),
        Text = "Enable Invites",
        TextColor3 = "FontColor",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 602,
        Parent = InviteToggleRow,
    })

    local InviteSwitch = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = "MainColor",
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(32, 18),
        ZIndex = 602,
        Parent = InviteToggleRow,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = InviteSwitch })
    New("UIStroke", { Color = "OutlineColor", Parent = InviteSwitch })
    Library:RemoveFromRegistry(InviteSwitch)
    New("UIPadding", {
        PaddingBottom = UDim.new(0, 2),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 2),
        PaddingTop = UDim.new(0, 2),
        Parent = InviteSwitch,
    })

    local InviteBall = New("Frame", {
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = "FontColor",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        SizeConstraint = Enum.SizeConstraint.RelativeYY,
        ZIndex = 603,
        Parent = InviteSwitch,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = InviteBall })

    local InviteSwitchBtn = New("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        ZIndex = 604,
        Parent = InviteSwitch,
    })

    local function UpdateInviteSwitch()
        local on = ChatSettings.EnableInvites
        TweenService:Create(InviteSwitch, Library.TweenInfo, {
            BackgroundColor3 = on and Library.Scheme.AccentColor or Library.Scheme.MainColor,
        }):Play()
        TweenService:Create(InviteBall, Library.TweenInfo, {
            AnchorPoint = Vector2.new(on and 1 or 0, 0),
            Position = UDim2.fromScale(on and 1 or 0, 0),
        }):Play()
    end

InviteSwitchBtn.MouseButton1Click:Connect(function()
    ChatSettings.EnableInvites = not ChatSettings.EnableInvites
    UpdateInviteSwitch()
    SaveChatSettings()

    -- NEW: When turned off, nuke all pending invites server-side immediately
    if not ChatSettings.EnableInvites and HttpRequest then
        task.spawn(function()
            pcall(function()
                HttpRequest({
                    Url = "http://167.99.144.89:8081/chatbox/invites/deleteall",
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                    },
                    Body = game:GetService("HttpService"):JSONEncode({
                        Username = game:GetService("Players").LocalPlayer.Name
                    })
                })
            end)
        end)
    end
end)
    task.spawn(function()
        task.wait()
        local on = ChatSettings.EnableInvites
        InviteSwitch.BackgroundColor3 = on and Library.Scheme.AccentColor or Library.Scheme.MainColor
        InviteBall.AnchorPoint = Vector2.new(on and 1 or 0, 0)
        InviteBall.Position = UDim2.fromScale(on and 1 or 0, 0)
    end)

    -- Chat Text Size slider row
    local SliderRow = New("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Size = UDim2.new(1, 0, 0, 40),
        ZIndex = 601,
        Parent = SettingsPanel,
    })

    New("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14),
        Text = "Chat Text Size",
        TextColor3 = "FontColor",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 602,
        Parent = SliderRow,
    })

    local TextSizeBar = New("TextButton", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = "MainColor",
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 15),
        Text = "",
        ZIndex = 602,
        Parent = SliderRow,
    })
    New("UIStroke", { Color = "OutlineColor", Parent = TextSizeBar })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = TextSizeBar })

    local TextSizeFill = New("Frame", {
        BackgroundColor3 = "AccentColor",
        Size = UDim2.fromScale(0.5, 1),
        ZIndex = 603,
        Parent = TextSizeBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = TextSizeFill })

    local TextSizeDisplay = New("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "14",
        TextSize = 12,
        ZIndex = 604,
        Parent = TextSizeBar,
    })
    New("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
        Color = "DarkColor",
        LineJoinMode = Enum.LineJoinMode.Miter,
        Parent = TextSizeDisplay,
    })

    local SliderMin, SliderMax = 10, 22

    local MessageBodyLabels = {}

    local function UpdateTextSizeSlider()
        local scale = (ChatSettings.ChatTextSize - SliderMin) / (SliderMax - SliderMin)
        TextSizeFill.Size = UDim2.fromScale(scale, 1)
        TextSizeDisplay.Text = tostring(ChatSettings.ChatTextSize)
        for i = #MessageBodyLabels, 1, -1 do
            local lbl = MessageBodyLabels[i]
            if not lbl or not lbl.Parent then
                table.remove(MessageBodyLabels, i)
            else
                lbl.TextSize = ChatSettings.ChatTextSize
            end
        end
    end

    local SliderMouse = LocalPlayer:GetMouse()
    TextSizeBar.InputBegan:Connect(function(Input)
        if not IsClickInput(Input) then return end
        while IsDragInput(Input) do
            local loc = math.clamp(SliderMouse.X, TextSizeBar.AbsolutePosition.X, TextSizeBar.AbsolutePosition.X + TextSizeBar.AbsoluteSize.X)
            local scale = (loc - TextSizeBar.AbsolutePosition.X) / TextSizeBar.AbsoluteSize.X
            local newSize = math.floor(SliderMin + (SliderMax - SliderMin) * scale + 0.5)
            if newSize ~= ChatSettings.ChatTextSize then
                ChatSettings.ChatTextSize = newSize
                UpdateTextSizeSlider()
                SaveChatSettings()
            end
            RunService.RenderStepped:Wait()
        end
    end)

    UpdateTextSizeSlider()

    -- Gear toggle
    local SettingsOpen = false
    GearBtn.MouseButton1Click:Connect(function()
        SettingsOpen = not SettingsOpen
        SettingsPanel.Visible = SettingsOpen
    end)

    -- Close settings if clicking outside
    Library:GiveSignal(UserInputService.InputBegan:Connect(function(Input)
        if not IsClickInput(Input) or not SettingsOpen then return end
        local mousePos = Input.Position
        if not Library:MouseIsOverFrame(SettingsPanel, mousePos) and not Library:MouseIsOverFrame(GearBtn, mousePos) then
            SettingsOpen = false
            SettingsPanel.Visible = false
        end
    end))

    local ChatCloseBtn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = "MainColor",
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        Text = "X",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        ZIndex = 510,
        Parent = ChatTitleBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = ChatCloseBtn })
    New("UIStroke", { Color = "OutlineColor", Parent = ChatCloseBtn })

    New("Frame", {
        BackgroundColor3 = "OutlineColor",
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = 501,
        Parent = ChatGui,
    })

    local ChatScroll = New("ScrollingFrame", {
        AnchorPoint = Vector2.new(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        CanvasSize = UDim2.fromScale(0, 0),
        Position = UDim2.fromOffset(0, 37),
        ScrollBarImageColor3 = "OutlineColor",
        ScrollBarThickness = 3,
        Size = UDim2.new(1, 0, 1, -103),
        ZIndex = 501,
        Parent = ChatGui,
    })
    local ChatList = New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = ChatScroll,
    })
    New("UIPadding", {
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, 6),
        Parent = ChatScroll,
    })

    local TypingIndicatorFrame = New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 1, -47),
        Size = UDim2.new(1, -16, 0, 18),
        Visible = false,
        ZIndex = 505,
        Parent = ChatGui,
    })

    local TypingDotsHolder = New("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(22, 18),
        ZIndex = 506,
        Parent = TypingIndicatorFrame,
    })
    local TypingDot1 = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Color3.fromRGB(180, 182, 188),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.fromOffset(4, 4),
        ZIndex = 506,
        Parent = TypingDotsHolder,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = TypingDot1 })

    local TypingDot2 = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Color3.fromRGB(180, 182, 188),
        Position = UDim2.new(0, 9, 0.5, 0),
        Size = UDim2.fromOffset(4, 4),
        ZIndex = 506,
        Parent = TypingDotsHolder,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = TypingDot2 })

    local TypingDot3 = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Color3.fromRGB(180, 182, 188),
        Position = UDim2.new(0, 16, 0.5, 0),
        Size = UDim2.fromOffset(4, 4),
        ZIndex = 506,
        Parent = TypingDotsHolder,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = TypingDot3 })

    local TypingLabel = New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 26, 0, 0),
        Size = UDim2.new(1, -26, 1, 0),
        Text = "",
        TextColor3 = Color3.fromRGB(180, 182, 188),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 506,
        Parent = TypingIndicatorFrame,
    })

    task.spawn(function()
        local t = 0
        while true do
            t = t + 0.15
            if TypingIndicatorFrame.Visible then
                TypingDot1.Position = UDim2.new(0, 2, 0.5, math.sin(t * 5) * 2)
                TypingDot2.Position = UDim2.new(0, 9, 0.5, math.sin(t * 5 - 0.7) * 2)
                TypingDot3.Position = UDim2.new(0, 16, 0.5, math.sin(t * 5 - 1.4) * 2)
            end
            task.wait(0.03)
        end
    end)

    New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = "OutlineColor",
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -46),
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = 501,
        Parent = ChatGui,
    })

    local InputBar = New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = "MainColor",
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 46),
        ZIndex = 501,
        Parent = ChatGui,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius), Parent = InputBar })
    New("Frame", {
        BackgroundColor3 = "MainColor",
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, Library.CornerRadius),
        ZIndex = 501,
        Parent = InputBar,
    })

    local ReplyBanner = New("Frame", {
        BackgroundColor3 = Color3.fromRGB(35, 37, 42),
        Position = UDim2.new(0, 8, 0, 4),
        Size = UDim2.new(1, -38, 0, 22),
        Visible = false,
        ZIndex = 502,
        Parent = InputBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = ReplyBanner })
    New("UIStroke", { Color = Color3.fromRGB(88, 101, 242), Parent = ReplyBanner })

    local ReplyBannerText = New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, 0),
        Size = UDim2.new(1, -32, 1, 0),
        Text = "Replying to user",
        TextColor3 = Color3.fromRGB(220, 220, 220),
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 503,
        Parent = ReplyBanner,
    })
    local ReplyCancelBtn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Color3.fromRGB(50, 52, 58),
        Position = UDim2.new(1, -4, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        Text = "✕",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 10,
        ZIndex = 504,
        Parent = ReplyBanner,
    })
    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ReplyCancelBtn })

    local ChatInput = New("TextBox", {
        AnchorPoint = Vector2.new(0, 0),
        BackgroundColor3 = "BackgroundColor",
        ClearTextOnFocus = false,
        PlaceholderText = "Send a message...",
        PlaceholderColor3 = "FontColor",
        Position = UDim2.new(0, 8, 0, 8),
        Size = UDim2.new(1, -74, 0, 28),
        Text = "",
        TextColor3 = "FontColor",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 502,
        Parent = InputBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = ChatInput })
    New("UIStroke", { Color = "OutlineColor", Parent = ChatInput })
    New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = ChatInput })

    local SendBtn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = "AccentColor",
        Position = UDim2.new(1, -30, 0, 8),
        Size = UDim2.fromOffset(40, 28),
        Text = "Send",
        TextColor3 = "FontColor",
        TextSize = 13,
        ZIndex = 502,
        Parent = InputBar,
    })
    New("UICorner", { CornerRadius = UDim.new(0, Library.CornerRadius / 2), Parent = SendBtn })

    -- Discord-style Mention Auto-complete Menu
    local MentionMenu = New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = Color3.fromRGB(43, 45, 49),
        Position = UDim2.new(0, 8, 1, -50),
        Size = UDim2.new(1, -16, 0, 150),
        Visible = false,
        ZIndex = 550,
        Parent = ChatGui,
    })
    New("UICorner", { CornerRadius = UDim.new(0, 6), Parent = MentionMenu })
    New("UIStroke", { Color = Color3.fromRGB(30, 31, 34), Thickness = 1, Parent = MentionMenu })

    local MentionMenuHeader = New("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -10, 0, 24),
        Text = "MEMBERS",
        TextColor3 = Color3.fromRGB(150, 150, 150),
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 551,
        Parent = MentionMenu
    })

    local MentionScroll = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 1, -24),
        CanvasSize = UDim2.fromScale(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarImageColor3 = "OutlineColor",
        ScrollBarThickness = 3,
        ZIndex = 551,
        Parent = MentionMenu,
    })
    local MentionListLayout = New("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = MentionScroll,
    })
    New("UIPadding", {
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        Parent = MentionScroll,
    })

    local function PopulateMentionMenu(filterText)
        for _, child in ipairs(MentionScroll:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end

        local matches = {}
        for user in pairs(SeenUsers) do
            local dName = GetDisplayName(user)
            if user:lower():sub(1, #filterText) == filterText:lower() or dName:lower():sub(1, #filterText) == filterText:lower() then
                table.insert(matches, user)
            end
        end

        if #matches == 0 then
            MentionMenu.Visible = false
            return
        end

        table.sort(matches)

        local maxItems = math.min(#matches, 6)
        MentionMenu.Size = UDim2.new(1, -16, 0, 24 + (maxItems * 30) + 4)

        for _, user in ipairs(matches) do
            local btn = New("TextButton", {
                BackgroundColor3 = Color3.fromRGB(43, 45, 49),
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 28),
                Text = "",
                AutoButtonColor = false,
                ZIndex = 552,
                Parent = MentionScroll
            })
            New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = btn })

            local displayNameText = GetDisplayName(user)

            New("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 8, 0, 0),
                Size = UDim2.new(0.5, 0, 1, 0),
                Text = displayNameText,
                TextColor3 = Color3.fromRGB(220, 220, 220),
                TextSize = 13,
                Font = Enum.Font.GothamMedium,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 553,
                Parent = btn
            })

            if displayNameText ~= user then
                New("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0, 0),
                    Size = UDim2.new(0.5, -8, 1, 0),
                    Text = user,
                    TextColor3 = Color3.fromRGB(130, 130, 130),
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    ZIndex = 553,
                    Parent = btn
                })
            end

            btn.MouseEnter:Connect(function()
                btn.BackgroundColor3 = Color3.fromRGB(53, 55, 60)
            end)
            btn.MouseLeave:Connect(function()
                btn.BackgroundColor3 = Color3.fromRGB(43, 45, 49)
            end)

            btn.MouseButton1Click:Connect(function()
                local text = ChatInput.Text
                local replaced = false

                if text:match(".*%s@([%w_]*)$") then
                    local reversed = text:reverse()
                    local atIndex = reversed:find("@")
                    if atIndex then
                        local actualIndex = #text - atIndex + 1
                        text = text:sub(1, actualIndex - 1) .. "@" .. user .. " "
                        replaced = true
                    end
                elseif text:match("^@([%w_]*)$") then
                    text = "@" .. user .. " "
                    replaced = true
                end

                if replaced then
                    ChatInput.Text = text
                else
                    ChatInput.Text = ChatInput.Text .. user .. " "
                end

                MentionMenu.Visible = false
                ChatInput:CaptureFocus()
                ChatInput.CursorPosition = #ChatInput.Text + 1
            end)
        end

        MentionMenu.Visible = true
    end

    local function UpdateMentionState()
        if not ChatInput.TextEditable then
            MentionMenu.Visible = false
            return
        end

        local text = ChatInput.Text
        local mentionMatch = text:match(".*%s@([%w_]*)$") or text:match("^@([%w_]*)$")

        if mentionMatch then
            PopulateMentionMenu(mentionMatch)
        else
            MentionMenu.Visible = false
        end
    end

    local function IsLocallyMuted()
        return tick() < LocalMuteExpiration
    end

    local function UpdateInputLayout()
        local extraOffset = 0
        if ReplyTarget then extraOffset = extraOffset + 26 end

        if extraOffset > 0 then
            InputBar.Size = UDim2.new(1, 0, 0, 46 + extraOffset)
            ChatScroll.Size = UDim2.new(1, 0, 1, -(103 + extraOffset))
            TypingIndicatorFrame.Position = UDim2.new(0, 8, 1, -(47 + extraOffset))
            ChatInput.Position = UDim2.new(0, 8, 0, 8 + extraOffset)
            SendBtn.Position = UDim2.new(1, -30, 0, 8 + extraOffset)
            MentionMenu.Position = UDim2.new(0, 8, 1, -(50 + extraOffset))
        else
            ReplyBanner.Visible = false
            InputBar.Size = UDim2.new(1, 0, 0, 46)
            ChatScroll.Size = UDim2.new(1, 0, 1, -103)
            TypingIndicatorFrame.Position = UDim2.new(0, 8, 1, -47)
            ChatInput.Position = UDim2.new(0, 8, 0, 8)
            SendBtn.Position = UDim2.new(1, -30, 0, 8)
            MentionMenu.Position = UDim2.new(0, 8, 1, -50)
        end

        if ReplyTarget then
            ReplyBanner.Visible = true
            ReplyBanner.Position = UDim2.new(0, 8, 0, 4)
            ChatInput.PlaceholderText = "Message @" .. GetDisplayName(ReplyTarget.Username)
        else
            ReplyBanner.Visible = false
        end

        if IsLocallyMuted() then
            ChatInput.BackgroundColor3 = Color3.fromRGB(40, 42, 46)
            ChatInput.TextColor3 = Color3.fromRGB(120, 122, 128)
            ChatInput.TextEditable = false
            SendBtn.Active = false
            SendBtn.BackgroundColor3 = Color3.fromRGB(60, 62, 68)
            local remTime = math.max(0, LocalMuteExpiration - tick())
            ChatInput.PlaceholderText = "U are muted. Timer: " .. FormatDuration(remTime)
            SendBtn.Text = "Muted"
            MentionMenu.Visible = false
        else
            ChatInput.BackgroundColor3 = Library.Scheme.BackgroundColor or Color3.fromRGB(30, 31, 34)
            ChatInput.TextColor3 = Library.Scheme.FontColor
            ChatInput.TextEditable = true
            SendBtn.Active = true
            SendBtn.BackgroundColor3 = Library.Scheme.AccentColor

            if NicknameTarget then
                ChatInput.PlaceholderText = "Type nickname for " .. GetDisplayName(NicknameTarget) .. " here"
                SendBtn.Text = "Set"
            elseif MuteDurationTarget then
                ChatInput.PlaceholderText = "Type time. Example : 1d 1h 1m 1s"
                SendBtn.Text = "Mute"
            else
                SendBtn.Text = "Send"
                if not ReplyTarget then
                    ChatInput.PlaceholderText = "Send a message..."
                end
            end
        end
    end

    task.spawn(function()
        while true do
            if IsLocallyMuted() then
                UpdateInputLayout()
            end
            task.wait(1)
        end
    end)

    ReplyCancelBtn.MouseButton1Click:Connect(function()
        ReplyTarget = nil
        UpdateInputLayout()
        for _, rData in pairs(ActiveMessageRows) do
            if rData.SetHighlight then rData.SetHighlight(false) end
        end
    end)

    local ActiveContextMenu = nil
    local function CloseContextMenu()
        if ActiveContextMenu then
            ActiveContextMenu:Destroy()
            ActiveContextMenu = nil
        end
    end

    local function OpenUserContextMenu(targetUser, targetUserId)
        CloseContextMenu()

        local mousePos = game:GetService("UserInputService"):GetMouseLocation()
        local isTargetMuted = MutedUsernamesMap[targetUser:lower()] or (targetUserId and MutedUsernamesMap[tostring(targetUserId):lower()])
        local isAdminUser = IsAdmin(LocalPlayer.UserId, LocalPlayer.Name)

        local optionCount = isAdminUser and 5 or 4
        local menuHeight = (optionCount * 28) + ((optionCount - 1) * 2) + 12

        ActiveContextMenu = New("Frame", {
            BackgroundColor3 = Color3.fromRGB(18, 19, 22),
            Position = UDim2.fromOffset(mousePos.X, mousePos.Y - 36),
            Size = UDim2.fromOffset(160, menuHeight),
            ZIndex = 800,
            Parent = ScreenGui,
        })
        New("UICorner", { CornerRadius = UDim.new(0, 6), Parent = ActiveContextMenu })
        New("UIStroke", { Color = Color3.fromRGB(45, 47, 52), Thickness = 1, Parent = ActiveContextMenu })

        New("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = ActiveContextMenu,
        })
        New("UIPadding", {
            PaddingTop = UDim.new(0, 6),
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 6),
            PaddingRight = UDim.new(0, 6),
            Parent = ActiveContextMenu,
        })

        local function CreateMenuOption(text, textColor, callback)
            local btn = New("TextButton", {
                BackgroundColor3 = Color3.fromRGB(18, 19, 22),
                BackgroundTransparency = 0,
                Size = UDim2.new(1, 0, 0, 28),
                AutoButtonColor = false,
                Text = text,
                TextColor3 = textColor or Color3.fromRGB(185, 187, 190),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 801,
                Parent = ActiveContextMenu,
            })
            New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = btn })
            New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = btn })

            btn.MouseEnter:Connect(function()
                btn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            end)
            btn.MouseLeave:Connect(function()
                btn.BackgroundColor3 = Color3.fromRGB(18, 19, 22)
                btn.TextColor3 = textColor or Color3.fromRGB(185, 187, 190)
            end)

            btn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch or
                   input.UserInputType == Enum.UserInputType.MouseButton1 then
                    CloseContextMenu()
                    task.spawn(callback)
                end
            end)

            btn.MouseButton1Down:Connect(function()
                CloseContextMenu()
                task.spawn(callback)
            end)
        end

        CreateMenuOption("Copy Username", nil, function()
            if setclipboard then
                setclipboard(targetUser)
                Library:Notify({ Title = "Clipboard", Description = "Copied Username: " .. targetUser, Time = 2 })
            end
        end)

        CreateMenuOption("Copy UserID", nil, function()
            if setclipboard then
                setclipboard(tostring(targetUserId or 0))
                Library:Notify({ Title = "Clipboard", Description = "Copied UserID: " .. tostring(targetUserId or 0), Time = 2 })
            end
        end)

        CreateMenuOption("Set Nickname", nil, function()
            NicknameTarget = targetUser
            MuteDurationTarget = nil
            ReplyTarget = nil
            ChatInput.Text = ""
            UpdateInputLayout()
            ChatInput:CaptureFocus()
        end)

        CreateMenuOption("InviteUser", nil, function()
            if not HttpRequest then return end

            local Players = game:GetService("Players")

            -- Check server capacity before sending the invite
            local currentPlayers = Players.NumPlayers
            local maxPlayers = Players.MaxPlayers

            if currentPlayers >= maxPlayers then
                -- Server is full, show a notification and stop execution
                pcall(function()
                    Library:Notify({
                        Title = "Invite Failed",
                        Description = "Reason: Server Full try again.",
                        Time = 3
                    })
                end)
                return
            end

            local HttpService = game:GetService("HttpService")
            local localPlayer = Players.LocalPlayer

            local payload = {
                invitedUsername = targetUser,       -- person you clicked InviteUser on
                username = LocalPlayer.Name,        -- your username
                placeid = tostring(game.PlaceId),   -- current PlaceId
                jobid = game.JobId,                 -- current JobId
                players = #Players:GetPlayers()     -- player count
            }

            task.spawn(function()
                pcall(function()
                    HttpRequest({
                        Url = "http://167.99.144.89:8081/chatbox",
                        Method = "POST",
                        Headers = {
                            ["Content-Type"] = "application/json",
                            ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                        },
                        Body = HttpService:JSONEncode(payload)
                    })
                end)
            end)
        end)

        if isAdminUser then
            if isTargetMuted then
                CreateMenuOption("Unmute User", Color3.fromRGB(255, 60, 60), function()
                    local commandText = ",unmute " .. targetUser
                    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    local resolvedUserId = targetUserId
                    if not resolvedUserId then
                        local success, fetchedId = pcall(function()
                            return game:GetService("Players"):GetUserIdFromNameAsync(targetUser)
                        end)
                        resolvedUserId = success and fetchedId or 0
                    end

                    MutedUsernamesMap[targetUser:lower()] = nil
                    if resolvedUserId then MutedUsernamesMap[tostring(resolvedUserId):lower()] = nil end
                    for _, rowData in pairs(ActiveMessageRows) do
                        if rowData.RefreshName then rowData.RefreshName() end
                    end

                    local payload = {
                        Username = LocalPlayer.Name,
                        UserId = tostring(LocalPlayer.UserId),
                        Roles = {"user"},
                        Message = commandText,
                        MessageId = "cmd_" .. math.random(100000, 999999),
                        Time = timestamp,
                        MuteUser = targetUser,
                        MuteDuration = "unmute",
                        MuteUserId = tostring(resolvedUserId)
                    }

                    if HttpRequest then
                        pcall(function()
                            HttpRequest({
                                Url = "http://167.99.144.89:8081/chatbox",
                                Method = "POST",
                                Headers = {
                                    ["Content-Type"] = "application/json",
                                    ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                                },
                                Body = game:GetService("HttpService"):JSONEncode(payload),
                            })
                        end)
                    end
                    Window.ChatAddMessage("System", "Successfully executed: " .. commandText, true)
                end)
            else
                CreateMenuOption("Mute User", Color3.fromRGB(255, 60, 60), function()
                    MuteDurationTarget = targetUser
                    NicknameTarget = nil
                    ReplyTarget = nil
                    ChatInput.Text = ""
                    UpdateInputLayout()
                    ChatInput:CaptureFocus()
                end)
            end
        end
    end

game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 
        or input.UserInputType == Enum.UserInputType.MouseButton2 then
        if ActiveContextMenu then
            local mousePos = game:GetService("UserInputService"):GetMouseLocation()
            local absPos = ActiveContextMenu.AbsolutePosition
            local absSize = ActiveContextMenu.AbsoluteSize
            if not (mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y) then
                CloseContextMenu()
            end
        end
    end
    if input.UserInputType == Enum.UserInputType.Touch then
        if ActiveContextMenu then
            local mousePos = game:GetService("UserInputService"):GetMouseLocation()
            local absPos = ActiveContextMenu.AbsolutePosition
            local absSize = ActiveContextMenu.AbsoluteSize
            if not (mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y) then
                CloseContextMenu()
            end
        end
    end
end)

    local ChatResizeBtn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(1, 1),
        Size = UDim2.fromOffset(24, 24),
        Text = "",
        ZIndex = ChatGui.ZIndex + 1,
        Parent = ChatGui,
    })
    if ResizeIcon then
        New("ImageLabel", {
            BackgroundTransparency = 1,
            Image = ResizeIcon.Url,
            ImageColor3 = "OutlineColor",
            ImageRectOffset = ResizeIcon.ImageRectOffset,
            ImageRectSize = ResizeIcon.ImageRectSize,
            Size = UDim2.fromScale(1, 1),
            ZIndex = ChatGui.ZIndex + 2,
            Parent = ChatResizeBtn,
        })
    end
    Library:MakeResizable(ChatGui, ChatResizeBtn, function()
        UpdateInputLayout()
    end)

    Library:MakeDraggable(ChatGui, ChatTitleBar, true)

    local ProcessedSignatures = {}
    local ProcessedPings = {}

    local function GetUniqueMessageId()
        return tostring(math.random(100000, 999999))
    end

    local function SendToEndpoint(username, message, messageId, replyData, reactions, targetPingUser, deleteMessageId, isTypingState)
        if not HttpRequest then return end
        local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        local data = {
            Username = username,
            UserId = tostring(LocalPlayer.UserId),
            Roles = {"user"},
            Message = message,
            MessageId = messageId,
            Time = timestamp,
            Reactions = reactions or {},
            PingUser = targetPingUser,
            DeleteId = deleteMessageId,
            IsTyping = isTypingState
        }
        if replyData then
            data.ReplyToId = replyData.Id
            data.ReplyToUser = replyData.Username
            data.ReplyToText = replyData.Text
        end

        local body = game:GetService("HttpService"):JSONEncode(data)
        task.spawn(function()
            pcall(function()
                HttpRequest({
                    Url = "http://167.99.144.89:8081/chatbox",
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                    },
                    Body = body,
                })
            end)
        end)
    end

    local LastTypingSent = 0
    local WasTyping = false
    ChatInput:GetPropertyChangedSignal("Text"):Connect(function()
        if IsLocallyMuted() then return end

        local hasText = #ChatInput.Text > 0
        if hasText ~= WasTyping then
            WasTyping = hasText
            LastTypingSent = tick()
            SendToEndpoint(LocalPlayer.Name, "", nil, nil, nil, nil, nil, hasText)
        elseif hasText and tick() - LastTypingSent > 3 then
            LastTypingSent = tick()
            SendToEndpoint(LocalPlayer.Name, "", nil, nil, nil, nil, nil, true)
        end

        UpdateMentionState()
    end)

    local LastMessageTime = 0
    local SpamCooldown = 2
local BannedWords = {"sex", "dick", "pussy", "nigger", "nigga", "fanny"}

local function ContainsBannedWord(Msg)
    local Lower = Msg:lower()
    for _, Word in ipairs(BannedWords) do
        if Lower:find(Word:lower(), 1, true) then return true end
    end
    return false
end

    local ActiveReactorMenus = {}

    game:GetService("UserInputService").InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            for menu, isOutsideFunc in pairs(ActiveReactorMenus) do
                if isOutsideFunc() then
                    menu:Destroy()
                    ActiveReactorMenus[menu] = nil
                end
            end
        end
    end)

    local MsgIndex = 0
    local function AddMessage(sender, text, isSystem, senderUserId, messageId, replyData, reactions, customSignature)
        local msgIdStr = messageId or tostring(math.random(1000,9999))

        if ActiveMessageRows[msgIdStr] then
            if ActiveMessageRows[msgIdStr].UpdateReactions then
                ActiveMessageRows[msgIdStr].UpdateReactions(reactions)
            end
            if ActiveMessageRows[msgIdStr].RefreshName then
                ActiveMessageRows[msgIdStr].RefreshName()
            end
            return
        end

        local signature = customSignature or (tostring(sender) .. "|" .. tostring(text) .. "|" .. msgIdStr)
        if ProcessedSignatures[signature] then return end
        ProcessedSignatures[signature] = true

        MsgIndex = MsgIndex + 1

        local Row = New("Frame", {
            BackgroundColor3 = Color3.fromRGB(47, 49, 54),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = MsgIndex,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 502,
            Parent = ChatScroll,
        })
        New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = Row })
        New("UIPadding", { PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), Parent = Row })

        local ActionBar = New("Frame", {
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = Color3.fromRGB(45, 47, 52),
            Position = UDim2.new(1, -4, 0, -6),
            Size = UDim2.fromOffset(84, 24),
            Visible = false,
            ZIndex = 510,
            Parent = Row,
        })
        New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = ActionBar })
        New("UIStroke", { Color = "OutlineColor", Parent = ActionBar })

        local ReplyBtn = New("TextButton", {
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 28, 1, 0),
            Text = "↩",
            TextColor3 = Color3.fromRGB(200, 200, 200),
            TextSize = 13,
            ZIndex = 511,
            Parent = ActionBar,
        })

        local HeartBtn = New("TextButton", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 28, 0, 0),
            Size = UDim2.new(0, 28, 1, 0),
            Text = "❤️",
            TextColor3 = Color3.fromRGB(200, 200, 200),
            TextSize = 11,
            ZIndex = 511,
            Parent = ActionBar,
        })

        local BinBtn = New("TextButton", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 56, 0, 0),
            Size = UDim2.new(0, 28, 1, 0),
            Text = "🗑️",
            TextColor3 = Color3.fromRGB(200, 200, 200),
            TextSize = 11,
            ZIndex = 511,
            Parent = ActionBar,
        })

        local BinProgressGui = New("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 56, 0, 0),
            Size = UDim2.fromOffset(28, 28),
            Visible = false,
            ZIndex = 515,
            Parent = ActionBar,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = BinProgressGui })

        local BinProgressStroke = New("UIStroke", { Color = Color3.fromRGB(255, 60, 60), Thickness = 2.5, Parent = BinProgressGui })
        local BinProgressGradient = New("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.25, 0),
                NumberSequenceKeypoint.new(0.251, 1),
                NumberSequenceKeypoint.new(1, 1)
            }),
            Rotation = 0,
            Parent = BinProgressStroke,
        })

        local currentRowReactions = reactions or {}

        local MessageContentWrapper = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 503,
            Parent = Row,
        })

        local ReplyHighlightBar = New("Frame", {
            BackgroundColor3 = Color3.fromRGB(88, 101, 242),
            BorderSizePixel = 0,
            Position = UDim2.new(0, -6, 0, 0),
            Size = UDim2.new(0, 3, 1, 0),
            Visible = false,
            ZIndex = 506,
            Parent = MessageContentWrapper,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ReplyHighlightBar })

        local function SetRowHighlight(state)
            ReplyHighlightBar.Visible = state
            if state then
                Row.BackgroundColor3 = Color3.fromRGB(53, 56, 63)
                Row.BackgroundTransparency = 0.5
            else
                Row.BackgroundColor3 = Color3.fromRGB(47, 49, 54)
                Row.BackgroundTransparency = 1
            end
        end

        ReplyBtn.MouseButton1Click:Connect(function()
            for _, rData in pairs(ActiveMessageRows) do
                if rData.SetHighlight then rData.SetHighlight(false) end
            end
            SetRowHighlight(true)

            ReplyTarget = { Id = msgIdStr, Username = sender, Text = text }
            UpdateInputLayout()
            ChatInput:CaptureFocus()
        end)

        local activePickerMenu = nil
        HeartBtn.MouseButton1Click:Connect(function()
            if activePickerMenu then
                ActiveReactorMenus[activePickerMenu] = nil
                activePickerMenu:Destroy()
                activePickerMenu = nil
                return
            end

            local menuOpenedTick = tick()
            activePickerMenu = New("Frame", {
                BackgroundColor3 = Color3.fromRGB(35, 37, 42),
                Position = UDim2.new(1, -140, 0, 28),
                Size = UDim2.fromOffset(140, 34),
                ZIndex = 600,
                Parent = ActionBar,
            })
            New("UICorner", { CornerRadius = UDim.new(0, 6), Parent = activePickerMenu })
            New("UIStroke", { Color = Color3.fromRGB(88, 101, 242), Parent = activePickerMenu })
            New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = activePickerMenu })
            New("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = activePickerMenu })

            local availableEmojis = {"👍", "❤️", "😂", "😮", "😢", "🔥"}
            for _, emoji in ipairs(availableEmojis) do
                local emojiBtn = New("TextButton", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromOffset(20, 20),
                    Text = emoji,
                    TextSize = 13,
                    ZIndex = 601,
                    Parent = activePickerMenu,
                })

                emojiBtn.MouseButton1Down:Connect(function()
                    local currentRx = {}
                    for e, list in pairs(currentRowReactions) do
                        currentRx[e] = {}
                        for _, u in ipairs(list) do table.insert(currentRx[e], u) end
                    end

                    if not currentRx[emoji] then currentRx[emoji] = {} end
                    local foundIndex = nil
                    for i, user in ipairs(currentRx[emoji]) do
                        if user == LocalPlayer.Name then foundIndex = i; break end
                    end

                    if foundIndex then
                        table.remove(currentRx[emoji], foundIndex)
                        if #currentRx[emoji] == 0 then
                            currentRx[emoji] = nil
                        end
                    else
                        table.insert(currentRx[emoji], LocalPlayer.Name)
                    end

                    currentRowReactions = currentRx
                    if activePickerMenu then
                        ActiveReactorMenus[activePickerMenu] = nil
                        activePickerMenu:Destroy()
                        activePickerMenu = nil
                    end
                    SendToEndpoint(sender, text, msgIdStr, replyData, currentRx, nil)
                end)
            end

            ActiveReactorMenus[activePickerMenu] = function()
                if tick() - menuOpenedTick < 0.15 then return false end
                if not activePickerMenu or not activePickerMenu.Parent then return true end
                local mousePos = game:GetService("UserInputService"):GetMouseLocation()
                local absPos = activePickerMenu.AbsolutePosition
                local absSize = activePickerMenu.AbsoluteSize
                local heartPos = HeartBtn.AbsolutePosition
                local heartSize = HeartBtn.AbsoluteSize
                return not ((mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X and mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y) or (mousePos.X >= heartPos.X and mousePos.X <= heartPos.X + heartSize.X and mousePos.Y >= heartPos.Y and mousePos.Y <= heartPos.Y + heartSize.Y))
            end
        end)

        local isHoldingDelete = false
        BinBtn.MouseButton1Down:Connect(function()
            isHoldingDelete = true
            BinProgressGui.Visible = true
            BinProgressGradient.Rotation = 0

            local startTime = tick()
            task.spawn(function()
                while isHoldingDelete do
                    local elapsed = tick() - startTime
                    local progress = math.clamp(elapsed / 2.0, 0, 1)
                    BinProgressGradient.Rotation = progress * 360

                    if elapsed >= 2.0 then
                        ActiveMessageRows[msgIdStr] = nil
                        Row:Destroy()
                        SendToEndpoint(sender, text, msgIdStr, replyData, nil, nil, msgIdStr)
                        break
                    end
                    task.wait(0.016)
                end
            end)
        end)

        local function CancelDeleteHold()
            if isHoldingDelete then
                isHoldingDelete = false
                BinProgressGui.Visible = false
            end
        end

        BinBtn.MouseButton1Up:Connect(CancelDeleteHold)
        BinBtn.MouseLeave:Connect(CancelDeleteHold)

        Row.MouseEnter:Connect(function()
            if not isSystem then ActionBar.Visible = true end
        end)
        Row.MouseLeave:Connect(function()
            ActionBar.Visible = false
            CancelDeleteHold()
        end)

            -- Mobile: tap row to show action bar, only hide when tapping a different row
        local actionBarShown = false
        Row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch and not isSystem then
                if not actionBarShown then
                    -- Hide all other action bars first
                    for _, rowData in pairs(ActiveMessageRows) do
                        if rowData.HideActionBar then rowData.HideActionBar() end
                    end
                    actionBarShown = true
                    ActionBar.Visible = true
                end
                -- If already shown, do nothing — let buttons inside handle their own taps
            end
        end)

        local ContentLayout = New("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 503,
            Parent = MessageContentWrapper,
        })
        New("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2), Parent = ContentLayout })

        local ReplyTextLabel = nil
        if replyData and replyData.Username and replyData.Text then
            ReplyTextLabel = New("TextLabel", {
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                Text = "┌ ↩ " .. GetDisplayName(replyData.Username) .. ": " .. replyData.Text,
                TextColor3 = Color3.fromRGB(150, 150, 150),
                TextSize = 12,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 504,
                Parent = ContentLayout,
            })
        end

        local function GetNameColor()
            if isSystem then return Color3.fromRGB(255, 100, 100)
            elseif MutedUsernamesMap[sender:lower()] then return Color3.fromRGB(139, 0, 0)
            elseif sender == LocalPlayer.Name then return Library.Scheme.AccentColor
            else return Color3.fromRGB(255, 90, 90) end
        end

        local function FormatDisplayName()
            local nick = GetDisplayName(sender)
            if not isSystem and IsAdmin(senderUserId, sender) then return nick .. " 👑" end
            return nick
        end

local NameBtn = New("TextButton", {
    AutomaticSize = Enum.AutomaticSize.XY,
    BackgroundTransparency = 1,
    Text = FormatDisplayName(),
    TextColor3 = GetNameColor(),
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 504,
    Parent = ContentLayout,
})

NameBtn.MouseButton2Click:Connect(function()
    if not isSystem then OpenUserContextMenu(sender, senderUserId) end
end)

-- Mobile long press (1 second hold) on both name and full row
local holdThread = nil
local holdStarted = false
local holdStartPos = nil

local function setupLongPress(target)
    target.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            holdStarted = true
            holdStartPos = Vector2.new(input.Position.X, input.Position.Y)
            holdThread = task.delay(1, function()
                if holdStarted then
                    holdStarted = false
                    holdThread = nil
                    if not isSystem then
                        OpenUserContextMenu(sender, senderUserId)
                    end
                end
            end)
        end
    end)

    target.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            holdStarted = false
            holdThread = nil
        end
    end)

    target.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch and holdStartPos then
            local dx = math.abs(input.Position.X - holdStartPos.X)
            local dy = math.abs(input.Position.Y - holdStartPos.Y)
            if dx > 10 or dy > 10 then
                holdStarted = false
                if holdThread then
                    task.cancel(holdThread)
                    holdThread = nil
                end
            end
        end
    end)
end

setupLongPress(NameBtn)
setupLongPress(Row)

        local MsgBodyLabel = New("TextLabel", {
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            Text = text,
            TextColor3 = isSystem and Color3.fromRGB(255, 150, 150) or Library.Scheme.FontColor,
            TextSize = ChatSettings.ChatTextSize,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 504,
            Parent = ContentLayout,
        })
        table.insert(MessageBodyLabels, MsgBodyLabel)

        local reactionContainer = New("Frame", {
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            ZIndex = 504,
            Parent = ContentLayout,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4),
            Parent = reactionContainer,
        })

        local function RenderReactions(rxData)
            for _, child in ipairs(reactionContainer:GetChildren()) do
                if child:IsA("GuiObject") then child:Destroy() end
            end

            if not rxData then return end
            for emojiStr, userList in pairs(rxData) do
                if type(userList) == "table" and #userList > 0 then
                    local pill = New("TextButton", {
                        BackgroundColor3 = Color3.fromRGB(50, 52, 58),
                        AutoButtonColor = false,
                        Size = UDim2.fromOffset(36, 20),
                        Text = emojiStr .. " " .. #userList,
                        TextColor3 = Color3.fromRGB(200, 200, 200),
                        TextSize = 11,
                        ZIndex = 505,
                        Parent = reactionContainer,
                    })
                    New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = pill })
                    New("UIStroke", { Color = Color3.fromRGB(70, 72, 78), Parent = pill })

                    pill.MouseButton1Down:Connect(function()
                        local currentRx = {}
                        for e, list in pairs(currentRowReactions) do
                            currentRx[e] = {}
                            for _, u in ipairs(list) do table.insert(currentRx[e], u) end
                        end

                        if not currentRx[emojiStr] then currentRx[emojiStr] = {} end
                        local foundIndex = nil
                        for i, user in ipairs(currentRx[emojiStr]) do
                            if user == LocalPlayer.Name then foundIndex = i; break end
                        end

                        if foundIndex then
                            table.remove(currentRx[emojiStr], foundIndex)
                            if #currentRx[emojiStr] == 0 then currentRx[emojiStr] = nil end
                        else
                            table.insert(currentRx[emojiStr], LocalPlayer.Name)
                        end

                        currentRowReactions = currentRx
                        RenderReactions(currentRx)
                        SendToEndpoint(sender, text, msgIdStr, replyData, currentRx, nil)
                    end)
                end
            end
        end

        RenderReactions(currentRowReactions)

        ActiveMessageRows[msgIdStr] = {
            SetHighlight = SetRowHighlight,
            HideActionBar = function()
                actionBarShown = false
                ActionBar.Visible = false
            end,
            UpdateReactions = function(newRx)
                currentRowReactions = newRx or {}
                RenderReactions(currentRowReactions)
            end,
            RefreshName = function()
                NameBtn.Text = FormatDisplayName()
                NameBtn.TextColor3 = GetNameColor()
            end
        }

        task.defer(function()
            ChatScroll.CanvasPosition = Vector2.new(0, ChatList.AbsoluteContentSize.Y)
        end)
        return Row
    end

    local function SendMessage()
        if IsLocallyMuted() then return end

        if NicknameTarget then
            local newNick = ChatInput.Text:gsub("^%s*(.-)%s*$", "%1")
            if newNick ~= "" then CustomNicknames[NicknameTarget] = newNick
            else CustomNicknames[NicknameTarget] = nil end
            SaveNicknames()

            for _, rowData in pairs(ActiveMessageRows) do
                if rowData.RefreshName then rowData.RefreshName() end
            end

            NicknameTarget = nil
            ChatInput.Text = ""
            UpdateInputLayout()
            return
        end

        if MuteDurationTarget then
            local duration = ChatInput.Text:gsub("^%s*(.-)%s*$", "%1")
            if duration == "" then duration = "1h" end

            local commandText = ",mute " .. MuteDurationTarget .. " " .. duration
            if IsAdmin(LocalPlayer.UserId, LocalPlayer.Name) then
                local success, targetUserId = pcall(function() return game:GetService("Players"):GetUserIdFromNameAsync(MuteDurationTarget) end)
                local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                local payload = {
                    Username = LocalPlayer.Name,
                    UserId = tostring(LocalPlayer.UserId),
                    Roles = {"user"},
                    Message = commandText,
                    Time = timestamp,
                    MuteUser = MuteDurationTarget,
                    MuteDuration = duration,
                    MuteUserId = tostring(success and targetUserId or 0)
                }
                if HttpRequest then
                    task.spawn(function()
                        pcall(function()
                            HttpRequest({
                                Url = "http://167.99.144.89:8081/chatbox",
                                Method = "POST",
                                Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "") },
                                Body = game:GetService("HttpService"):JSONEncode(payload),
                            })
                        end)
                    end)
                end
                AddMessage("System", "Executed command: " .. commandText, true)
            end

            MuteDurationTarget = nil
            ChatInput.Text = ""
            UpdateInputLayout()
            return
        end

        local Msg = ChatInput.Text
        if not Msg or Msg:gsub("%s", "") == "" then return end

        if Msg:sub(1, 5) == ",mute" or Msg:sub(1, 7) == ",unmute" then
            if IsAdmin(LocalPlayer.UserId, LocalPlayer.Name) then
                local args = {}
                for word in Msg:gmatch("%S+") do table.insert(args, word) end
                local targetUsername = args[2]
                if targetUsername then
                    local success, targetUserId = pcall(function() return game:GetService("Players"):GetUserIdFromNameAsync(targetUsername) end)
                    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    local payload = {
                        Username = LocalPlayer.Name,
                        UserId = tostring(LocalPlayer.UserId),
                        Roles = {"user"},
                        Message = Msg,
                        Time = timestamp,
                        MuteUser = targetUsername,
                        MuteDuration = Msg:sub(1, 5) == ",mute" and (args[3] or "1h") or "unmute",
                        MuteUserId = tostring(success and targetUserId or 0)
                    }
                    if HttpRequest then
                        task.spawn(function()
                            pcall(function()
                                HttpRequest({
                                    Url = "http://167.99.144.89:8081/chatbox",
                                    Method = "POST",
                                    Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "") },
                                    Body = game:GetService("HttpService"):JSONEncode(payload),
                                })
                            end)
                        end)
                    end
                    AddMessage("System", "Executed command: " .. Msg, true)
                end
                ChatInput.Text = ""
                return
            end
        end

        if #Msg > 100 then AddMessage("System", "Message too long.", true); return end
if tick() - LastMessageTime < SpamCooldown then AddMessage("System", "Slow down.", true); return end
if ContainsBannedWord(Msg) then AddMessage("System", "Your message contains a blocked word.", true); return end

        LastMessageTime = tick()
        local CurrentMsg = Msg
        ChatInput.Text = ""
        MentionMenu.Visible = false

        local UniqueId = GetUniqueMessageId()
        local currentReply = ReplyTarget
        ReplyTarget = nil
        UpdateInputLayout()

        for _, rData in pairs(ActiveMessageRows) do
            if rData.SetHighlight then rData.SetHighlight(false) end
        end

        -- Parse out any @mentions to automatically trigger server pings
        local targetPingUser = nil
        for word in CurrentMsg:gmatch("%S+") do
            if word:sub(1, 1) == "@" then
                local possibleName = word:sub(2)
                if possibleName ~= "" then
                    targetPingUser = possibleName
                    break
                end
            end
        end

        AddMessage(LocalPlayer.Name, CurrentMsg, false, LocalPlayer.UserId, UniqueId, currentReply, nil)
        SendToEndpoint(LocalPlayer.Name, CurrentMsg, UniqueId, currentReply, nil, targetPingUser, nil, false)
    end

local function FetchMessages()
        pcall(function()
            if HttpRequest then
                local Result = HttpRequest({
                    Url = "http://167.99.144.89:8081/chatbox",
                    Method = "GET",
                    Headers = { ["Content-Type"] = "application/json" },
                })
                if Result and Result.StatusCode == 200 and Result.Body then
                    local Success, Decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(Result.Body) end)
                    if Success and type(Decoded) == "table" then

if Decoded.Invites then
    if not ChatSettings.EnableInvites then
        -- On every poll while invites are off, delete any that arrived
        for _, inv in ipairs(Decoded.Invites) do
            if inv.InvitedUsername and inv.InvitedUsername:lower() == LocalPlayer.Name:lower() then
                local invIdStr = tostring(inv.Id)
                if not DeniedInviteIds[invIdStr] then
                    DeniedInviteIds[invIdStr] = true
                    if HttpRequest then
                        task.spawn(function()
                            pcall(function()
                                HttpRequest({
                                    Url = "http://167.99.144.89:8081/chatbox/invites/deleteall",
                                    Method = "POST",
                                    Headers = {
                                        ["Content-Type"] = "application/json",
                                        ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                                    },
                                    Body = game:GetService("HttpService"):JSONEncode({
                                        Username = LocalPlayer.Name
                                    })
                                })
                            end)
                        end)
                    end
                end
            end
        end
        -- Still call RenderInvites so UI stays cleared
        RenderInvites(Decoded.Invites)
    else
        RenderInvites(Decoded.Invites)
    end
end

                        -- FIX: Rebuild SeenUsers strictly from VPS KnownUsers data. No local server player auto-discovery.
                        local KnownUsersList = Decoded.KnownUsers or {}
                        SeenUsers = {}
                        if game:GetService("Players").LocalPlayer then
                            RegisterSeenUser(game:GetService("Players").LocalPlayer.Name)
                        end
                        for _, kUser in ipairs(KnownUsersList) do
                            RegisterSeenUser(kUser)
                        end

                        local MutedUsersList = Decoded.MutedUsers or {}
                        MutedUsernamesMap = {}
                        local wasPreviouslyMuted = IsLocallyMuted()
                        local foundLocalMute = false

                        for _, muteObj in ipairs(MutedUsersList) do
                            if muteObj.Target then MutedUsernamesMap[tostring(muteObj.Target):lower()] = true end
                            if muteObj.TargetUserId then MutedUsernamesMap[tostring(muteObj.TargetUserId):lower()] = true end

                            local isTargetMatch = (muteObj.Target and muteObj.Target:lower() == LocalPlayer.Name:lower()) or
                                                  (muteObj.TargetUserId and tostring(muteObj.TargetUserId) == tostring(LocalPlayer.UserId))

                            if isTargetMatch then
                                foundLocalMute = true
                                local durationSec = muteObj.RemainingSeconds or 3600
                                if not LocalMuteExpiration or math.abs((LocalMuteExpiration - tick()) - durationSec) > 5 then
                                    LocalMuteExpiration = tick() + durationSec
                                end
                            end
                        end

                        if not foundLocalMute then
                            LocalMuteExpiration = 0
                        end

                        if wasPreviouslyMuted ~= IsLocallyMuted() then
                            UpdateInputLayout()
                        end

                        -- Handle Pings polling and processing
                        local pingsList = Decoded.Pings or {}
                        local localNameLower = game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer.Name:lower() or ""
                        local acknowledgedPingIds = {}

                        for _, pingObj in ipairs(pingsList) do
                            if pingObj.Id and not ProcessedPings[pingObj.Id] then
                                local targetUser = pingObj.TargetUser or ""
                                if targetUser:lower() == localNameLower then
                                    ProcessedPings[pingObj.Id] = true
                                    table.insert(acknowledgedPingIds, pingObj.Id)

                                    -- Fire notification with the requested sound ID
                                    if ChatSettings.EnablePings then
                                        pcall(function()
                                            Library:Notify({
                                                Title = "Mentioned!",
                                                Description = (pingObj.Sender or "Someone") .. " mentioned you in chat.",
                                                Time = 5,
                                                SoundId = "rbxassetid://18595195017"
                                            })
                                        end)
                                    end
                                end
                            end
                        end

                        -- Acknowledge processed pings back to the VPS endpoint
                        if #acknowledgedPingIds > 0 then
                            task.spawn(function()
                                pcall(function()
                                    HttpRequest({
                                        Url = "http://167.99.144.89:8081/chatbox/pings/acknowledge",
                                        Method = "POST",
                                        Headers = {
                                            ["Content-Type"] = "application/json",
                                            ["Authorization"] = "Bearer " .. (_G.ChatboxSecretKey or "")
                                        },
                                        Body = game:GetService("HttpService"):JSONEncode({
                                            Username = game:GetService("Players").LocalPlayer.Name,
                                            PingIds = acknowledgedPingIds
                                        })
                                    })
                                end)
                            end)
                        end

                        local messageList = Decoded.Messages or Decoded
                        if type(messageList) == "table" then
                            for _, msgData in ipairs(messageList) do
                                if msgData.Username and msgData.Message then
                                    local replyData = msgData.ReplyToId and { Id = msgData.ReplyToId, Username = msgData.ReplyToUser, Text = msgData.ReplyToText } or nil
                                    AddMessage(msgData.Username, msgData.Message, false, msgData.UserId, msgData.MessageId, replyData, msgData.Reactions)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    task.spawn(FetchMessages)
    task.spawn(function()
        while true do
            FetchMessages()
            task.wait(2)
        end
    end)

    SendBtn.MouseButton1Click:Connect(SendMessage)
    ChatInput.FocusLost:Connect(function(Enter)
        if Enter then SendMessage() end
    end)

    ChatCloseBtn.MouseButton1Click:Connect(function()
        ChatGui.Visible = false
        ChatOpen = false
    end)

local ChatIcon = Library:GetIcon("message-circle")

local ChatTabButton = New("TextButton", {
    BackgroundColor3 = "MainColor",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 40),
    Text = "",
    Parent = Tabs,
})
SetupTabDrag(ChatTabButton)

local ChatButtonPadding = New("UIPadding", {
    PaddingBottom = UDim.new(0, IsCompact and 6 or 11),
    PaddingLeft = UDim.new(0, IsCompact and 6 or 12),
    PaddingRight = UDim.new(0, IsCompact and 6 or 12),
    PaddingTop = UDim.new(0, IsCompact and 6 or 11),
    Parent = ChatTabButton,
})

local ChatBtnLabel = New("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(30, 0),
    Size = UDim2.new(1, -30, 1, 0),
    Text = "Chatbox",
    TextSize = 16,
    TextTransparency = 0.5,
    TextXAlignment = Enum.TextXAlignment.Left,
    Visible = not IsCompact,
    Parent = ChatTabButton,
})

local ChatBtnIcon
if ChatIcon then
    ChatBtnIcon = New("ImageLabel", {
        Image = ChatIcon.Url,
        ImageColor3 = ChatIcon.Custom and "WhiteColor" or "AccentColor",
        ImageRectOffset = ChatIcon.ImageRectOffset,
        ImageRectSize = ChatIcon.ImageRectSize,
        ImageTransparency = 0.5,
        Size = UDim2.fromScale(1, 1),
        SizeConstraint = IsCompact and Enum.SizeConstraint.RelativeXY or Enum.SizeConstraint.RelativeYY,
        Parent = ChatTabButton,
    })
end

table.insert(Library.TabButtons, {
    Label = ChatBtnLabel,
    Padding = ChatButtonPadding,
    Icon = ChatBtnIcon,
})

ChatTabButton.MouseEnter:Connect(function()
    if ChatOpen then return end
    TweenService:Create(ChatBtnLabel, Library.TweenInfo, { TextTransparency = 0.25 }):Play()
    if ChatBtnIcon then
        TweenService:Create(ChatBtnIcon, Library.TweenInfo, { ImageTransparency = 0.25 }):Play()
    end
end)
ChatTabButton.MouseLeave:Connect(function()
    if ChatOpen then return end
    TweenService:Create(ChatBtnLabel, Library.TweenInfo, { TextTransparency = 0.5 }):Play()
    if ChatBtnIcon then
        TweenService:Create(ChatBtnIcon, Library.TweenInfo, { ImageTransparency = 0.5 }):Play()
    end
end)

ChatTabButton.MouseButton1Click:Connect(function()
    ChatOpen = not ChatOpen
    ChatGui.Visible = ChatOpen

    if ChatOpen then
        TweenService:Create(ChatTabButton, Library.TweenInfo, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(ChatBtnLabel, Library.TweenInfo, { TextTransparency = 0 }):Play()
        if ChatBtnIcon then
            TweenService:Create(ChatBtnIcon, Library.TweenInfo, { ImageTransparency = 0 }):Play()
        end
    else
        TweenService:Create(ChatTabButton, Library.TweenInfo, { BackgroundTransparency = 1 }):Play()
        TweenService:Create(ChatBtnLabel, Library.TweenInfo, { TextTransparency = 0.5 }):Play()
        if ChatBtnIcon then
            TweenService:Create(ChatBtnIcon, Library.TweenInfo, { ImageTransparency = 0.5 }):Play()
        end
    end
end)
    Window.ChatAddMessage = AddMessage
end
