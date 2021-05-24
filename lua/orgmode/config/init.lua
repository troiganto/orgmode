local instance = {}
local Config = {}
local utils = require('orgmode.utils')
local defaults = require('orgmode.config.defaults')
local mappings = require('orgmode.config.mappings')

---@class Config
---@param opts? table
function Config:new(opts)
  local data = {
    opts = vim.tbl_deep_extend('force', defaults, opts or {})
  }
  setmetatable(data, self)
  return data
end

function Config:__index(key)
  if self.opts[key] then return self.opts[key] end
  return rawget(getmetatable(self), key)
end

function Config:get(opt, default)
  return self.opts[opt] or default
end

---@param opts table
---@return Config
function Config:extend(opts)
  self.opts = vim.tbl_deep_extend('force', self.opts, opts or {})
  return self
end

---@return string[]
function Config:get_all_files()
  if not self.org_agenda_files or self.org_agenda_files == '' then
    return {}
  end
  return vim.fn.glob(vim.fn.fnamemodify(self.org_agenda_files, ':p'), 0, 1)
end

---@return number
function Config:get_week_start_day_number()
  return utils.convert_from_isoweekday(1)
end

---@return number
function Config:get_week_end_day_number()
  return utils.convert_from_isoweekday(7)
end

---@return string|number
function Config:get_agenda_span()
  local span = self.opts.org_agenda_span
  local valid_spans = {'day', 'month', 'week', 'year'}
  if type(span) == 'string' and not vim.tbl_contains(valid_spans, span) then
    utils.echo_warning(string.format(
      'Invalid agenda span %s. Valid spans: %s. Falling back to week',
      span,
      table.concat(valid_spans, ', ')
    ))
    span = 'week'
  end
  if type(span) == 'number' and span < 0 then
    utils.echo_warning(string.format(
      'Invalid agenda span number %d. Must be 0 or more. Falling back to week',
      span,
      table.concat(valid_spans, ', ')
    ))
    span = 'week'
  end
  return span
end

function Config:setup_mappings(category)
  if self.opts.mappings.disable_all then return end
  if not category then
    utils.keymap('n', self.opts.mappings.global.org_agenda, '<cmd>lua require("orgmode").action("agenda.prompt")<CR>')
    utils.keymap('n', self.opts.mappings.global.org_capture, '<cmd>lua require("orgmode").action("capture.prompt")<CR>')
    return
  end
  if not self.opts.mappings[category] then return end

  for name, key in pairs(self.opts.mappings[category]) do
    if mappings[category] and mappings[category][name] then
      local map = vim.tbl_map(function(i) return string.format('"%s"', i) end, mappings[category][name])
      utils.buf_keymap(0, 'n', key, string.format('<cmd>lua require("orgmode").action(%s)<CR>', table.concat(map, ', ')))
    end
  end
end

instance = Config:new()
return instance