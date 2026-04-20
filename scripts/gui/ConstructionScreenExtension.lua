--
-- ConstructionScreenExtension
--
-- Author: aaw3k
-- Copyright (C) Mod Next, All Rights Reserved.
--

ConstructionScreenExtension = {}

---Ensure the favorites category exists and register group tabs
-- @return table|nil category
function ConstructionScreenExtension.registerFavoritesCategory()
  local category = ConstructionScreenExtension.getFavoritesCategory()

  if category == nil then
    g_storeManager:addConstructionCategory("favorites", g_i18n:getText("constructionFavorites_category"), nil, nil, "", "guiElementsConstructionFavorites.icon_favorites")

    category = ConstructionScreenExtension.getFavoritesCategory()
  end

  if category == nil then
    return nil
  end

  category.tabs = {}

  for index, group in ipairs(g_constructionFavoritesSystem:getGroups()) do
    category.tabs[index] = {
      name = string.format("GROUP_%d", index),
      title = group.name,
      iconFilename = nil,
      iconUVs = nil,
      iconSliceId = nil,
      index = index,
    }
  end

  return category
end

---Force a full GUI refresh after group changes
-- @param table self ConstructionScreen instance
-- @param integer tabIndex tab index to select after refresh
function ConstructionScreenExtension.refreshAfterGroupChange(self, tabIndex)
  local favoriteCategory = ConstructionScreenExtension.registerFavoritesCategory()

  self.categories = g_storeManager:getConstructionCategories()
  ConstructionScreenExtension.refreshFavoritesItems(self)

  if favoriteCategory ~= nil and ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    ConstructionScreenExtension.rebuildFavoriteDots(self, favoriteCategory)
    ConstructionScreenExtension.setFavoriteTabState(self, tabIndex)
    ConstructionScreenExtension.refreshFavoriteTabContent(self)
  end

  self.categorySelector:reloadData()
  ConstructionScreenExtension.updateAllActionTexts(self)
end

---Collect favorited items filtered by group index
-- @param table screenSelf ConstructionScreen instance
-- @param integer groupIndex group to filter by
-- @return table items list of favorite item entries for the group
function ConstructionScreenExtension.collectFavoriteItemsForGroup(screenSelf, groupIndex)
  local items = {}
  local seenIdentifiers = {}

  if screenSelf == nil or screenSelf.items == nil then
    return items
  end

  local favoriteCategory = ConstructionScreenExtension.getFavoritesCategory()

  for categoryIndex, tabs in ipairs(screenSelf.items) do
    if favoriteCategory == nil or categoryIndex ~= favoriteCategory.index then
      for _, tabItems in ipairs(tabs) do
        for _, item in ipairs(tabItems) do
          local identifier = ConstructionScreenExtension.getItemIdentifier(item)
          local favoriteKey = identifier ~= nil and string.lower(tostring(identifier)) or nil

          if identifier ~= nil and favoriteKey ~= nil and seenIdentifiers[favoriteKey] == nil and g_constructionFavoritesSystem:isFavorite(identifier, groupIndex) then
            local favoriteItem = ConstructionScreenExtension.cloneItem(item)

            seenIdentifiers[favoriteKey] = true
            favoriteItem.uniqueIndex = #items + 1
            table.insert(items, favoriteItem)
          end
        end
      end
    end
  end

  return items
end

---Refresh the items shown inside the favorites category
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.refreshFavoritesItems(self)
  local favoriteCategory = ConstructionScreenExtension.getFavoritesCategory()

  if favoriteCategory == nil then
    return
  end

  if self.items == nil then
    self.items = {}
  end

  self.items[favoriteCategory.index] = {}

  for groupIndex = 1, g_constructionFavoritesSystem:getGroupCount() do
    self.items[favoriteCategory.index][groupIndex] = ConstructionScreenExtension.collectFavoriteItemsForGroup(self, groupIndex)
  end
end

