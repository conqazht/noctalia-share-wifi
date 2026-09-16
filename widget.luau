-- widget.luau
-- Icon & status indicator on Noctalia Bar

local helperPath = noctalia.pluginDir() .. "/helper.sh"

noctalia.setUpdateInterval(3000)

local status = {
  active = false,
  clients = 0,
  maxClients = 0,
}

-- Try loading saved maxClients from config
local configPath = noctalia.pluginDataDir() .. "/config.json"
local function loadMaxClients()
  local raw = noctalia.readFile(configPath)
  if raw then
    local data = noctalia.json.decode(raw)
    if data and data.maxClients then
      local mc = tonumber(data.maxClients) or 2
      if mc < 1 then mc = 2 end
      if mc > 8 then mc = 8 end
      status.maxClients = mc
    else
      status.maxClients = 2
    end
  else
    status.maxClients = 2
  end
end
loadMaxClients()

local function renderWidget()
  local isVertical = barWidget.isVertical()
  local container = if isVertical then ui.column else ui.row
  local children = {
    ui.glyph({
      name = "access-point",
      size = 17,
      color = if status.active then "primary" else "on_surface",
    })
  }

  if status.active then
    local maxLimit = (status.maxClients and status.maxClients > 0) and status.maxClients or 2
    local badgeText = string.format("%d/%d", status.clients, maxLimit)
    table.insert(children, ui.label({
      text = badgeText,
      fontSize = 11,
      fontWeight = "bold",
      color = "primary",
    }))
  end

  barWidget.render(container({ gap = 4, align = "center", justify = "center" }, children))

  if status.active then
    local maxLimit = (status.maxClients and status.maxClients > 0) and status.maxClients or 2
    local clientStr = string.format("%d/%d clients", status.clients, maxLimit)
    barWidget.setTooltip("Share WiFi: Active (" .. clientStr .. ")\nClick: Settings\nRight-click: Turn off")
  else
    barWidget.setTooltip("Share WiFi: Off\nClick: Settings & Start")
  end
end

function update()
  noctalia.runAsync(helperPath .. " status", function(res)
    if res.exitCode == 0 and res.stdout ~= "" then
      local data = noctalia.json.decode(res.stdout)
      if data then
        status.active = (data.active == true)
        status.clients = tonumber(data.clients) or 0
        noctalia.state.set("share_wifi_status", status)
        renderWidget()
      end
    end
  end)
end

function onClick()
  noctalia.togglePanel("conqazht/share-wifi:panel")
end

function onRightClick()
  if status.active then
    status.active = false
    status.clients = 0
    noctalia.state.set("share_wifi_status", status)
    renderWidget()
    noctalia.notify("Share WiFi", "Hotspot stopped")
    noctalia.runAsync(helperPath .. " stop", function()
      update()
    end)
  else
    noctalia.togglePanel("conqazht/share-wifi:panel")
  end
end

-- Watch state updates from panel
noctalia.state.watch("share_wifi_status", function(newStatus)
  if newStatus then
    status.active = (newStatus.active == true)
    status.clients = tonumber(newStatus.clients) or 0
    if newStatus.maxClients ~= nil then
      status.maxClients = tonumber(newStatus.maxClients) or 0
    end
    renderWidget()
  end
end)

renderWidget()
update()
