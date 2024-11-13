local Promise = require('orgmode.utils.promise')

local M = {}

---@param items any[]
---@param opts {prompt?: string, format_item?: function, kind?: string}
---@return OrgPromise<string | nil>
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

---@param opts {prompt?: string, default?: string, completion?: string, highlight?: function}
---@return OrgPromise<string | nil>
function M.input(opts)
  return Promise.new(function(resolve, reject)
    local ok, err = pcall(vim.ui.input, opts, function(input)
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
---@param default? 'yes' | 'no'
---@return OrgPromise<'yes' | 'no' | nil> choice
function M.yes_or_no_or_cancel_slow(msg, default)
  local function prompt()
    return M.input({
      prompt = msg .. '(yes or no, ESC to cancel) ',
    }):next(function(choice)
      if not choice then
        return default
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