---Create or get favorite icon bitmaps for a list cell
-- @param table cell itemList cell
-- @param integer count number of icons required
-- @return table|nil favoriteIcons list of cloned bitmaps or nil
function ConstructionScreenExtension.ensureFavoriteIcons(cell, count)
  if cell == nil then
    return nil
  end

  if cell.constructionFavoritesFavoriteIcons == nil then
    cell.constructionFavoritesFavoriteIcons = {}
  end

  local baseIcon = cell:getAttribute("icon")

  if baseIcon == nil then
    return nil
  end

  local icons = cell.constructionFavoritesFavoriteIcons
  local sizeX, sizeY = getNormalizedScreenValues(20, 20)
  local paddingX, paddingY = getNormalizedScreenValues(30, 20)
  local spacingX, spacingY = getNormalizedScreenValues(24, 24)
  local maxPerRow = 5

  while #icons < count do
    local favoriteIcon = baseIcon:clone(cell)
    local iconIndex = #icons
    local row = math.floor(iconIndex / maxPerRow)
    local column = iconIndex % maxPerRow

    favoriteIcon.name = "favoriteIcon" .. tostring(iconIndex + 1)
    favoriteIcon.anchors = { 1, 1, 1, 1 }
    favoriteIcon.pivot = { 1, 1 }

    favoriteIcon:setImageSlice(nil, "guiElementsConstructionFavorites.icon_star_outline")
    favoriteIcon:setSize(sizeX, sizeY)
    favoriteIcon:setPosition(-paddingX - column * spacingX, -paddingY - row * spacingY)
    favoriteIcon:setVisible(false)

    table.insert(icons, favoriteIcon)
  end

  return icons
end

