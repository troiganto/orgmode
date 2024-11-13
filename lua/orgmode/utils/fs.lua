local utils = require('orgmode.utils')

local M = {}

---Check whether given path is absolute.
---
---Paths are considered absolute if they start with '/' or '~/'. The syntax
---'~user/' is not recognized.
---
---@param path_str string
---@return boolean
function M.is_absolute(path_str)
  return path_str:match('^~?/') and true or false
end

---@param path_str string
---@return string | false
function M.substitute_path(path_str)
  if path_str:match('^/') then
    return path_str
  elseif path_str:match('^~/') then
    local home_path = os.getenv('HOME')
    return home_path and path_str:gsub('^~', home_path) or false
  elseif path_str:match('^%./') then
    local base = vim.fn.fnamemodify(utils.current_file_path(), ':p:h')
    return base .. '/' .. path_str:gsub('^%./', '')
  elseif path_str:match('^%.%./') then
    local base = vim.fn.fnamemodify(utils.current_file_path(), ':p:h')
    return base .. '/' .. path_str
  end
  return false
end

---@param filepath string
---@return string | false
function M.get_real_path(filepath)
  if not filepath then
    return false
  end
  local substituted = M.substitute_path(filepath)
  if not substituted then
    return false
  end
  local real = vim.loop.fs_realpath(substituted)
  if real and filepath:sub(-1, -1) == '/' then
    -- make sure if filepath gets a trailing slash, the realpath gets one, too.
    real = real .. '/'
  end
  return real or false
end

---@return string
function M.get_current_file_dir()
  local current_file = utils.current_file_path()
  local current_dir = vim.fn.fnamemodify(current_file, ':p:h')
  return current_dir or ''
end

---@param filepath string an absolute path
---@param base? string an absolute path to an ancestor of filepath;
---                    if nil, uses the current file's directory
---@return string filepath_relative_to_base
function M.make_relative(filepath, base)
  local abs_filepath = M.substitute_path(filepath)
  if not abs_filepath then
    error('filepath must be absolute' .. tostring(filepath))
  end
  local abs_base = M.substitute_path(base or './')
  if not abs_base then
    error('base must be absolute' .. tostring(base))
  end
  if abs_base:sub(-1, -1) ~= '/' then
    abs_base = abs_base .. '/'
  end
  if abs_filepath == abs_base then
    return '.'
  end
  if abs_filepath:sub(1, #abs_base) == abs_base then
    return abs_filepath:sub(#abs_base + 1, -1)
  end
  return abs_filepath
end

return M
