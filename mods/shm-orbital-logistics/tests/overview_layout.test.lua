local layout = require('logic.overview_layout')

describe('геометрия окна обзора', function()
  it('ширина карточек учитывает рамку и постоянный gutter, колонки — разделители и интервалы', function()
    for window = 560, 1200 do
      local w = layout.widths(window)
      assert(w.cards + 2 * layout.FRAME_PADDING + layout.SCROLLBAR == window)
      assert(w.content + 2 * layout.CARD_PADDING == w.cards)
      assert(w.sections + w.now + w.lines + 2 * layout.DIVIDER + 4 * layout.GAP == w.content)
      assert(w.sections > 2 * layout.BLOCK_PADDING and w.now > 2 * layout.BLOCK_PADDING and w.lines > 2 * layout.BLOCK_PADDING)
    end
  end)

  it('название, назначение и выбор мест помещаются даже на минимальной и сдвинутой ширине', function()
    for window = 560, 1200 do
      local width = layout.widths(window).sections - 2 * layout.BLOCK_PADDING
      local row = layout.section_row(width)
      assert(row.name > 0 and row.places >= 2)
      if row.below then
        assert(layout.TOGGLE + layout.GAP + row.name <= width)
        assert(layout.PURPOSE + layout.GAP + row.picker <= width)
      else
        assert(layout.TOGGLE + row.name + layout.PURPOSE + row.picker + 3 * layout.GAP <= width)
      end
    end
  end)

  it('строки исключений с разным числом иконок делят один бюджет колонок', function()
    for window = 560, 1200 do
      local width = layout.widths(window).now - 2 * layout.BLOCK_PADDING
      local columns = layout.exceptions(width, 10)
      assert(columns.icons + layout.GAP + columns.status == width)
      assert(columns.status > 0)
      for _, count in ipairs({ 1, 4, 10 }) do
        local used = math.min(count, columns.columns)
        assert(used * layout.ITEM + (used - 1) * layout.GAP <= columns.icons)
      end
    end
  end)

  it('полные циклы переносятся внутри остатка заголовка и не расширяют карточку', function()
    for window = 560, 1200 do
      local route = layout.route(layout.widths(window).cards)
      assert(route.columns >= 1)
      assert(route.cell * route.columns + layout.GAP * (route.columns - 1) <= route.width)
      assert(layout.TOGGLE + layout.CARD_ICON + layout.NAME + 3 * layout.GAP + route.width == layout.widths(window).content)
    end
  end)
end)
