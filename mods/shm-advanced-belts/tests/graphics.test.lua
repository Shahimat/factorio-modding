local graphics = require('logic.graphics')

local TINT = { r = 1, g = 0, b = 0 }
local BELT = '__space-age__/graphics/entity/turbo-transport-belt/turbo-transport-belt.png'
local BELT_MASK = '__shm-advanced-belts__/graphics/entity/transport-belt/transport-belt-mask.png'

describe('mask_path', function()
  it('файл турбо получает маску в моде по тому же правилу, что инструмент', function()
    assert_eq(graphics.mask_path(BELT), BELT_MASK)
    assert_eq(
      graphics.mask_path('__space-age__/graphics/entity/turbo-splitter/turbo-splitter-east-top_patch.png'),
      '__shm-advanced-belts__/graphics/entity/splitter/splitter-east-top_patch-mask.png'
    )
  end)

  it('замёрзшие патчи, остатки и чужие файлы — без маски', function()
    assert_nil(graphics.mask_path('__space-age__/graphics/entity/turbo-transport-belt/turbo-transport-belt-frozen.png'))
    assert_nil(graphics.mask_path('__space-age__/graphics/entity/turbo-splitter/remnants/turbo-splitter-remnants.png'))
    assert_nil(graphics.mask_path('__base__/graphics/entity/transport-belt/transport-belt.png'))
    assert_nil(graphics.mask_path(nil))
  end)
end)

describe('recolor', function()
  it('спрайт турбо становится парой слоёв, маска с tint', function()
    local prototype = { belt_animation_set = { animation_set = { filename = BELT, size = 128 } } }
    graphics.recolor(prototype, TINT)
    local layers = prototype.belt_animation_set.animation_set.layers
    assert_eq(#layers, 2)
    assert_eq(layers[1].filename, BELT)
    assert_eq(layers[2].filename, BELT_MASK)
    assert_eq(layers[2].tint, TINT)
    assert_eq(layers[2].size, 128)
  end)

  it('лист sheet превращается в список sheets', function()
    local file = '__space-age__/graphics/entity/turbo-underground-belt/turbo-underground-belt-structure.png'
    local prototype = { structure = { direction_in = { sheet = { filename = file, width = 192 } } } }
    graphics.recolor(prototype, TINT)
    local direction = prototype.structure.direction_in
    assert_nil(direction.sheet)
    assert_eq(#direction.sheets, 2)
    assert_eq(direction.sheets[2].tint, TINT)
  end)

  it('в существующих layers маска встаёт сразу за своим слоем', function()
    local shadow = { filename = '__base__/graphics/shadow.png' }
    local prototype = { picture = { layers = { { filename = BELT }, shadow } } }
    graphics.recolor(prototype, TINT)
    local layers = prototype.picture.layers
    assert_eq(#layers, 3)
    assert_eq(layers[2].filename, BELT_MASK)
    assert_eq(layers[3], shadow)
  end)

  it('маска не рисуется тенью и свечением', function()
    local prototype = { picture = { filename = BELT, draw_as_shadow = true, draw_as_glow = true } }
    graphics.recolor(prototype, TINT)
    local mask = prototype.picture.layers[2]
    assert_nil(mask.draw_as_shadow)
    assert_nil(mask.draw_as_glow)
  end)

  it('замёрзший патч не трогается', function()
    local frozen = { filename = '__space-age__/graphics/entity/turbo-transport-belt/turbo-transport-belt-frozen.png' }
    local prototype = { frozen_patch = frozen }
    graphics.recolor(prototype, TINT)
    assert_eq(prototype.frozen_patch, frozen)
  end)
end)

describe('recolor_icons', function()
  it('icon превращается в icons с маской', function()
    local prototype = { icon = '__space-age__/graphics/icons/turbo-splitter.png', icon_size = 64 }
    graphics.recolor_icons(prototype, TINT)
    assert_nil(prototype.icon)
    assert_eq(#prototype.icons, 2)
    assert_eq(prototype.icons[2].icon, '__shm-advanced-belts__/graphics/icons/splitter-mask.png')
    assert_eq(prototype.icons[2].tint, TINT)
    assert_eq(prototype.icons[2].icon_size, 64)
  end)

  it('чужая иконка остаётся без маски', function()
    local prototype = { icon = '__base__/graphics/icons/splitter.png' }
    graphics.recolor_icons(prototype, TINT)
    assert_eq(#prototype.icons, 1)
  end)
end)
