local utils = require('orgmode.utils')
local fs_utils = require('orgmode.utils.fs')
local config = require('orgmode.config')
local Menu = require('orgmode.ui.menu')
local Promise = require('orgmode.utils.promise')
local ui_utils = require('orgmode.attach.ui')

---@class OrgAttach
---@field files OrgFiles
local Attach = {}

---@param opts? table
function Attach:new(opts)
  opts = opts or {}
  local data = {
    files = opts.files,
  }
  setmetatable(data, self)
  self.__index = self
  return data
end

---Check if we have enough information to root the attachment directory.
---
---When DIR is given, check also if it is already absolute. Otherwise,
---assume that it will be relative, and check if `org_attach_id_dir' is
---absolute, or if at least the current buffer has a file name.
---
---Throw an error if we cannot root the directory.
---
---@param dir string | nil
---@return nil
local function check_absolute_path(dir)
  if dir and fs_utils.is_absolute(dir)
      or fs_utils.is_absolute(config.org_attach_id_dir)
      or utils.current_file_path() ~= ''
  then
    return
  end
  error("Need absolute `org_attach_id_dir` to attach in buffers without filename")
end

---@param files OrgFiles
---@param name string property name
---@param search_parents? boolean whether to recurse to parents
---@param cursor? table (1, 0) indexed base position tuple
---@return string? property
local function get_property_at_cursor(files, name, search_parents, cursor)
  local path = utils.current_file_path()
  local file = files:load_file_sync(path)
  if not file then
    return nil
  end
  local headline = file:get_closest_headline_or_nil(cursor)
  local property = nil
  if headline then
    property = headline:get_property(name, search_parents)
    if not property and search_parents then
      property = file:get_property(name)
    end
  else
    property = file:get_property(name)
  end
  return property
end

---@param files OrgFiles
---@param name string property name
---@param value? string property value
---@param cursor? table (1, 0) indexed base position tuple
---@return nil
local function set_property_at_cursor(files, name, value, cursor)
  local path = utils.current_file_path()
  local file = files:load_file_sync(path)
  if not file then
    return nil
  end
  local headline = file:get_closest_headline_or_nil(cursor)
  if headline then
    headline:set_property(name, value)
  else
    file:set_property(name, value)
  end
end

---@param files OrgFiles
---@param cursor? table (1, 0) indexed base position tuple
---@return string
local function get_or_create_id_at_cursor(files, cursor)
  local path = utils.current_file_path()
  local file = files:load_file_sync(path)
  if not file then
    error(('not an org file: %s'):format(path))
  end
  local headline = file:get_closest_headline_or_nil(cursor)
  return headline and headline:id_get_or_create() or file:id_get_or_create()
end

---@return boolean
local function use_inheritance()
  if config.org_attach_use_inheritance == 'selective' then
    ---@diagnostic disable-next-line
    return config.org_use_property_inheritance
  end
  return config.org_attach_use_inheritance and true or false
end

---@return OrgPromise<'id' | 'dir' | nil>
local function preferred_method()
  local method = config.org_attach_preferred_new_method
  if not method then
    return Promise.resolve(nil)
  end
  if method == 'id' then
    return Promise.resolve('id')
  end
  if method == 'dir' then
    return Promise.resolve('dir')
  end
  if method == 'ask' then
    return ui_utils.select({ 'id', 'dir' }, {
      prompt = 'How to create attachments directory?',
      format_item = function(item)
        return ('Create new %s property'):format(item:upper())
      end,
    })
  end
  local msg = string.format('invalid value for org_attach_preferred_new_method: %s', method)
  return Promise.reject(msg)
end

function Attach:prompt()
  local menu = Menu:new({
    title = 'Press key for an attach command',
    prompt = 'Press key for an attach command',
  })

  menu:add_option({
    label = 'Select a file and attach it to the task.',
    key = 'a',
    action = function() return self:attach() end,
  })
  menu:add_option({
    label = 'Attach a file using copy method.',
    key = 'c',
    action = function() return self:attach_cp() end,
  })
  menu:add_option({
    label = 'Attach a file using move method.',
    key = 'm',
    action = function() return self:attach_mv() end,
  })
  menu:add_option({
    label = 'Attach a file using link method.',
    key = 'l',
    action = function() return self:attach_ln() end,
  })
  menu:add_option({
    label = 'Attach a file using symbolic-link method.',
    key = 'y',
    action = function() return self:attach_lns() end,
  })
  menu:add_option({
    label = 'Attach a file from URL (downloading it).',
    key = 'u',
    action = function() return self:attach_url() end,
  })
  menu:add_option({
    label = 'Select a buffer and attach its contents to the task.',
    key = 'b',
    action = function() return self:attach_buffer() end,
  })
  menu:add_option({
    label = 'Create a new attachment, as a vim buffer.',
    key = 'n',
    action = function() return self:attach_new() end,
  })
  menu:add_option({
    label = 'Synchronize current node with its attachment directory.',
    key = 'z',
    action = function() return self:sync() end,
  })
  menu:add_option({
    label = 'Open current node\'s attachments.',
    key = 'o',
    action = function() return self:open() end,
  })
  menu:add_option({
    label = 'Open current node\'s attachments in vim.',
    key = 'O',
    action = function() return self:open_in_vim() end,
  })
  menu:add_option({
    label = 'Open current node\'s attachment directory. Create if missing.',
    key = 'f',
    action = function() return self:reveal() end,
  })
  menu:add_option({
    label = 'Open current node\'s attachment directory in vim.',
    key = 'F',
    action = function() return self:reveal() end,
  })
  menu:add_option({
    label = 'Select and delete one attachment',
    key = 'd',
    action = function() return self:delete_one() end,
  })
  menu:add_option({
    label = 'Delete all attachments of the current node.',
    key = 'D',
    action = function() return self:delete_all() end,
  })
  menu:add_option({
    label = 'Set specific attachment directory for current node.',
    key = 's',
    action = function() return self:set_directory() end,
  })
  menu:add_option({
    label = 'Unset specific attachment directory for current node.',
    key = 'S',
    action = function() return self:unset_directory() end,
  })
  menu:add_option({ label = 'Quit', key = 'q' })
  menu:add_separator({ icon = ' ', length = 1 })

  return menu:open()
end

---@param cursor? table (1, 0) indexed base position tuple
---@return string?
function Attach:_get_dir_base(cursor)
  local recursive = use_inheritance()
  local dir = get_property_at_cursor(self.files, 'DIR', recursive, cursor)
  if dir then
    check_absolute_path(dir)
    return dir
  end
  local id = get_property_at_cursor(self.files, 'ID', recursive, cursor)
  if id then
    check_absolute_path(nil)
    return self:get_dir_from_id(id, true)
  end
  return nil
end

---Return the directory associated with the current outline node.
---
---First check for DIR property, then ID property.
---`org_attach_use_inheritance' determines whether inherited
---properties also will be considered.
---
---If an ID property is found the default mechanism using that ID
---will be invoked to access the directory for the current entry.
---Note that this method returns the directory as declared by ID or
---DIR even if the directory doesn't exist in the filesystem.
---
---@param cursor? table (1, 0) indexed base position tuple
---@param create_if_not_exists? boolean if true, call get_dir_or_create()
---@param no_fs_check? boolean if true, return the directory even if it doesn't
---                            exist
---@return OrgPromise<string | nil> attach_dir
function Attach:get_dir(cursor, create_if_not_exists, no_fs_check)
  local dir_promise = create_if_not_exists
      and self:get_dir_or_create(cursor)
      or Promise.resolve(self:_get_dir_base(cursor))
  return dir_promise:next(function(dir)
    return (no_fs_check or vim.fs.is_dir(dir)) and dir or nil
  end)
