local config = require('orgmode.config')
local utils = require('orgmode.utils')
local id_dir = require('orgmode.attach.id_dir')
local fs_utils = require('orgmode.utils.fs')

---@param headline OrgHeadline
---@param tag string
---@param onoff? boolean if true, add the tag; if false, remove the tag; if
---                      nil, toggle the tag
---@return boolean new_state
local function toggle_headline_tag(headline, tag, onoff)
  local current_tags = headline:get_own_tags()

  local present = vim.tbl_contains(current_tags, tag)
  if onoff == nil then
    onoff = not present
  end

  if onoff and not present then
    table.insert(current_tags, tag)
  elseif not onoff and present then
    current_tags = vim.tbl_filter(function(i) return i ~= tag end, current_tags)
  end

  headline:set_tags(utils.tags_to_string(current_tags))
  return onoff
end

---@class OrgAttachNode
---@field private headline? OrgHeadline
---@field private file OrgFile
local AttachNode = {}
AttachNode.__index = AttachNode

---@param headline OrgHeadline
---@return OrgAttachNode
function AttachNode.from_headline(headline)
  ---@type OrgAttachNode
  local data = {
    headline = headline,
    file = headline.file,
  }
  return setmetatable(data, AttachNode)
end

---@param file OrgFile
---@return OrgAttachNode
function AttachNode.from_file(file)
  ---@type OrgAttachNode
  local data = {
    file = file,
  }
  return setmetatable(data, AttachNode)
end

---@param file OrgFile
---@param cursor? [integer, integer] (1,0)-indexed cursor position
---@return OrgAttachNode
function AttachNode.at_cursor(file, cursor)
  local headline = file:get_closest_headline_or_nil(cursor)
  return headline
      and AttachNode.from_headline(headline)
      or AttachNode.from_file(file)
end

---@return OrgFile
function AttachNode:get_file()
  return self.file
end

---@return string filename
function AttachNode:get_filename()
  return self.file.filename
end

---@return string title
function AttachNode:get_title()
  if self.headline then
    return self.headline:get_title()
  end
  return self.file:get_title()
end

---Return the starting line of the attachment node.
---
---This is zero for file nodes and the 1-based line number for headline nodes.
---This is chosen such that every attachment node in an org file has
---a different line number.
---@return integer line
function AttachNode:get_start_line()
  if self.headline then
    return self.headline:node():start() + 1
  end
  return 0
end

---@param property_name string property name
---@param search_parents? boolean whether to recurse to parents
---@return string|nil property
function AttachNode:get_property(property_name, search_parents)
  if search_parents == nil then
    search_parents = config:use_attach_inheritance(property_name)
  end
  local property
  if self.headline then
    property = self.headline:get_property(property_name, search_parents)
    if property or not search_parents then
      return property
    end
  end
  property = self.file:get_property(property_name)
  return property
end

---@param name string property name
---@param value? string property value
---@return nil
function AttachNode:set_property(name, value)
  if self.headline then
    self.headline:set_property(name, value)
  else
    self.file:set_property(name, value)
  end
end

---@return string id
function AttachNode:id_get_or_create()
  return self.headline
      and self.headline:id_get_or_create()
      or self.file:id_get_or_create()
end

---Find the attachment directory associated with this node.
---
---@return string|nil attach_dir
function AttachNode:get_dir()
  local dir = self:get_property('dir')
  if dir then
    ---@todo relative to own file, not to the current one!
    ---this will require modifying substitute_path() and get_real_path()
    return fs_utils.substitute_path(dir) or nil
  end
  local id = self:get_property('id')
  if id then
    dir = id_dir.get_existing_from_id(id)
    return dir and fs_utils.substitute_path(dir) or nil
  end
  return nil
end

---Set the attachment directory on the current node.
---
---In addition to `set_property()`, this also adjusts the path to be relative,
---if required by `org_attach_dir_relative`.
---
---@param dir string
---@return string new_dir_resolved exact value of the `DIR` property
---@overload fun(): nil
function AttachNode:set_dir(dir)
  if dir then
    if config.org_attach_dir_relative then
      dir = fs_utils.make_relative(dir, vim.fs.dirname(self.file.filename))
    else
      dir = vim.fn.fnamemodify(dir, ':p')
    end
  end
  self:set_property('DIR', dir)
  return dir
end

---@param tag string
---@param onoff? boolean if true, add the tag; if false, remove the tag; if
---                      nil, toggle the tag
---@return boolean|nil new_state
function AttachNode:toggle_tag(tag, onoff)
  ---@todo There is currently no way to set #+FILETAGS programmatically. Do
  ---nothing when before first heading (attaching to file) to avoid blocking
  ---error.
  return self.headline and toggle_headline_tag(self.headline, tag, onoff)
end

---@param onoff? boolean if true, add the tag; if false, remove the tag; if
---                      nil, toggle the tag
---@return boolean|nil new_state
function AttachNode:toggle_auto_tag(onoff)
  return config.org_attach_auto_tag
      and self:toggle_tag(config.org_attach_auto_tag, onoff)
end

return AttachNode
