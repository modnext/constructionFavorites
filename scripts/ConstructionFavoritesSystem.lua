--
-- ConstructionFavoritesSystem
--
-- Author: aaw3k
-- Copyright (C) Mod Next, All Rights Reserved.
--

local modSettingsDirectory = g_currentModSettingsDirectory

ConstructionFavoritesSystem = {
  MAX_GROUPS = 9,
}

local ConstructionFavoritesSystem_mt = Class(ConstructionFavoritesSystem)

---Create a new favorites system instance
function ConstructionFavoritesSystem.new()
  local self = setmetatable({}, ConstructionFavoritesSystem_mt)

  self.favorites = {}
  self.groups = {}
  self.itemGroups = {}
  self.activeGroupIndex = 1
  self.isDirty = false
  self.isResolved = false
  self.hasSyncedThisSession = false

  -- load data from xml file
  self:loadFromXMLFile()

  -- ensure default group exists
  if #self.groups == 0 then
    self:addGroup(g_i18n:getText("constructionFavorites_category"), 1)
  end

  return self
end

---Mark favorites data as changed and pending save
function ConstructionFavoritesSystem:markDirty()
  self.isDirty = true
end

---Convert an identifier to a portable storage key using engine path variables
-- Uses $moddir$, $pdlcdir$ etc. to produce paths independent of install location
-- @param string identifier item identifier (absolute or relative path)
-- @return string|nil storageKey portable path with engine variable prefix
function ConstructionFavoritesSystem.toStorageKey(identifier)
  if identifier == nil then
    return nil
  end

  return NetworkUtil.convertToNetworkFilename(identifier)
end

---Ensure storage keys are resolved to current runtime paths
-- Runs resolution exactly once per session on first access
function ConstructionFavoritesSystem:ensureResolved()
  if self.isResolved then
    return
  end

  self.isResolved = true
  self:resolveStorageKeys()
end

---Resolve storage keys to current runtime absolute paths
-- Migrates portable storage keys to current absolute paths via NetworkUtil
function ConstructionFavoritesSystem:resolveStorageKeys()
  local resolvedFavorites = {}
  local resolvedItemGroups = {}

  for key, identifier in pairs(self.favorites) do
    local runtimeKey = nil

    if g_storeManager:getItemByXMLFilename(key) ~= nil then
      runtimeKey = string.lower(key)
    else
      local resolvedPath = NetworkUtil.convertFromNetworkFilename(identifier)

      if resolvedPath ~= nil and g_storeManager:getItemByXMLFilename(resolvedPath) ~= nil then
        runtimeKey = string.lower(resolvedPath)
      end
    end

    if runtimeKey ~= nil then
      local storeItem = g_storeManager:getItemByXMLFilename(runtimeKey)

      resolvedFavorites[runtimeKey] = storeItem ~= nil and storeItem.xmlFilename or identifier

      if resolvedItemGroups[runtimeKey] == nil then
        resolvedItemGroups[runtimeKey] = self.itemGroups[key]
      elseif self.itemGroups[key] ~= nil then
        for groupIdx, value in pairs(self.itemGroups[key]) do
          resolvedItemGroups[runtimeKey][groupIdx] = value
        end

        self:markDirty()
      end
    else
      resolvedFavorites[key] = identifier
      resolvedItemGroups[key] = self.itemGroups[key]
    end
  end

  self.favorites = resolvedFavorites
  self.itemGroups = resolvedItemGroups
end

---Validate a group index and optionally apply a default
-- @param integer|nil groupIndex group index to validate
-- @param integer|nil defaultGroupIndex fallback index when groupIndex is nil
-- @return integer|nil validGroupIndex
function ConstructionFavoritesSystem:getValidGroupIndex(groupIndex, defaultGroupIndex)
  local validGroupIndex = groupIndex

  if validGroupIndex == nil then
    validGroupIndex = defaultGroupIndex
  end

  if validGroupIndex == nil or validGroupIndex < 1 or validGroupIndex > #self.groups then
    return nil
  end

  return validGroupIndex
