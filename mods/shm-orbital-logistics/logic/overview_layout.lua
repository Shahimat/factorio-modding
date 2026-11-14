-- Бюджет ширины overview в GUI-единицах. Отступы задаются renderer явно:
-- активация scrollbar и содержимое карточки не меняют ширину viewport.
local layout = {
  VERSION = 1,
  FRAME_PADDING = 8,
  CARD_PADDING = 12,
  SCROLLBAR = 12,
  BLOCK_PADDING = 8,
  GAP = 4,
  DIVIDER = 1,
  TOGGLE = 24,
  PURPOSE = 116,
  PLACE = 28,
  ITEM = 32,
  NAME = 220,
  CARD_ICON = 28,
  ROUTE_PLANET = 32,
  ROUTE_ARROW = 20,
}

function layout.widths(window)
  local cards = window - 2 * layout.FRAME_PADDING - layout.SCROLLBAR
  local content = cards - 2 * layout.CARD_PADDING
  local columns = content - 2 * layout.DIVIDER - 4 * layout.GAP
  local sections = math.floor(columns * 0.42)
  local now = math.floor(columns * 0.33)
  return { cards = cards, content = content, sections = sections, now = now, lines = columns - sections - now }
end

function layout.section_row(width)
  -- На узком окне название остаётся над полями; на обычном — всё в ряд.
  -- Раскладка зависит только от ширины колонки, не от выбранного назначения.
  local below = width < 260
  local name = below and (width - layout.TOGGLE - layout.GAP)
    or math.min(180, width - layout.TOGGLE - layout.PURPOSE - 2 * layout.PLACE - 3 * layout.GAP)
  local remaining = below and (width - layout.PURPOSE - layout.GAP)
    or (width - layout.TOGGLE - name - layout.PURPOSE - 3 * layout.GAP)
  local places = math.max(1, math.floor(remaining / layout.PLACE))
  return { below = below, name = name, places = places, picker = places * layout.PLACE }
end

function layout.exceptions(width, max_items)
  local columns = math.max(1, math.min(8, math.floor((width * 0.45 + layout.GAP) / (layout.ITEM + layout.GAP))))
  local used = math.min(columns, max_items)
  local icons = used * layout.ITEM + (used - 1) * layout.GAP
  return { columns = columns, icons = icons, status = width - icons - layout.GAP }
end

function layout.route(card)
  local width = card - 2 * layout.CARD_PADDING - layout.TOGGLE - layout.CARD_ICON - layout.NAME - 3 * layout.GAP
  local cell = layout.ROUTE_PLANET + layout.GAP + layout.ROUTE_ARROW
  local columns = math.max(1, math.floor((width + layout.GAP) / (cell + layout.GAP)))
  return { width = width, cell = cell, columns = columns }
end

return layout
