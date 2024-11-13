local Promise = require('orgmode.utils.promise')
local utils = require('orgmode.utils')

local M = {}

---@generic T
---@param items `T`[]
---@param opts {prompt?: string, kind?: string, format_item?: fun(item: T): string}
---@return OrgPromise<T | nil>
function M.select(items, opts)
  return Promise.new(function(resolve, reject)
    local ok, err = pcall(vim.ui.select, items, opts, function(choice)
      resolve(choice)
    end)
    if not ok then
      reject(err)
    end
  end)
end

---@param pattern string
---@return integer | nil bufnr
local function any_bufnr(pattern)
  local regex = vim.regex(vim.fn.glob2regpat(pattern))
  local mods = { ':.', ':p', ':~' }
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    for _, mod in ipairs(mods) do
      local expanded = vim.fn.fnamemodify(name, mod)
      if regex:match_str(expanded) then
        return bufnr
      end
    end
  end
end

---@param buf integer | string
---@return integer | nil bufnr
local function get_bufnr_verbose(buf)
  local bufnr = vim.fn.bufnr(buf)
  if bufnr ~= -1 then
    return bufnr
  end
  -- bufnr() failed, was there no match or more than one?
  if type(buf) == 'string' then
    if any_bufnr(buf) then
      utils.echo_warning('more than one match for ' .. tostring(buf))
    else
      utils.echo_warning('no matching buffer for ' .. tostring(buf))
    end
  else
    utils.echo_warning(('buffer %d does not exist'):format(buf))
  end
end

---@param buf? integer | string
---@param opts? {prompt?: string, default?: string}
---@return OrgPromise<integer | nil> bufnr
function M.select_buffer(buf, opts)
  if buf and buf ~= '' then
    return Promise.resolve(get_bufnr_verbose(buf))
  end
  opts = vim.tbl_extend('force', { prompt = 'Select a buffer: ' }, opts or {}, {
    completion = 'buffer',
    highlight = false,
  })
  return M.input(opts):next(function(input)
    if not input or input == '' then
      return nil
    end
    return get_bufnr_verbose(input)
  end)
end

---@param opts? {prompt?: string, default?: string, completion?: string|fun(arglead: string, cmdline: string, cursorpos: integer): string[]}
---@return OrgPromise<string | nil>
function M.input(opts)
  opts = opts or {}
  local prompt = opts.prompt or ''
  local default = opts.default or ''
  local completion = opts.completion
  if type(completion) == 'function' then
    completion = 'customlist,' .. vim.fn.get(completion, 'name')
  end
  return Promise.new(function(resolve, reject)
    local ok, err = pcall(vim.ui.input, {
      prompt = prompt,
      default = default,
      completion = completion,
    }, function(input)
      resolve(input)
    end)
    if not ok then
      reject(err)
    end
  end)
end

---@param msg string
---@param choices? string | string[]
---@param default? integer
---@param dtype? 'Error' | 'Question' | 'Info' | 'Warning' | 'Generic'
---@return OrgPromise<integer> choice
function M.confirm(msg, choices, default, dtype)
  choices = choices or ''
  if type(choices) == 'table' then
    choices = table.concat(choices, '\n')
  end
  return Promise.new(function(resolve, reject)
    vim.schedule(function()
      local ok, res = pcall(vim.fn.confirm, msg, choices, default, dtype)
      if ok then
        resolve(res)
      else
        reject(res)
      end
    end)
  end)
end

---@param msg string
---@return OrgPromise<'yes' | 'no'> choice
function M.yes_or_no_slow(msg)
  local function prompt()
    return M.input({ prompt = msg .. '(yes or no) ' }):next(function(choice)
      if choice then
        choice = choice:lower()
        if choice == 'yes' or choice == 'no' then
          return choice
        end
      end
      return prompt()
    end)
  end
  return prompt()
end

---@param msg string
---@return OrgPromise<'yes' | 'no' | nil> choice
function M.yes_or_no_or_cancel_slow(msg)
  local function prompt()
    return M.input({
      prompt = msg .. '(yes or no, ESC to cancel) ',
    }):next(function(choice)
      if not choice then
        return nil
      end
      choice = choice:lower()
      if choice == 'yes' or choice == 'no' then
        return choice
      end
      return prompt()
    end)
  end
  return prompt()
end

return M