end

---Check if item is favorited
-- @param string identifier item identifier
-- @param integer groupIndex optional group index to check specifically
-- @return boolean isFavorite true if item is favorited
function ConstructionFavoritesSystem:isFavorite(identifier, groupIndex)
  self:ensureResolved()

  if identifier == nil then
    return false
  end

  local key = string.lower(tostring(identifier))

  if self.favorites[key] == nil then
    return false
  end

  if groupIndex ~= nil then
    local validGroupIndex = self:getValidGroupIndex(groupIndex)

    return validGroupIndex ~= nil and self.itemGroups[key] ~= nil and self.itemGroups[key][validGroupIndex] == true
  end

  return true
end

---Add item to favorites and assign to a group
-- @param string identifier item identifier
-- @param integer groupIndex target group index (default 1)
function ConstructionFavoritesSystem:addFavorite(identifier, groupIndex)
  if identifier == nil then
    return
  end

  local validGroupIndex = self:getValidGroupIndex(groupIndex, 1)

  if validGroupIndex == nil then
    return
  end

  local key = string.lower(tostring(identifier))

  self.favorites[key] = tostring(identifier)

  if self.itemGroups[key] == nil then
    self.itemGroups[key] = {}
  end

  self.itemGroups[key][validGroupIndex] = true
  self:markDirty()
end

---Remove item from favorites and clear group assignment
-- @param string identifier item identifier
-- @param integer groupIndex optional target group to remove from
function ConstructionFavoritesSystem:removeFavorite(identifier, groupIndex)
  if identifier == nil then
    return
  end

  local key = string.lower(tostring(identifier))

  if groupIndex ~= nil then
    local validGroupIndex = self:getValidGroupIndex(groupIndex)

    if validGroupIndex == nil or self.itemGroups[key] == nil then
      return
    end

    self.itemGroups[key][validGroupIndex] = nil

    if next(self.itemGroups[key]) == nil then
      self.favorites[key] = nil
      self.itemGroups[key] = nil
    end
  else
    self.favorites[key] = nil
    self.itemGroups[key] = nil
  end

  self:markDirty()
end

---Toggle favorite status within a specific group
-- @param string identifier item identifier
-- @param integer groupIndex group to toggle in
-- @return boolean isFavorite new favorite state
function ConstructionFavoritesSystem:toggleFavorite(identifier, groupIndex)
  if identifier == nil then
    return false
  end

  local validGroupIndex = self:getValidGroupIndex(groupIndex, 1)

  if validGroupIndex == nil then
    return false
  end

  local key = string.lower(tostring(identifier))
  local currentGroups = self.itemGroups[key]

  if currentGroups ~= nil and currentGroups[validGroupIndex] == true then
    self:removeFavorite(identifier, validGroupIndex)
    return false
  end

  self:addFavorite(identifier, validGroupIndex)
  return true
end

---Get the total number of favorited items
-- @return integer count number of favorites
function ConstructionFavoritesSystem:getFavoriteCount()
  local count = 0

  for _ in pairs(self.favorites) do
    count = count + 1
  end

  return count
end

---Add a new group
-- @param string name group display name
-- @param integer id group id used to select a color from GROUP_COLORS
-- @return integer|nil groupIndex the new group's index, or nil if limit reached
function ConstructionFavoritesSystem:addGroup(name, id)
  if #self.groups >= ConstructionFavoritesSystem.MAX_GROUPS then
    return nil
  end

  local group = {
    id = id or 1,
    name = name or "Group",
  }

  table.insert(self.groups, group)
  self:markDirty()

  return #self.groups
end

