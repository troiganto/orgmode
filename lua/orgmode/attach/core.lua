local AttachNode = require('orgmode.attach.node')
local EventManager = require('orgmode.events')
local methods = require('orgmode.attach.methods')
local Promise = require('orgmode.utils.promise')
local config = require('orgmode.config')
local fileops = require('orgmode.attach.fileops')
local id_dir = require('orgmode.attach.id_dir')
local utils = require('orgmode.utils')

---@class OrgAttachCore
---@field files OrgFiles
---@field links OrgLinks
local AttachCore = {}
AttachCore.__index = AttachCore

---@param opts {files:OrgFiles, links:OrgLinks}
function AttachCore.new(opts)
  local data = {
    files = opts and opts.files,
    links = opts and opts.links,
  }
  return setmetatable(data, AttachCore)
end

---Get the current attachment node.
---
---@return OrgAttachNode
function AttachCore:get_current_node()
  return AttachNode.at_cursor(self.files:get_current_file())
end

---Get attachment node in a given file at a given position.
---
---@param file OrgFile
---@param cursor [integer, integer] The (1,0)-indexed cursor position in the buffer
---@return OrgAttachNode
function AttachCore:get_node(file, cursor)
  return AttachNode.at_cursor(file, cursor)
end

---Get an attachment node for an arbitrary window.
---
---An error occurs if the given window doesn't point at a loaded org file.
---
---@param winid integer window-ID or 0 for the current window
---@return OrgAttachNode
function AttachCore:get_node_by_winid(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local file = self.files:get(path)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  return AttachNode.at_cursor(file, cursor)
end

---Get all attachment nodes that are pointed at in a given buffer.
---
---If the buffer is not loaded, or if it's not an org file, this returns an
---empty list.
---
---If the buffer is loaded but hidden, this returns a table mapping from 0 to
---the only attachment node pointed at by the mark `"` (position at last exit
---from the buffer).
---
---If the buffer is active, this returns a table mapping from window-ID to
---attachment node containing the curser in that window. Note that two windows
---may point at the same attachment node.
---
---See `:help windows-intro` for terminology.
---
---@param bufnr integer
---@return OrgAttachNode[]
function AttachCore:get_nodes_by_buffer(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    -- Buffer is not loaded, no lines available.
    return {}
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local file = self.files:load_file_sync(path)
  if not file then
    -- Buffer is loaded, but not an org file.
    return {}
  end
  local windows = vim.fn.win_findbuf(bufnr)
  if #windows == 0 then
    -- Org file is loaded but hidden.
    local cursor = vim.api.nvim_buf_get_mark(bufnr, '"')
    return { AttachNode.at_cursor(file, cursor) }
  end
  -- Org file is active, collect all windows.
  -- Because all nodes are in the same buffer, we use the fact that their
  -- starting-line numbers are unique. This lets us deduplicate multiple
  -- windows that show the same node.
  local nodes = {} ---@type table<integer, OrgAttachNode>
  for _, winid in ipairs(windows) do
    local cursor = vim.api.nvim_win_get_cursor(winid)
    local node = AttachNode.at_cursor(file, cursor)
    nodes[node:get_start_line()] = node
  end
  return vim.tbl_values(nodes)
end

---Like `get_nodes_by_buffer()`, but only accept an unambiguous result.
---
---If the buffer is displayed in multiple windows, *and* those windows have
---their cursors at different attachment nodes, return nil.
---
---@param bufnr integer
---@return OrgAttachNode|nil
function AttachCore:get_single_node_by_buffer(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    -- Buffer is not loaded, no lines available.
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local file = self.files:load_file_sync(path)
  if not file then
    -- Buffer is loaded, but not an org file.
    return
  end
  local windows = vim.fn.win_findbuf(bufnr)
  if #windows == 0 then
    -- Org file is loaded but hidden.
    local cursor = vim.api.nvim_buf_get_mark(bufnr, '"')
    return AttachNode.at_cursor(file, cursor)
  end
  -- Org file is active.
  local node, start_line
  for _, winid in ipairs(windows) do
    local cursor = vim.api.nvim_win_get_cursor(winid)
    if not node then
      node = AttachNode.at_cursor(file, cursor)
    else
      -- Multiple nodes; continue if they are the same, otherwise break.
      start_line = start_line or node:get_start_line()
      local next_node = AttachNode.at_cursor(file, cursor)
      if start_line ~= next_node:get_start_line() then
        return
      end
    end
  end
  return node
end

---List attachment nodes across buffers.
---
---By default, the result includes all nodes pointed at by a cursor in
---a window. If `include_hidden` is true, the result also includes buffers that
---are loaded but hidden. In their case, the node that contains the `"` mark is
---used.
---
---@param opts? { include_hidden?: boolean }
---@return OrgAttachNode[]
function AttachCore:list_current_nodes(opts)
  local nodes = {} ---@type OrgAttachNode[]
  local seen_bufs = {} ---@type table<integer, true>
  for _, winid in vim.api.nvim_list_wins() do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local path = vim.api.nvim_buf_get_name(bufnr)
    local file = self.files:load_file_sync(path)
    if file then
      local cursor = vim.api.nvim_win_get_cursor(winid)
      nodes[#nodes + 1] = AttachNode.at_cursor(file, cursor)
    end
    seen_bufs[bufnr] = true
  end
  local include_hidden = opts and opts.include_hidden or false
  if include_hidden then
    for _, bufnr in vim.api.nvim_list_bufs() do
      if vim.api.nvim_buf_is_loaded(bufnr) and not seen_bufs[bufnr] then
        local path = vim.api.nvim_buf_get_name(bufnr)
        local file = self.files:load_file_sync(path)
        if file then
          -- Hidden buffers don't have cursors, only windows do; use the next
          -- best thing instead, the position when last exited.
          local cursor = vim.api.nvim_buf_get_mark(bufnr, '"')
          nodes[#nodes + 1] = AttachNode.at_cursor(file, cursor)
        end
      end
    end
  end
  return nodes
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
---@param node OrgAttachNode
---@param no_fs_check? boolean if true, return the directory even if it doesn't
---                            exist
---@return string|nil attach_dir
function AttachCore:get_dir_or_nil(node, no_fs_check)
  local dir = node:get_dir()
  return dir and (no_fs_check or vim.fs.is_dir(dir)) and dir or nil
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
---@param node OrgAttachNode
---@param no_fs_check? boolean if true, return the directory even if it doesn't
---                            exist
---@return string attach_dir
function AttachCore:get_dir(node, no_fs_check)
  return self:get_dir_or_nil(node, no_fs_check)
      or error('No attachment directory for this node')
end

---@generic T
---@alias orgmode.attach.core.thunk `T` | fun(): T

---@generic T
---@param f `T` | fun(...): T
---@return T
local function thunk(f, ...)
  if vim.is_callable(f) then
    return f(...)
  end
  return f
end

---@alias orgmode.attach.core.new_method 'id' | 'dir'

---Return existing or new directory associated with the current outline node.
---
---`org_attach_preferred_new_method` decides how to attach new directory if
---neither ID nor DIR property exist.
---
---If the attachment by some reason cannot be created an error will be raised.
---
---@param node OrgAttachNode
---@param method orgmode.attach.core.new_method | fun(): orgmode.attach.core.new_method
---@param new_dir string | fun(): string
---@return string
function AttachCore:get_dir_or_create(node, method, new_dir)
  local dir = self:get_dir_or_nil(node) -- free `is_dir()` check
  if dir then
    return dir
  end
  method = thunk(method)
  if method == 'id' then
    local id = node:id_get_or_create()
    dir = id_dir.get_from_id(id)
    if not dir then
      error(('Failed to get folder for id %s, adjust `%s'):format(id, 'org_attach_id_to_path_function_list'))
    end
  elseif method == 'dir' then
    dir = node:set_dir(thunk(new_dir))
    ---@todo figure out how and where to resolve `dir`!
  else
    error(('unknown method: %s'):format(method))
  end
  local mode = 493 -- octal 0755 as decimal
  fileops.make_dir(dir, { mode = mode, parents = true, exist_ok = true }):wait()
  return dir
end

---@class orgmode.attach.core.set_directory.opts
---@field do_copy boolean | fun(old: string, new: string): boolean
---@field do_delete boolean | fun(old: string): boolean

---Set the DIR node property and ask to move files there.
---
---The property defines the directory that is used for attachments
---of the entry. Creates relative links if `org_attach_dir_relative'
---is true.
---
---@param node OrgAttachNode
---@param new_dir string
---@param opts orgmode.attach.core.set_directory.opts
---@return OrgPromise<string | nil> new_dir
function AttachCore:set_directory(node, new_dir, opts)
  local old_dir = node:get_dir()
  local do_copy = old_dir and thunk(opts.do_copy, old_dir, new_dir)
  local do_delete = old_dir and thunk(opts.do_delete, old_dir)
  -- Some checks are duplicated, but it keeps the code straightforward and the
  -- type checker happy.
  return Promise.resolve(old_dir and new_dir and do_copy and fileops.copy_directory(old_dir, new_dir, {
    parents = true,
    keep_times = true,
    create_symlink = config.org_attach_copy_directory_create_symlink,
  })):next(function()
    node:set_dir(new_dir)
    return Promise.resolve(old_dir and do_delete and fileops.remove_directory(old_dir, { recursive = true }))
  end)
end

---Remove DIR node property.
---
---If attachment folder is changed due to removal of DIR-property
---ask to move attachments to new location and ask to delete old
---attachment folder.
---
---Change of attachment-folder due to unset might be if an ID
---property is set on the node, or if a separate inherited
---DIR-property exists (that is different from the unset one).
---
---@param node OrgAttachNode
---@param opts orgmode.attach.core.set_directory.opts
---@return OrgPromise<string | nil> new_dir
function AttachCore:unset_directory(node, opts)
  local old_dir = node:get_dir()
  node:set_dir()
  local new_dir = node:get_dir() -- new dir potentially via parent nodes
  local do_copy = old_dir and new_dir and thunk(opts.do_copy, old_dir, new_dir)
  local do_delete = old_dir and thunk(opts.do_delete, old_dir)
  -- Some checks are duplicated, but it keeps the code straightforward and the
  -- type checker happy.
  return Promise.resolve(old_dir and new_dir and do_copy and fileops.copy_directory(old_dir, new_dir, {
    parents = true,
    keep_times = true,
    create_symlink = config.org_attach_copy_directory_create_symlink,
  })):next(function()
    return Promise.resolve(old_dir and do_delete and fileops.remove_directory(old_dir, { recursive = true }))
  end)
end

---Turn the autotag on.
---
---If autotagging is disabled, this does nothing.
---
---@param node OrgAttachNode
---@return nil
function AttachCore:tag(node)
  node:toggle_auto_tag(true)
end

---Turn the autotag off.
---
---If autotagging is disabled, this does nothing.
---
---@param node OrgAttachNode
---@return nil
function AttachCore:untag(node)
  node:toggle_auto_tag(false)
end

---Helper to the `attach_*()` functions.
---Like `vim.fs.basename()` but reject an empty string result.
---This also ignores trailing slashes, e.g.:
---* '/foo/bar' -> 'bar'
---* '/foo/' -> 'foo'
---* '/' -> error!
---@param path string
---@return string basename
local function basename_safe(path)
  local match = path:match('^(.*[^/])/*$')
  local basename = match and vim.fs.basename(match)
  return basename ~= '' and basename or error('cannot determine attachment name: ' .. path)
end

---@alias OrgAttachMethod 'cp' | 'mv' | 'ln' | 'lns'

---@class orgmode.attach.core.attach.opts
---@inlinedoc
---@field attach_method OrgAttachMethod
---@field set_dir_method orgmode.attach.core.new_method | fun(): orgmode.attach.core.new_method
---@field new_dir string | fun(): string

---Move/copy/link file into attachment directory of the current outline node.
---
---@param node OrgAttachNode
---@param file string The file to attach
---@param opts orgmode.attach.core.attach.opts
---@return OrgPromise<string|nil> attachment_name
function AttachCore:attach(node, file, opts)
  local basename = basename_safe(file)
  local attach = methods.get_file_attacher(opts.attach_method)
  local attach_dir = self:get_dir_or_create(node, opts.set_dir_method, opts.new_dir)
  local attach_file = vim.fs.joinpath(attach_dir, basename)
  return attach(file, attach_file):next(function(success)
    if not success then
      return nil
    end
    EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
    node:toggle_auto_tag(true)
    local link = self.links:store_link_to_attachment({ attach_dir = attach_dir, original = file })
    vim.fn.setreg(vim.v.register, link)
    return basename
  end)
end

---@class orgmode.attach.core.attach_url.opts
---@inlinedoc
---@field set_dir_method orgmode.attach.core.new_method | fun(): orgmode.attach.core.new_method
---@field new_dir string | fun(): string

---Move/copy/link file into attachment directory of the current outline node.
---
---@param node OrgAttachNode
---@param url string URL to the file to attach
---@param opts orgmode.attach.core.attach_url.opts
---@return OrgPromise<string|nil> attachment_name
function AttachCore:attach_url(node, url, opts)
  local basename = basename_safe(url)
  local attach_dir = self:get_dir_or_create(node, opts.set_dir_method, opts.new_dir)
  local attach_file = vim.fs.joinpath(attach_dir, basename)
  return methods.attach_url(url, attach_file):next(function(success)
    if not success then
      return nil
    end
    EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
    node:toggle_auto_tag(true)
    local link = self.links:store_link_to_attachment({ attach_dir = attach_dir, original = url })
    vim.fn.setreg(vim.v.register, link)
    return basename
  end)
end

---@alias orgmode.attach.core.attach_buffer.opts orgmode.attach.core.attach_url.opts

---Attach buffer's contents to current outline node.
---
---Throws a file-exists error if it would overwrite an existing filename.
---
---@param node OrgAttachNode
---@param bufnr integer
---@param opts orgmode.attach.core.attach_buffer.opts
---@return OrgPromise<string|nil> attachment_name
function AttachCore:attach_buffer(node, bufnr, opts)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local basename = basename_safe(bufname)
  local attach_dir = self:get_dir_or_create(node, opts.set_dir_method, opts.new_dir)
  local attach_file = vim.fs.joinpath(attach_dir, basename)
  return methods.attach_buffer(bufnr, attach_file):next(function(success)
    if not success then
      return nil
    end
    return fileops.exists(bufname):next(function(bufname_exists)
      EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
      node:toggle_auto_tag(true)
      local link = self.links:store_link_to_attachment({
        attach_dir = attach_dir,
        original = bufname_exists and bufname or attach_file,
      })
      vim.fn.setreg(vim.v.register, link)
      return basename
    end)
  end)
end

---@class orgmode.attach.core.attach_many.result
---@field successes integer
---@field failures integer

---Move/copy/link many files into attachment directory.
---
---@param node OrgAttachNode
---@param files string[]
---@param opts orgmode.attach.core.attach.opts
---@return OrgPromise<orgmode.attach.core.attach_many.result> tally
function AttachCore:attach_many(node, files, opts)
  local attach = methods.get_file_attacher(opts.attach_method)
  ---@type orgmode.attach.core.attach_many.result
  local initial_tally = { successes = 0, failures = 0 }
  if #files == 0 then
    return Promise.resolve(initial_tally)
  end
  local attach_dir = self:get_dir_or_create(node, opts.set_dir_method, opts.new_dir)
  return Promise
      .map(function(to_be_attached)
        local basename = basename_safe(to_be_attached)
        local attach_file = vim.fs.joinpath(attach_dir, basename)
        return attach(to_be_attached, attach_file):next(function(success)
          self.links:store_link_to_attachment({ attach_dir = attach_dir, original = to_be_attached })
          return success
        end)
      end, files, 1)
      ---@param successes boolean[]
      :next(function(successes)
        EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
        node:toggle_auto_tag(true)
        ---@param tally orgmode.attach.core.attach_many.result
        ---@param success boolean
        ---@return orgmode.attach.core.attach_many.result tally
        return utils.reduce(successes, function(tally, success)
          if success then
            tally.successes = tally.successes + 1
          else
            tally.failures = tally.failures + 1
          end
          return tally
        end, initial_tally)
      end)
end

---@class orgmode.attach.core.attach_new.opts
---@inlinedoc
---@field set_dir_method orgmode.attach.core.new_method | fun(): orgmode.attach.core.new_method
---@field new_dir string | fun(): string
---@field enew_bang boolean
---@field enew_mods table<string,any>

---Create a new attachment FILE for the current outline node.
---
---The attachment is opened as a new buffer.
---
---@param node OrgAttachNode
---@param name string
---@param opts orgmode.attach.core.attach_new.opts
---@return OrgPromise<string|nil> attachment_name
function AttachCore:attach_new(node, name, opts)
  local attach_dir = self:get_dir_or_create(node, opts.set_dir_method, opts.new_dir)
  local path = vim.fs.joinpath(attach_dir, name)
  --TODO: the emacs version doesn't run the hook here. Is this correct?
  EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
  node:toggle_auto_tag(true)
  return fileops.exists(path):next(function(already_exists)
    if already_exists then
      return Promise.reject('EEXIST: ' .. path)
    end
    ---@type vim.api.keyset.cmd
    local cmd = { cmd = 'enew', args = { path }, bang = opts.enew_bang, mods = opts.enew_mods }
    return Promise.new(function(resolve, reject)
      local ok, err = pcall(vim.api.nvim_cmd, cmd, {})
      if ok then
        resolve(name)
      else
        reject(err)
      end
    end)
  end)
end

---@param attach_dir string the directory to open
---@return nil
function AttachCore:reveal(attach_dir)
  local res = assert(vim.ui.open(attach_dir)):wait()
  if res.code ~= 0 then
    error(res.stderr)
  end
end

---@param attach_dir string the directory to open
---@return nil
function AttachCore:reveal_nvim(attach_dir)
  local command = config.org_attach_visit_command or 'edit'
  if type(command) == 'string' then
    vim.cmd(command)
  else
    command(attach_dir)
  end
end

---@param node OrgAttachNode
---@param name string name of the file to open
---@return nil
function AttachCore:open(name, node)
  local attach_dir = self:get_dir(node)
  local path = vim.fs.joinpath(attach_dir, name)
  EventManager.dispatch(EventManager.event.AttachOpened:new(node, path))
  local res = assert(vim.ui.open(path)):wait()
  if res.code ~= 0 then
    error(res.stderr)
  end
end

---@param node OrgAttachNode
---@param name string name of the file to open
---@return nil
function AttachCore:open_in_vim(name, node)
  local attach_dir = self:get_dir(node)
  local path = vim.fs.joinpath(attach_dir, name)
  EventManager.dispatch(EventManager.event.AttachOpened:new(node, path))
  vim.cmd.edit(path)
end

---Delete a single attachment.
---
---@param node OrgAttachNode
---@param name string the name of the attachment to delete
---@return OrgPromise<nil>
function AttachCore:delete_one(node, name)
  local attach_dir = self:get_dir(node)
  local path = vim.fs.joinpath(attach_dir, name)
  return fileops.unlink(path):next(function()
    EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
    return nil
  end)
end

---Delete all attachments from the current outline node.
---
---This actually deletes the entire attachment directory. A safer way is to
---open the directory with `reveal` and delete from there.
---
---@param node OrgAttachNode
---@param recursive boolean | fun():boolean
---@return OrgPromise<string> deleted_dir
function AttachCore:delete_all(node, recursive)
  local attach_dir = self:get_dir(node)
  -- A few synchronous FS operations here, can't really be avoided. The
  -- alternative would be to evaluate `recursive` before it's necessary.
  local uv = vim.uv or vim.loop
  local ok, errmsg, err = uv.fs_unlink(attach_dir)
  if ok then
    return Promise.resolve()
  elseif err ~= 'EISDIR' then
    error(errmsg)
  end
  ok, errmsg, err = uv.fs_rmdir(attach_dir)
  if ok then
    return Promise.resolve()
  elseif err ~= 'ENOTEMPTY' then
    error(errmsg)
  end
  recursive = thunk(recursive)
  if not recursive then
    error(errmsg)
  end
  return fileops.remove_directory(attach_dir, { recursive = true })
      :next(function()
        EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
        node:toggle_auto_tag(false)
        return attach_dir
      end)
end

---@param directory string
---@return boolean
local function has_any_non_litter_files(directory)
  for name in fileops.iterdir(directory) do
    if not vim.endswith(name, '~') then
      return true
    end
  end
  return false
end

---Synchronize the current outline node with its attachments.
---
---Useful after files have been added/removed externally. The Option
---`org_attach_sync_delete_empty_dir` controls the behavior for empty
---attachment directories. (This ignores files whose name ends with
---a tilde `~`.)
---
---@param node OrgAttachNode
---@param delete_empty_dir boolean|fun(): boolean
---@return OrgPromise<string|nil> attach_dir_if_deleted
function AttachCore:sync(node, delete_empty_dir)
  local attach_dir = self:get_dir_or_nil(node)
  if not attach_dir then
    self:untag(node)
    return Promise.resolve()
  end
  EventManager.dispatch(EventManager.event.AttachChanged:new(node, attach_dir))
  node:toggle_auto_tag(has_any_non_litter_files(attach_dir))
  delete_empty_dir = thunk(delete_empty_dir)
  if not delete_empty_dir then
    return Promise.resolve()
  end
  return fileops.remove_directory(attach_dir, { recursive = true })
      :next(function()
        return attach_dir
      end)
end

---@param file OrgFile
---@param callback fun(attach_dir: string|false, basename: string): string|nil
---@return OrgPromise<nil>
function AttachCore:on_every_attachment_link(file, callback)
  -- TODO: In a better world, this would use treesitter for parsing ...
  return file:update(function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local prev_node = nil ---@type OrgAttachNode | nil
    local attach_dir = nil ---@type string | false | nil
    for i, line in ipairs(lines) do
      -- Check if node has changed; if yes, invalidate cached attach_dir.
      local node = AttachNode.at_cursor(file, { i + 1, 0 })
      if node ~= prev_node then
        attach_dir = nil
      end
      ---@param basename string
      ---@param bracket '[' | ']'
      ---@return string
      local replaced = line:gsub('%[%[attachment:([^%]]+)%]([%[%]])', function(basename, bracket)
        -- Only compute attach_dir when we know that we need it!
        if attach_dir == nil then
          attach_dir = self:get_dir_or_nil(node, true) or false
        end
        local res = callback(attach_dir, basename)
        return res
            and ('[[%s]%s'):format(res, bracket)
            or ('[[attachment:%s]%s'):format(basename, bracket)
      end)
      if replaced ~= line then
        vim.api.nvim_buf_set_lines(0, i - 1, i, true, { replaced })
      end
      prev_node = node
    end
  end)
end

return AttachCore