---Update favorite icon visibility and color on a list cell
-- @param table self ConstructionScreen instance
-- @param table item list item
-- @param table cell itemList cell
function ConstructionScreenExtension.updateFavoriteCell(self, item, cell)
  local activeGroups = {}

  if not ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) and item ~= nil then
    local identifier = ConstructionScreenExtension.getItemIdentifier(item)

    if identifier ~= nil and g_constructionFavoritesSystem:isFavorite(identifier) then
      activeGroups = ConstructionScreenExtension.getSortedItemGroups(identifier)
    end
  end

  cell.isFavoriteItem = #activeGroups > 0

  local favoriteIcons = ConstructionScreenExtension.ensureFavoriteIcons(cell, #activeGroups)

  if favoriteIcons == nil then
    return
  end

  for iconIndex, icon in ipairs(favoriteIcons) do
    local groupIndex = activeGroups[iconIndex]

    icon:setVisible(groupIndex ~= nil)

    if groupIndex ~= nil then
      local r, g, b, a = g_constructionFavoritesSystem:getGroupColor(groupIndex)

      icon:setImageColor(nil, r, g, b, a)
    end
  end
end

---Handle K key press: create group on favorites, cycle group on other categories
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.onManageGroups(self)
  if ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    if g_constructionFavoritesSystem:getGroupCount() < ConstructionFavoritesSystem.MAX_GROUPS then
      ConstructionScreenExtension.showCreateGroupDialog(self)
    end

    return
  end

  g_constructionFavoritesSystem:cycleActiveGroup()
  ConstructionScreenExtension.updateAllActionTexts(self)
end

---Open the create group dialog using TextInputDialog
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.showCreateGroupDialog(self)
  local dialogPrompt = g_i18n:getText("constructionFavorites_groupName")
  local confirmText = g_i18n:getText("button_ok")

  TextInputDialog.show(function(newName, confirmed)
    if confirmed and not string.isNilOrWhitespace(newName) then
      local groupId = g_constructionFavoritesSystem:getAvailableGroupId()
      local newIndex = g_constructionFavoritesSystem:addGroup(string.trim(newName), groupId)

      if newIndex ~= nil then
        ConstructionScreenExtension.refreshAfterGroupChange(self, newIndex)
      end
    end
  end, nil, "", dialogPrompt, dialogPrompt, nil, confirmText, nil, g_i18n:getText("constructionFavorites_createGroup"))
end

---Delete the currently active group tab
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.deleteCurrentGroup(self)
  if not ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    return
  end

  local activeGroup = g_constructionFavoritesSystem:getActiveGroup()

  if activeGroup <= 1 then
    return
  end

  local groups = g_constructionFavoritesSystem:getGroups()
  local groupName = groups[activeGroup] ~= nil and groups[activeGroup].name or ""
  local text = string.format(g_i18n:getText("constructionFavorites_deleteGroupConfirm"), groupName)
  local title = g_i18n:getText("constructionFavorites_deleteGroup")

  YesNoDialog.show(function(confirmed)
    if not confirmed then
      return
    end

    local nextGroup = math.max(1, activeGroup - 1)

    g_constructionFavoritesSystem:removeGroup(activeGroup)
    g_constructionFavoritesSystem:setActiveGroup(nextGroup)

    ConstructionScreenExtension.refreshAfterGroupChange(self, nextGroup)
  end, nil, text, title)
end

---Update the favorite action event text based on active group
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.updateFavoriteActionText(self)
  if self.favoriteActionEvent == nil then
    return
  end

  local identifier = ConstructionScreenExtension.getSelectedItemIdentifier(self)

  if identifier == nil then
    ConstructionScreenExtension.setActionEventState(self.favoriteActionEvent, false, nil, false)

    return
  end

  local activeGroup = g_constructionFavoritesSystem:getActiveGroup()
  local groupName = ConstructionScreenExtension.getActiveGroupName()
  local isInGroup = g_constructionFavoritesSystem:isFavorite(identifier, activeGroup)
  local text

  if isInGroup then
    text = string.format(g_i18n:getText("constructionFavorites_removeFromGroup"), groupName)
  else
    text = string.format(g_i18n:getText("constructionFavorites_addToGroup"), groupName)
  end

  ConstructionScreenExtension.setActionEventState(self.favoriteActionEvent, true, text, true)
end

---Update the manage groups action event text and visibility
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.updateManageGroupsActionText(self)
  if self.manageGroupsActionEvent == nil then
    return
  end

  local isFavoritesCategory = ConstructionScreenExtension.isFavoritesCategory(self.currentCategory)
  local canManage = (isFavoritesCategory and g_constructionFavoritesSystem:getGroupCount() < ConstructionFavoritesSystem.MAX_GROUPS)
    or (not isFavoritesCategory and ConstructionScreenExtension.getSelectedItemIdentifier(self) ~= nil)

  if not canManage then
    ConstructionScreenExtension.setActionEventState(self.manageGroupsActionEvent, false, nil, false)
    return
  end

  local text = isFavoritesCategory and g_i18n:getText("constructionFavorites_createGroup") or g_i18n:getText("constructionFavorites_switchGroup")

  ConstructionScreenExtension.setActionEventState(self.manageGroupsActionEvent, true, text, true)
end

---Update delete group action visibility
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.updateDeleteGroupActionText(self)
  if self.deleteGroupActionEvent == nil then
    return
  end

  local canDelete = ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) and g_constructionFavoritesSystem:getActiveGroup() > 1

  ConstructionScreenExtension.setActionEventState(self.deleteGroupActionEvent, canDelete, g_i18n:getText("constructionFavorites_deleteGroup"), canDelete)
end

---Update all custom action texts
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.updateAllActionTexts(self)
  ConstructionScreenExtension.updateFavoriteActionText(self)
  ConstructionScreenExtension.updateManageGroupsActionText(self)
  ConstructionScreenExtension.updateDeleteGroupActionText(self)
end

---Toggle favorite status for the currently selected item using the active group
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.onToggleFavorite(self)
  local identifier = ConstructionScreenExtension.getSelectedItemIdentifier(self)

  if identifier == nil then
    return
  end

  g_constructionFavoritesSystem:toggleFavorite(identifier, g_constructionFavoritesSystem:getActiveGroup())
  ConstructionScreenExtension.refreshFavoritesItems(self)
  self.itemList:reloadData()

  ConstructionScreenExtension.updateEmptyFavoritesDetails(self)
  ConstructionScreenExtension.updateAllActionTexts(self)
end

---Clone an item
-- @param table item item to clone
-- @return table copy of the item
function ConstructionScreenExtension.cloneItem(item)
  local copy = {}

  for key, value in pairs(item) do
    copy[key] = value
  end

  return copy