end

---Return the directory associated with the current outline node.
---
---First check for DIR property, then ID property.
---`org_attach_use_inheritance' determines whether inherited
---properties also will be considered.
---
---If an ID property is found the default mechanism using that ID
---will be invoked to access the directory for the current entry.
---Note that this method returns the directory as declared by ID or
---DIR even if the directory doesn't exist in the filesystem.
---
---@param cursor? table (1, 0) indexed base position tuple
---@param create_if_not_exists? boolean if true, call get_dir_or_create()
---@param no_fs_check? boolean if true, return the directory even if it doesn't
---                            exist
---@return string? attach_dir
function Attach:get_dir_sync(cursor, create_if_not_exists, no_fs_check)
  return self:get_dir(cursor, create_if_not_exists, no_fs_check):wait()
end

---Return existing or new directory associated with the current outline node.
---
---`org_attach_preferred_new_method` decides how to attach new directory if
---neither ID nor DIR property exist.
---
---If the attachment by some reason cannot be created an error will be raised.
---
---@param cursor? table (1, 0) indexed base position tuple
---@return OrgPromise<string>
function Attach:get_dir_or_create(cursor)
  return Promise.resolve(self:_get_dir_base(cursor))
      ---@param dir? string
      ---@return string | OrgPromise<string | nil>
      :next(function(dir)
        if dir then
          return dir
        end
        ---@return OrgPromise<string | nil> dir
        return preferred_method():next(function(method)
          if method == 'id' then
            local id = get_or_create_id_at_cursor(self.files, cursor)
            dir = self:get_dir_from_id(id)
            if not dir then
              return Promise.reject(string.format([[
Failed to get folder for id %s, adjust `org_attach_id_to_path_function_list']],
                id
              ))
            end
            return dir
          end
          if method == 'dir' then
            return self:set_directory()
          end
          return Promise.reject([[
No existing directory. DIR or ID property has to be explicitly created]])
        end)
      end)
      ---@param dir? string
      ---@return OrgPromise<string> dir
      :next(function(dir)
        if not dir then
          return Promise.reject('No attachment directory is associated with the current node')
        end
        return dir
      end)
      ---@param dir string
      ---@return OrgPromise<string> dir
      :next(function(dir)
        return Promise.new(function(resolve)
          local mode = 493 -- octal 0755 as decimal
          vim.uv.fs_mkdir(dir, mode, function()
            resolve(dir)
          end)
        end)
      end)
