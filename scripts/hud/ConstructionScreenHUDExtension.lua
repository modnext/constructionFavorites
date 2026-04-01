--
-- ConstructionScreenHUDExtension
--
-- Author: aaw3k
-- Copyright (C) Mod Next, All Rights Reserved.
--

ConstructionScreenHUDExtension = {}

local ConstructionScreenHUDExtension_mt = Class(ConstructionScreenHUDExtension)

---Create a new instance of ConstructionScreenHUDExtension
function ConstructionScreenHUDExtension.new(screen, customMt)
  local self = setmetatable({}, customMt or ConstructionScreenHUDExtension_mt)

  self.priority = GS_PRIO_NORMAL

  local r, g, b, a = unpack(HUD.COLOR.BACKGROUND)

  self.background = g_overlayManager:createOverlay("gui.shortcutBox2", 0, 0, 0, 0)
  self.background:setColor(r, g, b, a)

  self.separatorHorizontal = g_overlayManager:createOverlay(g_plainColorSliceId, 0, 0, 0, 0)
  self.separatorHorizontal:setColor(1, 1, 1, 0.25)

  self.screen = screen

  -- captured help elements
  self.favoriteElement = nil
  self.manageGroupsElement = nil
  self.deleteGroupElement = nil

  self:storeScaledValues()

  g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.UI_SCALE], self.storeScaledValues, self)

  return self
end

---Delete instance and free resources
function ConstructionScreenHUDExtension:delete()
  self.background:delete()
  self.separatorHorizontal:delete()
  g_messageCenter:unsubscribeAll(self)
end

---Recalculate scaled dimensions for current UI scale
function ConstructionScreenHUDExtension:storeScaledValues()
  local uiScale = g_gameSettings:getValue(GameSettings.SETTING.UI_SCALE)
  local width, height = getNormalizedScreenValues(330 * uiScale, 50 * uiScale)

  self.background:setDimension(width, height)
  self.separatorHorizontal:setDimension(width, g_pixelSizeY)

  _, self.inputHeight = getNormalizedScreenValues(0, 25 * uiScale)
end

---Intercept favorite actions from the default help display
-- @param table inputHelpDisplay the InputHelpDisplay instance
-- @param table eventHelpElements list of current help elements
function ConstructionScreenHUDExtension:setEventHelpElements(inputHelpDisplay, eventHelpElements)
  -- skip all three actions from the default help list
  inputHelpDisplay:addSkipAction(InputAction.TOGGLE_FAVORITE)
  inputHelpDisplay:addSkipAction(InputAction.MANAGE_FAVORITE_GROUPS)
  inputHelpDisplay:addSkipAction(InputAction.DELETE_FAVORITE_GROUP)

  self.favoriteElement = nil
  self.manageGroupsElement = nil
  self.deleteGroupElement = nil

  if eventHelpElements ~= nil then
    for _, helpElement in ipairs(eventHelpElements) do
      local actionName = helpElement.actionName

      if actionName == InputAction.TOGGLE_FAVORITE then
        self.favoriteElement = helpElement
      elseif actionName == InputAction.MANAGE_FAVORITE_GROUPS then
        self.manageGroupsElement = helpElement
      elseif actionName == InputAction.DELETE_FAVORITE_GROUP then
        self.deleteGroupElement = helpElement
      end
    end
  end
end

---Get the help elements that should be drawn in the custom box
-- @return table elementsToDraw visible help elements in display order
function ConstructionScreenHUDExtension:getElementsToDraw()
  local elementsToDraw = {}

  if self.favoriteElement ~= nil then
    table.insert(elementsToDraw, self.favoriteElement)
  end

  if self.manageGroupsElement ~= nil then
    table.insert(elementsToDraw, self.manageGroupsElement)
  end

  if self.deleteGroupElement ~= nil then
    table.insert(elementsToDraw, self.deleteGroupElement)
  end

  return elementsToDraw
end

---Draw the HUD extension box with grouped favorite actions
-- @param table inputHelpDisplay the InputHelpDisplay instance
-- @param float posX x position to draw at
-- @param float posY y position to draw at
-- @return float posY updated y position after drawing
function ConstructionScreenHUDExtension:draw(inputHelpDisplay, posX, posY)
  local elementsToDraw = self:getElementsToDraw()
  local numRows = #elementsToDraw

  if numRows == 0 then
    return posY
  end

  local totalHeight = numRows * self.inputHeight

  self.background:setDimension(self.background.width, totalHeight)

  posY = posY - totalHeight

  self.background:setPosition(posX, posY)
  self.background:render()

  local textOffsetX = inputHelpDisplay.textOffsetX
  local textOffsetY = inputHelpDisplay.textOffsetY
  local textSize = inputHelpDisplay.textSize
  local textPosX = posX + textOffsetX

  for i, element in ipairs(elementsToDraw) do
    local rowY = posY + totalHeight - (i * self.inputHeight)
    local elementWidth = inputHelpDisplay:drawInput(posX + self.background.width, rowY, self.inputHeight, element)

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)

    local elementText = element.text or ""
    elementText = utf8ToUpper(elementText)

    local textStartX = textPosX
    local maxTextWidth = self.background.width - elementWidth - 2 * textOffsetX
    local overrideRender = false

    if element == self.favoriteElement then
      local activeGroup = g_constructionFavoritesSystem:getActiveGroup()
      local groupName = utf8ToUpper(ConstructionScreenExtension.getActiveGroupName())

      local identifier = ConstructionScreenExtension.getSelectedItemIdentifier(self.screen)
      local isFavorite = identifier ~= nil and g_constructionFavoritesSystem:isFavorite(identifier, activeGroup)
      local template = g_i18n:getText(isFavorite and "constructionFavorites_removeFromGroup" or "constructionFavorites_addToGroup")

      local sStart, sEnd = string.find(template, "%s", 1, true)

      if sStart then
        local prefix = utf8ToUpper(string.sub(template, 1, sStart - 1))
        local suffix = utf8ToUpper(string.sub(template, sEnd + 1))

        local prefixWidth = getTextWidth(textSize, prefix)
        local groupWidth = getTextWidth(textSize, groupName)
        local suffixWidth = getTextWidth(textSize, suffix)

        if prefixWidth + groupWidth + suffixWidth <= maxTextWidth then
          local r, g, b, a = g_constructionFavoritesSystem:getGroupColor(activeGroup)

          renderText(textStartX, rowY + textOffsetY, textSize, prefix)
          textStartX = textStartX + prefixWidth

          setTextColor(r, g, b, a)
          renderText(textStartX, rowY + textOffsetY, textSize, groupName)
          textStartX = textStartX + groupWidth

          setTextColor(1, 1, 1, 1)
          renderText(textStartX, rowY + textOffsetY, textSize, suffix)

          overrideRender = true
        end
      end
    end

    if not overrideRender then
      elementText = Utils.limitTextToWidth(elementText, textSize, maxTextWidth, false, "...")
      renderText(textStartX, rowY + textOffsetY, textSize, elementText)
    end

    setTextBold(false)

    -- draw separator between rows
    if i < numRows then
      self.separatorHorizontal:renderCustom(posX, rowY)
    end
  end

  return posY
end

---Get the height of this extension
-- @return float height current height or 0 if not visible
function ConstructionScreenHUDExtension:getHeight()
  local numRows = #self:getElementsToDraw()

  if numRows == 0 then
    return 0
  end

  return numRows * self.inputHeight
end
