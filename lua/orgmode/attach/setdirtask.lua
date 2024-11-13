local Promise = require('orgmode.utils.promise')
local config = require('orgmode.config') ---@todo can we remove config from this module?
local fs_utils = require('orgmode.utils.fs')
local fsops = require('orgmode.attach.fsops')

---Helper for OrgAttach:set_directory() and unset_directory().
---
---@class orgmode.attach.set_directory.task
---@field node OrgAttachNode
---@field old_dir string|nil
---@field new_dir string|nil
---@field do_copy boolean
---@field do_delete boolean
---@field do_property_change boolean
local Task = {}
Task.__index = Task

---@param node OrgAttachNode
function Task.new(node)
  return setmetatable({
    node = node,
    old_dir = node:get_dir(),
    do_delete = false,
    do_copy = false,
    do_property_change = false,
  }, Task)
end

---@return OrgPromise<boolean> success
function Task:copy()
  local old = self.old_dir
  local new = self.new_dir
  return Promise.resolve(old and new and self.do_copy and fsops.copy_directory(old, new, {
    parents = true,
    keep_times = true,
    create_symlink = config.org_attach_copy_directory_create_symlink,
  }))
end

---@return nil
function Task:change_property()
  if not self.do_property_change then
    return
  end
  local path = self.new_dir
  if path then
    if config.org_attach_dir_relative then
      path = fs_utils.make_relative(path, vim.fs.dirname(self.node:get_filename()))
    else
      path = vim.fn.fnamemodify(path, ':p')
    end
  end
  self.node:set_property('DIR', path)
end

---@return OrgPromise<boolean>
function Task:delete()
  local old = self.old_dir
  return Promise.resolve(old and self.do_delete and fsops.remove_directory(old, { recursive = true }))
end

---@return OrgPromise<boolean>
function Task:run()
  return self
      :copy()
      :next(function()
        return self:change_property()
      end)
      :next(function()
        return self:delete()
      end)
end

return Task