end

---Return existing or new directory associated with the current outline node.
---
---`org_attach_preferred_new_method` decides how to attach new directory if
---neither ID nor DIR property exist.
---
---If the attachment by some reason cannot be created an error will be raised.
---
---@param cursor? table (1, 0) indexed base position tuple
---@return string
function Attach:get_dir_or_create_sync(cursor)
  return self:get_dir_or_create(cursor):wait()
end

---Return a folder path based on `org_attach_id_dir` and ID.
---
---Try `id_to_path` functions in `org_attach_id_to_path_function_list`
---ignoring nils. If `existing` is true, then return the first path
---found in the filesystem. Otherwise return the first truthy value.
---
---@param id string node ID property to expand into a directory
---@param existing? boolean if true, return the first path found in the
---                         filesystem; otherwise return first truthy value.
---@return string? attach_dir
function Attach:get_dir_from_id(id, existing)
  local funcs = config.org_attach_id_to_path_function_list
  local basedir = fs_utils.substitute_path(config.org_attach_id_dir)
  local default_basedir = fs_utils.substitute_path('./data/')
  local preferred = nil
  local first = nil
  for _, func in ipairs(funcs) do
    local name = func(id)
    local candidate = basedir and vim.fs.joinpath(basedir, name)
    local candidate2 = default_basedir and vim.fs.joinpath(default_basedir, name)
    if candidate then
      if existing then
        if vim.fs.is_dir(candidate) then
          preferred = candidate
        elseif candidate2 and vim.fs.is_dir(candidate2) then
          preferred = candidate2
        end
      elseif not first then
        first = candidate
      end
    end
    if preferred then break end
  end
  return preferred or first
end

---Set the DIR node property and ask to move files there.
---The property defines the directory that is used for attachments
---of the entry. Creates relative links if `org_attach_dir_relative'
---is true.
---
---@param cursor? table (1, 0) indexed base position tuple
---@return OrgPromise<string> dir
function Attach:set_directory(cursor)
  ---@class OrgAttachSetDirectoryTask
  ---@field old? string
  ---@field new? string
  ---@field do_copy? boolean
  ---@field do_delete? boolean

  return self:get_dir(cursor):next(function(old_dir)
    ---@type OrgAttachSetDirectoryTask | nil
    return { old = old_dir }
  end):next(function(task)
    ---@cast task OrgAttachSetDirectoryTask
    return ui_utils.input({
          prompt = 'Attachment directory: ',
          default = get_property_at_cursor(self.files, 'DIR', false, cursor),
          completion = 'dir', ---@todo does this complete based on CWD?
        })
        :next(function(new_dir)
          ---@type OrgAttachSetDirectoryTask | nil
          return new_dir and vim.tbl_extend('error', task, {
            new = new_dir ~= '' and new_dir or nil
          })
        end)
  end):next(function(task)
    ---@cast task OrgAttachSetDirectoryTask | nil
    if not task or not task.old or not task.new or task.new == task.old then
      return task
    end
    local msg = ('Copy attachments from "%s" to "%s"? '):format(task.old, task.new)
    return ui_utils.yes_or_no_or_cancel_slow(msg)
        :next(function(choice)
          ---@cast task OrgAttachSetDirectoryTask | nil
          return choice and vim.tbl_extend('error', task, {
            do_copy = choice == 'yes',
          })
        end)
  end):next(function(task)
    ---@cast task OrgAttachSetDirectoryTask | nil
    if not task or not task.old or task.new == task.old then
      return task
    end
    local msg = ('Delete "%s"? '):format(task.old)
    return ui_utils.yes_or_no_or_cancel_slow(msg)
        :next(function(choice)
          ---@cast task OrgAttachSetDirectoryTask | nil
          return choice and vim.tbl_extend('error', task, {
            do_delete = choice == 'yes',
          })
        end)
  end):next(function(task)
    -- copy
    -- set
    -- delete
  end)
end

return Attach
