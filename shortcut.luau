-- shortcut.luau

local function syncStatus()
  local raw = noctalia.state.get("share_wifi_status")
  if raw and raw.active then
    shortcut.setActive(true)
    local sub = noctalia.tr("shortcut.sharing")
    if raw.clients and raw.clients > 0 then
      sub = raw.clients .. " connected"
    end
    shortcut.setSubtitle(sub)
  else
    shortcut.setActive(false)
    shortcut.setSubtitle(noctalia.tr("shortcut.off"))
  end
end

noctalia.state.watch("share_wifi_status", function()
  syncStatus()
end)

function onClick()
  noctalia.togglePanel("conqazht/share-wifi:panel")
end

syncStatus()