end

---Get the favorites construction category
-- @return table|nil category
function ConstructionScreenExtension.getFavoritesCategory()
  return g_storeManager:getConstructionCategoryByName("favorites")
end

function ConstructionScreenExtension.getClampedFavoriteTab(tabIndex)
  local favoriteCategory = ConstructionScreenExtension.getFavoritesCategory()
  local maxTab = favoriteCategory ~= nil and #favoriteCategory.tabs or 0

  if maxTab == 0 then
    return 1
  end

  return math.max(1, math.min(tabIndex or g_constructionFavoritesSystem:getActiveGroup(), maxTab))
end

---Check if the given category index is the favorites category
-- @param integer categoryIndex current category index
-- @return boolean isFavoritesCategory true if current category is favorites
function ConstructionScreenExtension.isFavoritesCategory(categoryIndex)
  local favoriteCategory = ConstructionScreenExtension.getFavoritesCategory()

  return favoriteCategory ~= nil and categoryIndex == favoriteCategory.index
end

---Get the currently visible item list
-- @param table self ConstructionScreen instance
-- @return table|nil items
function ConstructionScreenExtension.getCurrentItems(self)
  if self.currentCategory == nil or self.currentTab == nil then
    return nil
  end

  if self.items == nil or self.items[self.currentCategory] == nil then
    return nil
  end

  return self.items[self.currentCategory][self.currentTab]
end

---Clear favorite dots
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.clearFavoriteDots(self)
  if self.subCategoryDotBox == nil or self.subCategoryDotBox.elements == nil then
    return
  end

  for index, dot in pairs(self.subCategoryDotBox.elements) do
    dot:delete()
    self.subCategoryDotBox.elements[index] = nil
  end
end

---Update favorite dot colors
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.updateFavoriteDotColors(self)
  if self.subCategoryDotBox == nil or self.subCategoryDotBox.elements == nil then
    return
  end

  for groupIndex, dot in ipairs(self.subCategoryDotBox.elements) do
    local r, g, b, a = g_constructionFavoritesSystem:getGroupColor(groupIndex)

    dot.color = { 0.20156, 0.20156, 0.20156, 1 }
    dot.colorSelected = { r, g, b, a }
  end
end

---Rebuild favorite dots
-- @param table self ConstructionScreen instance
-- @param table favoriteCategory favorite category
function ConstructionScreenExtension.rebuildFavoriteDots(self, favoriteCategory)
  ConstructionScreenExtension.clearFavoriteDots(self)

  local subCategoryTexts = {}

  for dotIndex, tab in ipairs(favoriteCategory.tabs) do
    local dot = self.subCategoryDotTemplate:clone(self.subCategoryDotBox)

    dot.getIsSelected = function()
      return self.currentTab == dotIndex
    end

    table.insert(subCategoryTexts, tab.title)
  end

  self.subCategorySelector:setTexts(subCategoryTexts)
  self.subCategoryDotBox:invalidateLayout()

  ConstructionScreenExtension.updateFavoriteDotColors(self)
end

---Set favorite tab state
-- @param table self ConstructionScreen instance
-- @param integer tabIndex tab index to set
-- @return integer targetTab the set tab index
function ConstructionScreenExtension.setFavoriteTabState(self, tabIndex)
  local targetTab = ConstructionScreenExtension.getClampedFavoriteTab(tabIndex)

  if self.subCategorySelector ~= nil then
    self.subCategorySelector:setState(targetTab, true)
  end

  self.currentTab = targetTab
  g_constructionFavoritesSystem:setActiveGroup(targetTab)

  return targetTab
end

---Get the currently selected item identifier
-- @param table self ConstructionScreen instance
-- @return string|nil identifier
function ConstructionScreenExtension.getSelectedItemIdentifier(self)
  local items = ConstructionScreenExtension.getCurrentItems(self)

  if items == nil or self.itemList == nil then
    return nil
  end

  return ConstructionScreenExtension.getItemIdentifier(items[self.itemList.selectedIndex])
end

