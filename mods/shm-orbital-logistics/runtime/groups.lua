-- Перевод секции на имя группы с другой меткой. Переименовать группу API не
-- умеет, поэтому все участники старой группы переводятся на новое имя, а
-- старая группа удаляется. Назначение меняется сразу у всех хабов группы —
-- как и положено метке в общем имени.

local tags = require('logic.tags')

local groups = {}

--- Новое имя для секции с меткой `tag`. Секция без группы получает имя по
--- платформе и номеру секции.
function groups.name_for(section, tag, fallback)
  local base = section.group ~= '' and section.group or fallback
  return tags.retag(base, tag)
end

--- Переводит секцию (и всех участников её группы) на имя `name`.
--- Возвращает true или false и ключ причины для сообщения игроку.
function groups.rename(force, section, name)
  local old = section.group
  if name == old then
    return true
  end
  if name == '' then
    return false, 'empty-name'
  end
  if force.get_logistic_group(name) then
    return false, 'name-taken'
  end
  if old == '' then
    section.group = name
    return true
  end
  local group = force.get_logistic_group(old)
  local members = group and group.members or { section }
  for _, member in pairs(members) do
    if member.valid and member.is_manual then
      member.group = name
    end
  end
  local left = force.get_logistic_group(old)
  if left and #left.members == 0 then
    force.delete_logistic_group(old)
  end
  return true
end

return groups