---Remove a group by index
-- @param integer groupIndex group to remove
function ConstructionFavoritesSystem:removeGroup(groupIndex)
  local validGroupIndex = self:getValidGroupIndex(groupIndex)

  if validGroupIndex == nil or validGroupIndex == 1 then
    return
  end

  local previousGroupCount = #self.groups
  table.remove(self.groups, validGroupIndex)

  for key, groups in pairs(self.itemGroups) do
    for i = validGroupIndex + 1, previousGroupCount do
      groups[i - 1] = groups[i]
    end

    groups[previousGroupCount] = nil

    if next(groups) == nil then
      self.favorites[key] = nil
      self.itemGroups[key] = nil
    end
  end

  if self.activeGroupIndex >= validGroupIndex then
    self.activeGroupIndex = self.activeGroupIndex - 1
  end

  self.activeGroupIndex = math.max(1, math.min(self.activeGroupIndex, #self.groups))
  self:markDirty()
end

---Rename a group
-- @param integer groupIndex group to rename
-- @param string newName new display name
function ConstructionFavoritesSystem:renameGroup(groupIndex, newName)
  local group = self.groups[groupIndex]

  if group == nil or newName == nil then
    return
  end

  local trimmedName = string.trim(tostring(newName))

  if trimmedName == "" then
    return
  end

  group.name = trimmedName
  self:markDirty()
end

---Set the color of a group
-- @param integer groupIndex group to update
-- @param integer id group id used to select a color from GROUP_COLORS
function ConstructionFavoritesSystem:setGroupColor(groupIndex, id)
  local group = self.groups[groupIndex]

  if group == nil or id == nil then
    return
  end

  local validId = tonumber(id)

  if validId == nil then
    return
  end

  validId = math.floor(validId)
  validId = math.max(1, math.min(validId, #ConstructionFavoritesSystem.GROUP_COLORS))

  group.id = validId
  self:markDirty()
end

---Get the first available group id that is not used by any group
-- @return integer id
function ConstructionFavoritesSystem:getAvailableGroupId()
  local usedColors = {}

  for _, group in ipairs(self.groups) do
    usedColors[group.id] = true
  end

  for i = 1, #ConstructionFavoritesSystem.GROUP_COLORS do
    if not usedColors[i] then
      return i
    end
  end

  return 1
end

---Get all groups
-- @return table groups list of group definitions
function ConstructionFavoritesSystem:getGroups()
  return self.groups
end

---Get the number of groups
-- @return integer count
function ConstructionFavoritesSystem:getGroupCount()
  return #self.groups
end

---Get the active group index
-- @return integer groupIndex
function ConstructionFavoritesSystem:getActiveGroup()
  return self.activeGroupIndex
end

---Set the active group index
-- @param integer groupIndex group to activate
function ConstructionFavoritesSystem:setActiveGroup(groupIndex)
  local validGroupIndex = self:getValidGroupIndex(groupIndex)

  if validGroupIndex ~= nil then
    self.activeGroupIndex = validGroupIndex
  end
end

---Cycle to the next group
-- @return integer groupIndex the newly active group index
function ConstructionFavoritesSystem:cycleActiveGroup()
  local nextIndex = self.activeGroupIndex + 1

  if nextIndex > #self.groups then
    nextIndex = 1
  end

  self.activeGroupIndex = nextIndex

  return nextIndex
end

---Get group mapping for a given item
-- @param string identifier item identifier
-- @return table|nil groupIndex map
function ConstructionFavoritesSystem:getItemGroups(identifier)
  self:ensureResolved()

  if identifier == nil then
    return nil
  end

  return self.itemGroups[string.lower(tostring(identifier))]
end

---Get the RGBA color for a group
-- @param integer groupIndex group index
-- @return number r red
-- @return number g green
-- @return number b blue
-- @return number a alpha
function ConstructionFavoritesSystem:getGroupColor(groupIndex)
  local group = self.groups[groupIndex]

  if group == nil then
    return 1, 0.698, 0.141, 1
  end

  local color = ConstructionFavoritesSystem.GROUP_COLORS[group.id] or ConstructionFavoritesSystem.GROUP_COLORS[1]

  return color[1], color[2], color[3], color[4]
end

---Load favorites and groups from xml file
function ConstructionFavoritesSystem:loadFromXMLFile()
  self.favorites = {}
  self.groups = {}
  self.itemGroups = {}
  self.isDirty = false
  self.isResolved = false

  local xmlFile = XMLFile.loadIfExists("ConstructionFavoritesXML", modSettingsDirectory .. "favorites.xml")

  if xmlFile == nil then
    return
  end

  -- load groups and nested items
  xmlFile:iterate("favorites.group", function(_, key)
    if #self.groups >= ConstructionFavoritesSystem.MAX_GROUPS then
      return
    end

    local id = xmlFile:getInt(key .. "#id", xmlFile:getInt(key .. "#colorIndex", 1))
    local name = xmlFile:getString(key .. "#name")

    if name ~= nil and name ~= "" then
      table.insert(self.groups, { id = id, name = name })
      local currentGroupIdx = #self.groups

      -- load nested items
      xmlFile:iterate(key .. ".item", function(_, itemKey)
        local identifier = xmlFile:getString(itemKey .. "#identifier")

        if identifier ~= nil and identifier ~= "" then
          identifier = ConstructionFavoritesSystem.toStorageKey(identifier)
          local lowerKey = string.lower(identifier)

          self.favorites[lowerKey] = identifier

          if self.itemGroups[lowerKey] == nil then
            self.itemGroups[lowerKey] = {}
          end

          self.itemGroups[lowerKey][currentGroupIdx] = true
        end
      end)
    end
  end)

  xmlFile:delete()
end

---Synchronize favorites with currently loaded mods
function ConstructionFavoritesSystem:sync()
  if self.hasSyncedThisSession then
    return
  end

  self.hasSyncedThisSession = true
  self:ensureResolved()
  self:saveIfDirty()
end

---Save favorites and groups only when data has changed
function ConstructionFavoritesSystem:saveIfDirty()
  if not self.isDirty then
    return
  end

  self:saveToXMLFile()
end

---Save favorites and groups to xml file
function ConstructionFavoritesSystem:saveToXMLFile()
  createFolder(modSettingsDirectory)

  local xmlFile = XMLFile.create("ConstructionFavoritesXML", modSettingsDirectory .. "favorites.xml", "favorites")

  if xmlFile == nil then
    Logging.warning("ConstructionFavorites: failed to create xml file at '%s'", modSettingsDirectory)
    return
  end

  -- save groups and nested items
  for i, group in ipairs(self.groups) do
    local key = string.format("favorites.group(%d)", i - 1)

    xmlFile:setInt(key .. "#id", group.id)
    xmlFile:setString(key .. "#name", group.name)

    local itemIndex = 0

    for lowerKey, identifier in pairs(self.favorites) do
      if self.itemGroups[lowerKey] ~= nil and self.itemGroups[lowerKey][i] == true then
        local itemKey = string.format("%s.item(%d)", key, itemIndex)

        xmlFile:setString(itemKey .. "#identifier", HTMLUtil.encodeToHTML(ConstructionFavoritesSystem.toStorageKey(identifier)))
        itemIndex = itemIndex + 1
      end
    end
  end

  xmlFile:save()
  xmlFile:delete()
  self.isDirty = false
end

-- predefined group star colors
ConstructionFavoritesSystem.GROUP_COLORS = {
  { 1.000, 0.745, 0.118, 1 },
  { 0.863, 0.078, 0.235, 1 },
  { 0.180, 0.800, 0.443, 1 },
  { 0.000, 0.447, 0.741, 1 },
  { 0.608, 0.349, 0.714, 1 },
  { 0.000, 0.588, 0.533, 1 },
  { 0.890, 0.102, 0.647, 1 },
  { 0.650, 0.850, 0.130, 1 },
  { 0.650, 0.400, 0.200, 1 },
}

---
g_constructionFavoritesSystem = ConstructionFavoritesSystem.new()