---Get sorted item groups for an identifier
-- @param string identifier item identifier
-- @return table sorted group indices
function ConstructionScreenExtension.getSortedItemGroups(identifier)
  local activeGroups = {}
  local groups = g_constructionFavoritesSystem:getItemGroups(identifier)

  if groups ~= nil then
    for groupIndex in pairs(groups) do
      table.insert(activeGroups, groupIndex)
    end

    table.sort(activeGroups)
  end

  return activeGroups
end

---Get a unique identifier for an item (storeItem or brush)
-- @param table item construction screen item
-- @return string|nil identifier
function ConstructionScreenExtension.getItemIdentifier(item)
  if item == nil then
    return nil
  end

  if item.storeItem ~= nil then
    return item.storeItem.xmlFilename
  end

  if item.brushParameters ~= nil and #item.brushParameters > 0 then
    if item.brushClass == ConstructionBrushSculpt then
      return "sculpt:" .. tostring(item.brushParameters[1])
    elseif item.brushClass == ConstructionBrushPaint then
      return "paint:" .. tostring(item.brushParameters[1])
    end

    return "brush:" .. tostring(item.brushParameters[1])
  end

  return item.name
end

---Update empty favorites details
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.updateEmptyFavoritesDetails(self)
  if not ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    return
  end

  local items = ConstructionScreenExtension.getCurrentItems(self)

  if items == nil or #items == 0 then
    ConstructionScreenExtension.showEmptyPlaceholderDetails(self)
  end
end

---Refresh favorite tab content
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.refreshFavoriteTabContent(self)
  local items = ConstructionScreenExtension.getCurrentItems(self)

  if items == nil or #items == 0 then
    self:assignItemAttributeData(nil)
  else
    self.itemList:setSelectedIndex(1)
  end

  self:setBrush(self.selectorBrush, true)
  self:updateMenuState()

  ConstructionScreenExtension.updateEmptyFavoritesDetails(self)
end

---Check if favorites placeholder should be drawn
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.shouldDrawFavoritesPlaceholder(self)
  if not ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    return false
  end

  local items = ConstructionScreenExtension.getCurrentItems(self)

  return items ~= nil and #items == 0
end

---Get the display name of the currently active group
-- @return string groupName
function ConstructionScreenExtension.getActiveGroupName()
  local groups = g_constructionFavoritesSystem:getGroups()
  local activeIndex = g_constructionFavoritesSystem:getActiveGroup()

  if groups[activeIndex] ~= nil then
    return groups[activeIndex].name
  end

  return ""
end

---Shows placeholder text in details panel when category is empty
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.showEmptyPlaceholderDetails(self)
  self:assignItemAttributeData(nil)

  if self.itemDetailsName ~= nil then
    self.itemDetailsName:setText(g_i18n:getText("configuration_valueEmpty"))
    self.itemDetailsName:setVisible(true)
  end
end

---Creates favorites placeholder overlay
-- @param table self ConstructionScreen instance
function ConstructionScreenExtension.createFavoritesPlaceholder(self)
  if self.constructionFavoritesPlaceholder ~= nil then
    return
  end

  local sliceInfo = g_overlayManager:getSliceInfoById("guiElementsConstructionFavorites.icon_grid")

  if sliceInfo == nil then
    return
  end

  local size = 0.04
  local overlay = Overlay.new(sliceInfo.filename, 0, 0, size, size * g_screenAspectRatio)

  overlay:setUVs(sliceInfo.uvs)
  overlay:setColor(1, 1, 1, 0.3)

  self.constructionFavoritesPlaceholder = overlay
end

---Set action event state
function ConstructionScreenExtension.setActionEventState(eventId, isVisible, text, isActive)
  if eventId == nil then
    return
  end

  if isActive ~= nil then
    g_inputBinding:setActionEventActive(eventId, isActive)
  end

  if text ~= nil then
    g_inputBinding:setActionEventText(eventId, text)
  end

  g_inputBinding:setActionEventTextVisibility(eventId, isVisible)
end

