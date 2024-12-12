local config = require('orgmode.config')
local fileops = require('orgmode.attach.fileops')
local fs_utils = require('orgmode.utils.fs')

local M = {}

---@overload fun(func: (string|fun(id: string): string?), id: string): string?
local translate = setmetatable({}, {
  ---@param self table<string, fun(id: string): string?>
  ---@param func string | fun(id: string): string?
  ---@param id string ID property
  ---@return string|nil attach_dir
  __call = function(self, func, id)
    return (self[func] or func)(id)
  end
})

---Translate an UUID ID into a folder-path.
---Default format for how Org translates ID properties to a path for
---attachments.  Useful if ID is generated with UUID.
---@param id string
---@return string | nil path
function translate.uuid_folder_format(id)
  if id:len() <= 2 then
    return nil
  end
  return ('%s/%s'):format(id:sub(1, 2), id:sub(3))
end

---Translate an ID based on a timestamp to a folder-path.
---Useful way of translation if ID is generated based on ISO8601 timestamp.
---Splits the attachment folder hierarchy into year+month and the rest.
---@param id string
---@return string | nil path
function translate.ts_folder_format(id)
  if id:len() <= 6 then
    return nil
  end
  return ('%s/%s'):format(id:sub(1, 6), id:sub(7))
end

---Return `__/X/ID` folder path as a dumb fallback.
---X is the first character in the ID string.
---This function may be appended to `org_attach_id_path_function_list` to
---provide a fallback for non-standard ID values that other functions in
---`org_attach_id_path_function_list` are unable to handle. For example,
---when the ID is too short for `org_attach_id_ts_folder_format`.
---However, we recommend to define a more specific function spreading entries
---over multiple folders.  This function may create a large number of entries
---in a single folder, which may cause issues on some systems."
---@param id string
---@return string path
function translate.fallback_folder_format(id)
  assert(id ~= '', id)
  return ("__/%s/%s"):format(id:sub(1, 1), id)
end

M.translate = translate

---Return a folder path based on `org_attach_id_dir` and ID.
---Try `id_to_path` functions in `org_attach_id_to_path_function_list`
---and return the first truthy result.
---@param id string node ID property to expand into a directory
---@return string|nil attach_dir
function M.get_from_id(id)
  local basedir = fs_utils.substitute_path(config.org_attach_id_dir)
  if not basedir then
    return nil
  end
  for _, func in ipairs(config.org_attach_id_to_path_function_list) do
    local name = func(id)
    if name then
      return vim.fs.joinpath(basedir, name)
    end
  end
  return nil
end

---Return a folder path based on `org_attach_id_dir` and ID.
---This is like `get_dir_from_id()`, but the resulting path must exist in the
---filesystem.
---@param id string node ID property to expand into a directory
---@return string|nil attach_dir
function M.get_existing_from_id(id)
  local basedir = fs_utils.substitute_path(config.org_attach_id_dir)
  if not basedir then
    return nil
  end
  local default_basedir = fs_utils.substitute_path('./data/')
  assert(default_basedir)
  for _, func in ipairs(config.org_attach_id_to_path_function_list) do
    local name = M.translate(func, id)
    if name then
      local candidate = vim.fs.joinpath(basedir, name)
      if fileops.is_dir(candidate) then
        return candidate
      end
      local fallback = vim.fs.joinpath(default_basedir, name)
      if fileops.is_dir(fallback) then
        return fallback
      end
    end
  end
  return nil
end

return M