---Register a menu action event
function ConstructionScreenExtension.registerMenuActionEvent(self, fieldName, inputAction, callback, defaultText)
  local _, eventId = g_inputBinding:registerActionEvent(inputAction, self, callback, false, true, false, true)

  if eventId == nil then
    return nil
  end

  g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
  g_inputBinding:setActionEventTextVisibility(eventId, false)

  if defaultText ~= nil then
    g_inputBinding:setActionEventText(eventId, defaultText)
  end

  self[fieldName] = eventId

  return eventId
end

---Remove a menu action event
-- @param table self ConstructionScreen instance
-- @param string fieldName field name
function ConstructionScreenExtension.removeMenuActionEvent(self, fieldName)
  local eventId = self[fieldName]

  if eventId ~= nil then
    g_inputBinding:removeActionEvent(eventId)
    self[fieldName] = nil
  end
end

---Register favorites category and populate with favorited items
local function rebuildDataAppended(self)
  if g_constructionFavoritesSystem ~= nil then
    g_constructionFavoritesSystem:sync()
  end

  ConstructionScreenExtension.registerFavoritesCategory()

  self.categories = g_storeManager:getConstructionCategories()

  ConstructionScreenExtension.refreshFavoritesItems(self)
  self.categorySelector:reloadData()
  ConstructionScreenExtension.updateAllActionTexts(self)
end

---
ConstructionScreen.rebuildData = Utils.appendedFunction(ConstructionScreen.rebuildData, rebuildDataAppended)

---Add HUD extension every frame during draw
local function drawPrepended(self)
  if ConstructionScreen.uiHidden then
    return
  end

  if self.constructionFavoritesHUDExtension ~= nil then
    table.insert(g_currentMission.hud.inputHelp.helpExtensions, self.constructionFavoritesHUDExtension)
  end
end

---
ConstructionScreen.draw = Utils.prependedFunction(ConstructionScreen.draw, drawPrepended)

---Draw the placeholder grid icon if the favorites category is empty
local function onDraw(self)
  if ConstructionScreen.uiHidden then
    return
  end

  if not ConstructionScreenExtension.shouldDrawFavoritesPlaceholder(self) then
    return
  end

  if self.constructionFavoritesPlaceholder == nil then
    ConstructionScreenExtension.createFavoritesPlaceholder(self)
  end

  if self.constructionFavoritesPlaceholder == nil then
    return
  end

  local listContainer = self.itemList.parent

  if listContainer == nil then
    return
  end

  local size = 0.04
  local sizeY = size * g_screenAspectRatio
  local posX = listContainer.absPosition[1] + (listContainer.absSize[1] - size) * 0.5
  local posY = listContainer.absPosition[2] + (listContainer.absSize[2] - sizeY) * 0.5

  self.constructionFavoritesPlaceholder:setPosition(posX, posY)
  self.constructionFavoritesPlaceholder:render()
end

---
ConstructionScreen.draw = Utils.appendedFunction(ConstructionScreen.draw, onDraw)

---Register all action events and create HUD extension
local function registerMenuActionEventsAppended(self, _)
  ConstructionScreenExtension.registerMenuActionEvent(self, "favoriteActionEvent", InputAction.TOGGLE_FAVORITE, ConstructionScreenExtension.onToggleFavorite)
  ConstructionScreenExtension.registerMenuActionEvent(self, "manageGroupsActionEvent", InputAction.MANAGE_FAVORITE_GROUPS, ConstructionScreenExtension.onManageGroups)
  ConstructionScreenExtension.registerMenuActionEvent(self, "deleteGroupActionEvent", InputAction.DELETE_FAVORITE_GROUP, ConstructionScreenExtension.deleteCurrentGroup, g_i18n:getText("constructionFavorites_deleteGroup"))

  if self.constructionFavoritesHUDExtension == nil then
    self.constructionFavoritesHUDExtension = ConstructionScreenHUDExtension.new(self)
  end

  ConstructionScreenExtension.updateAllActionTexts(self)
end

---
ConstructionScreen.registerMenuActionEvents = Utils.appendedFunction(ConstructionScreen.registerMenuActionEvents, registerMenuActionEventsAppended)

---Remove action events and delete HUD extension
local function removeMenuActionEventsAppended(self)
  ConstructionScreenExtension.removeMenuActionEvent(self, "favoriteActionEvent")
  ConstructionScreenExtension.removeMenuActionEvent(self, "manageGroupsActionEvent")
  ConstructionScreenExtension.removeMenuActionEvent(self, "deleteGroupActionEvent")

  if self.constructionFavoritesHUDExtension ~= nil then
    self.constructionFavoritesHUDExtension:delete()
    self.constructionFavoritesHUDExtension = nil
  end

  if self.constructionFavoritesPlaceholder ~= nil then
    self.constructionFavoritesPlaceholder:delete()
    self.constructionFavoritesPlaceholder = nil
  end
end

---
ConstructionScreen.removeMenuActionEvents = Utils.appendedFunction(ConstructionScreen.removeMenuActionEvents, removeMenuActionEventsAppended)

---Save favorites data once when the construction screen closes
local function onCloseAppended(self)
  if g_constructionFavoritesSystem ~= nil then
    g_constructionFavoritesSystem:saveIfDirty()
  end
end

---
ConstructionScreen.onClose = Utils.appendedFunction(ConstructionScreen.onClose, onCloseAppended)

---Update action texts when list selection changes
local function onListSelectionChangedAppended(self, list, section, index)
  if list == self.itemList then
    ConstructionScreenExtension.updateAllActionTexts(self)
  end
end

---
ConstructionScreen.onListSelectionChanged = Utils.appendedFunction(ConstructionScreen.onListSelectionChanged, onListSelectionChangedAppended)

---Update action texts when list highlight changes
local function onListHighlightChangedAppended(self, list, section, index)
  if list == self.itemList then
    ConstructionScreenExtension.updateAllActionTexts(self)
  end
end

---
ConstructionScreen.onListHighlightChanged = Utils.appendedFunction(ConstructionScreen.onListHighlightChanged, onListHighlightChangedAppended)

---Update favorite icon visibility on item list cells
local function populateCellForItemInSectionOverwritten(self, superFunc, list, section, index, cell)
  superFunc(self, list, section, index, cell)

  if list ~= self.categorySelector then
    local items = ConstructionScreenExtension.getCurrentItems(self)
    local item = items ~= nil and items[index] or nil

    ConstructionScreenExtension.updateFavoriteCell(self, item, cell)
  end
end

---
ConstructionScreen.populateCellForItemInSection = Utils.overwrittenFunction(ConstructionScreen.populateCellForItemInSection, populateCellForItemInSectionOverwritten)

---Restore tab state when switching categories
local function setCurrentCategoryOverwritten(self, superFunc, categoryIndex, ...)
  local previousActiveGroup = g_constructionFavoritesSystem:getActiveGroup()

  self.isChangingCategory = true
  superFunc(self, categoryIndex, ...)
  self.isChangingCategory = false

  if ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    local targetTab = ConstructionScreenExtension.getClampedFavoriteTab(previousActiveGroup)

    g_constructionFavoritesSystem:setActiveGroup(targetTab)

    if self.currentTab ~= targetTab then
      self:setCurrentTab(targetTab)

      if self.subCategorySelector ~= nil then
        self.subCategorySelector:setState(targetTab, true)
      end
    end

    ConstructionScreenExtension.updateFavoriteDotColors(self)
    ConstructionScreenExtension.updateEmptyFavoritesDetails(self)
  end

  ConstructionScreenExtension.updateAllActionTexts(self)
end

---
ConstructionScreen.setCurrentCategory = Utils.overwrittenFunction(ConstructionScreen.setCurrentCategory, setCurrentCategoryOverwritten)

---Sync active group when switching tabs within favorites
local function setCurrentTabAppended(self, index)
  if ConstructionScreenExtension.isFavoritesCategory(self.currentCategory) then
    if not self.isChangingCategory then
      g_constructionFavoritesSystem:setActiveGroup(index or 1)
    end

    ConstructionScreenExtension.updateEmptyFavoritesDetails(self)
  end

  ConstructionScreenExtension.updateAllActionTexts(self)
end

---
ConstructionScreen.setCurrentTab = Utils.appendedFunction(ConstructionScreen.setCurrentTab, setCurrentTabAppended)
