local AttachNode = require('orgmode.attach.node')
local EventManager = require('orgmode.events')
local Menu = require('orgmode.ui.menu')
local Promise = require('orgmode.utils.promise')
local config = require('orgmode.config')
local fsops = require('orgmode.attach.fsops')
local remote_resource = require('orgmode.objects.remote_resource')
local ui_utils = require('orgmode.attach.ui')
local utils = require('orgmode.utils')
local Core = require('orgmode.attach.core')

local MAX_TIMEOUT = 2 ^ 31

---@class OrgAttach
---@field private core OrgAttachCore
local Attach = {}
Attach.__index = Attach

---@param opts {files:OrgFiles, links:OrgLinks}
function Attach:new(opts)
  local data = setmetatable({ core = Core.new(opts) }, self)
  data.core.links:add_type(require('orgmode.org.links.types.attachment'):new({ attach = data }))
  return data
end

---@return orgmode.attach.core.new_method | fun(): orgmode.attach.core.new_method
local function get_set_dir_method()
  local method = config.org_attach_preferred_new_method
  if not method then
    error('No existing directory. DIR or ID property has to be explicitly created')
  end
  if method == 'id' or method == 'dir' then
    return method --[[@type 'id'|'dir']]
  end
  if method ~= 'ask' then
    error(('invalid value for org_attach_preferred_new_method: %s'):format(method))
  end
  return function()
    local menu = Menu:new({ title = 'How to create attachments directory?', prompt = 'Select method' })
    menu:add_option({
      key = 'i',
      label = 'Create new ID property',
      action = function()
        return 'id'
      end,
    })
    menu:add_option({
      key = 'd',
      label = 'Create new DIR property',
      action = function()
        return 'dir'
      end,
    })
    ---@type 'id'|'dir'
    return assert(menu:open(), 'Cancelled')
  end
end

---@param prev_dir string | nil
---@return string
local function get_new_dir_prop(prev_dir)
  local new_dir = vim.fn.input('Attachment directory', prev_dir or '', 'dir')
  if not new_dir or new_dir == '' then
    error('Cancelled')
  end
  return new_dir
end

---@param msg string
---@return 'yes'|'no'|nil choice
local function yes_or_no_or_cancel_slow(msg)
  local answer
  repeat
    ---@type string | nil
    answer = vim.fn.input(msg .. '(yes or no, ESC to cancel) ')
    answer = answer and answer:lower()
  until answer == 'yes' or answer == 'no'
  return answer
end

---Like `vim.fn.bufnr()`, but print a warning on failure.
---@param buf integer | string
---@return integer | nil bufnr
local function get_bufnr_verbose(buf)
  local bufnr = vim.fn.bufnr(buf)
  if bufnr ~= -1 then
    return bufnr
  end
  -- bufnr() failed, was there no match or more than one?
  if type(buf) == 'string' then
    local matches = vim.fn.getcompletion(buf, 'buffer')
    if #matches > 1 then
      utils.echo_warning('more than one match for ' .. tostring(buf))
      return
    end
    if #matches == 1 then
      -- Surprise match?!
      bufnr = vim.fn.bufnr(matches[1])
      if bufnr > 0 then
        return bufnr
      end
    end
    utils.echo_warning('no matching buffer for ' .. tostring(buf))
    return
  end
  utils.echo_warning(('buffer %d does not exist'):format(buf))
end

---@return integer | nil bufnr
local function select_buffer()
  local choice = vim.fn.input('Select a buffer: ', '', 'buffer')
  return choice and vim.fn.bufnr(choice)
end

---@param nodes OrgAttachNode[]
---@return OrgAttachNode selection
local function select_node(nodes)
  ---@param arglead string
  ---@return OrgAttachNode[]
  local function get_matches(arglead)
    return vim.fn.matchfuzzy(nodes, arglead, { matchseq = true, text_cb = AttachNode.get_title })
  end
  ---@type string|nil
  local choice = vim.fn.OrgmodeInput('Select an attachment node: ', '', get_matches)
  if not choice then
    error('Cancelled')
  end
  local matches = get_matches(choice)
  if #matches == 1 then
    return matches[1]
  end
  if #matches > 1 then
    error('more than one match for ' .. tostring(choice))
  else
    error('no matching buffer for ' .. tostring(choice))
  end
end

---@param opts? orgmode.attach.attach_to_other_buffer.Options
---@return OrgAttachNode
function Attach:find_other_node(opts)
  local window = opts and opts.window
  local ask = opts and opts.ask
  local prefer_recent = opts and opts.prefer_recent
  local include_hidden = opts and opts.include_hidden or false
  if window then
    return self:get_node_by_window(window)
  end
  if prefer_recent then
    local ok, node = pcall(self.core.get_current_node, self.core)
    if ok then return node end
    local altbuf_nodes, altwin_node
    if prefer_recent == 'buffer' then
      altbuf_nodes = self.core:get_single_node_by_buffer(vim.fn.bufnr('#'))
      if altbuf_nodes then return altbuf_nodes end
      ok, altwin_node = pcall(self.get_node_by_window, self, '#')
      if ok then return altwin_node end
    elseif prefer_recent == 'window' then
      ok, altwin_node = pcall(self.get_node_by_window, self, '#')
      if ok then return altwin_node end
      altbuf_nodes = self.core:get_single_node_by_buffer(vim.fn.bufnr('#'))
      if altbuf_nodes then return altbuf_nodes end
    else
      local altbuf = vim.fn.bufnr('#')
      local altwin = vim.fn.win_getid(vim.fn.winnr('#'))
      -- altwin falls back to current window if previous window doesn't exist;
      -- that's fine, we've handled it earlier.
      ok, altwin_node = pcall(self.core.get_node_by_winid, self.core, altwin)
      altwin_node = ok and altwin_node or nil
      altbuf_nodes = self.core:get_nodes_by_buffer(altbuf)
      if altwin_node and (#altbuf_nodes == 0 or vim.api.nvim_win_get_buf(altwin) == altbuf) then
        return altwin_node
      end
      if #altbuf_nodes == 1 and not altwin_node then
        return altbuf_nodes[1]
      end
      if prefer_recent == 'ask' then
        local candidates = altbuf_nodes
        if altwin_node then
          table.insert(candidates, 1, altwin_node)
        end
        return select_node(candidates)
      end
      -- More than one possible attachment location and not asking; fall back
      -- to regular behavior.
    end
  end
  local candidates = self.core:list_current_nodes({ include_hidden = include_hidden })
  if #candidates == 0 then
    error('nowhere to attach to')
  end
  if ask == 'always' then
    return select_node(candidates)
  end
  if ask == 'multiple' then
    if #candidates == 1 then
      return candidates[1]
    end
    return select_node(candidates)
  end
  if ask then
    error(('invalid value for ask: %s'):format(ask))
  end
  if #candidates == 1 then
    return candidates[1]
  end
  error('more than one possible attachment location')
end

---The dispatcher for attachment commands.
---Shows a list of commands and prompts for another key to execute a command.
---@return nil
function Attach:prompt()
  local menu = Menu:new({
    title = 'Press key for an attach command',
    prompt = 'Press key for an attach command',
  })

  menu:add_option({
    label = 'Select a file and attach it to the task.',
    key = 'a',
    action = function()
      return self:attach()
    end,
  })
  menu:add_option({
    label = 'Attach a file using copy method.',
    key = 'c',
    action = function()
      return self:attach_cp()
    end,
  })
  menu:add_option({
    label = 'Attach a file using move method.',
    key = 'm',
    action = function()
      return self:attach_mv()
    end,
  })
  menu:add_option({
    label = 'Attach a file using link method.',
    key = 'l',
    action = function()
      return self:attach_ln()
    end,
  })
  menu:add_option({
    label = 'Attach a file using symbolic-link method.',
    key = 'y',
    action = function()
      return self:attach_lns()
    end,
  })
  menu:add_option({
    label = 'Attach a file from URL (downloading it).',
    key = 'u',
    action = function()
      return self:attach_url()
    end,
  })
  menu:add_option({
    label = 'Select a buffer and attach its contents to the task.',
    key = 'b',
    action = function()
      return self:attach_buffer()
    end,
  })
  menu:add_option({
    label = 'Create a new attachment, as a vim buffer.',
    key = 'n',
    action = function()
      return self:attach_new()
    end,
  })
  menu:add_option({
    label = 'Synchronize current node with its attachment directory.',
    key = 'z',
    action = function()
      return self:sync()
    end,
  })
  menu:add_option({
    label = "Open current node's attachments.",
    key = 'o',
    action = function()
      return self:open()
    end,
  })
  menu:add_option({
    label = "Open current node's attachments in vim.",
    key = 'O',
    action = function()
      return self:open_in_vim()
    end,
  })
  menu:add_option({
    label = "Open current node's attachment directory. Create if missing.",
    key = 'f',
    action = function()
      return self:reveal()
    end,
  })
  menu:add_option({
    label = "Open current node's attachment directory in vim.",
    key = 'F',
    action = function()
      return self:reveal_nvim()
    end,
  })
  menu:add_option({
    label = 'Select and delete one attachment',
    key = 'd',
    action = function()
      return self:delete_one()
    end,
  })
  menu:add_option({
    label = 'Delete all attachments of the current node.',
    key = 'D',
    action = function()
      return self:delete_all()
    end,
  })
  menu:add_option({
    label = 'Set specific attachment directory for current node.',
    key = 's',
    action = function()
      return self:set_directory()
    end,
  })
  menu:add_option({
    label = 'Unset specific attachment directory for current node.',
    key = 'S',
    action = function()
      return self:unset_directory()
    end,
  })
  menu:add_option({ label = 'Quit', key = 'q' })
  menu:add_separator({ icon = ' ', length = 1 })

  return menu:open()
end

---Get the current attachment node.
---
---@return OrgAttachNode
function Attach:get_current_node()
  return self.core:get_current_node()
end

---Get attachment node in a given file at a given position.
---
---@param file OrgFile
---@param cursor [integer, integer] The (1,0)-indexed cursor position in the buffer
---@return OrgAttachNode
function Attach:get_node(file, cursor)
  return self.core:get_node(file, cursor)
end

---Get attachment node pointed at in a window
---
---@param window? integer | string window-ID, window number or any argument
---                                accepted by `winnr()`; if 0 or nil, use the
---                                current window
---@return OrgAttachNode
function Attach:get_node_by_window(window)
  local winid
  if not window or window == 0 then
    winid = vim.api.nvim_get_current_win()
  elseif type(window) == 'string' then
    winid = vim.fn.win_getid(vim.fn.winnr(window))
  elseif vim.fn.win_id2win(window) ~= 0 then
    winid = window
  else
    winid = vim.fn.win_getid(window)
  end
  if winid == 0 then
    error(('invalid window: %s'):format(window))
  end
  return self.core:get_node_by_winid(winid)
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
---@param node? OrgAttachNode
---@param no_fs_check? boolean if true, return the directory even if it doesn't
---                            exist
---@return string|nil attach_dir
function Attach:get_dir(node, no_fs_check)
  node = node or self.core:get_current_node()
  return self.core:get_dir_or_nil(node, no_fs_check)
end

---Return existing or new directory associated with the current outline node.
---
---`org_attach_preferred_new_method` decides how to attach new directory if
---neither ID nor DIR property exist.
---
---If the attachment by some reason cannot be created an error will be raised.
---
---@param node? OrgAttachNode
---@return string
function Attach:get_dir_or_create(node)
  node = node or self.core:get_current_node()
  return self.core:get_dir_or_create(node, get_set_dir_method(), get_new_dir_prop)
end

---Set the DIR node property and ask to move files there.
---
---The property defines the directory that is used for attachments
---of the entry. Creates relative links if `org_attach_dir_relative'
---is true.
---
---@param node? OrgAttachNode
---@return string | nil new_dir
function Attach:set_directory(node)
  node = node or self.core:get_current_node()
  local new_dir = get_new_dir_prop(node:get_dir())
  return self.core
      :set_directory(node, new_dir, {
        do_copy = function(old, new)
          local answer = yes_or_no_or_cancel_slow(('Copy attachments from "%s" to "%s"? '):format(old, new))
          if answer == 'yes' then
            return true
          end
          if answer == 'no' then
            return false
          end
          error('Cancelled')
        end,
        do_delete = function(old)
          local answer = yes_or_no_or_cancel_slow(('Delete "%s"? '):format(old))
          if answer == 'yes' then
            return true
          end
          if answer == 'no' then
            return false
          end
          error('Cancelled')
        end,
      })
      :wait(MAX_TIMEOUT)
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
---@param node? OrgAttachNode
---@return string | nil new_dir
function Attach:unset_directory(node)
  node = node or self.core:get_current_node()
  return self.core
      :unset_directory(node, {
        do_copy = function(old, new)
          local answer = yes_or_no_or_cancel_slow(('Copy attachments from "%s" to "%s"? '):format(old, new))
          if answer == 'yes' then
            return true
          end
          if answer == 'no' then
            return false
          end
          error('Cancelled')
        end,
        do_delete = function(old)
          local answer = yes_or_no_or_cancel_slow(('Delete "%s"? '):format(old))
          if answer == 'yes' then
            return true
          end
          if answer == 'no' then
            return false
          end
          error('Cancelled')
        end,
      })
      :wait(MAX_TIMEOUT)
end

---@param directory string
---@param show_hidden? boolean
local function list_files(directory, show_hidden)
  ---@param path string
  ---@return string ftype
  local function resolve_links(path)
    local target = vim.uv.fs_realpath(path)
    local stat = target and vim.uv.fs_stat(target)
    return stat and stat.type or 'file'
  end
  local filter = show_hidden and function()
    return true
  end or function(name)
    return not vim.startswith(name, '.') and not vim.endswith(name, '~')
  end
  local res = {}
  local files = {}
  for name, ftype in fsops.iterdir(directory) do
    if filter(name) then
      if ftype == 'link' then
        ftype = resolve_links(vim.fs.joinpath(directory, name))
      end
      if ftype == 'directory' then
        res[#res + 1] = name .. '/'
      else
        files[#files + 1] = name
      end
    end
  end
  table.sort(res)
  table.sort(files)
  return vim.list_extend(res, files)
end

---Return a completion function for attachments.
---
---You should pass either `dir` or `node`. If you pass both, `dir` takes
---precedence. If you pass `node`, its attachment directory is used. If it
---doesn't have one, an error occurs and no completion function is returned.
---@param opts? {dir?: string, node?: OrgAttachNode}
---@return fun(arglead: string): string[]
function Attach:make_completion(opts)
  local root = opts and opts.dir
      or self:get_dir(opts and opts.node)
      or error('No attachment directory for this node')
  ---@param arglead string
  ---@return string[]
  return function(arglead)
    local dirname = vim.fs.dirname(arglead)
    local searchdir = vim.fs.normalize(vim.fs.joinpath(root, dirname))
    local basename = vim.fs.basename(arglead)
    local show_hidden = vim.startswith(basename, '.')
    local candidates = list_files(searchdir, show_hidden)
    -- Only call matchfuzzy() if it won't break.
    if basename ~= '' and basename:len() <= 256 then
      candidates = vim.fn.matchfuzzy(candidates, basename)
    end
    -- Don't prefix `./` to the paths.
    if searchdir ~= '.' then
      candidates = vim.tbl_map(function(name)
        return vim.fs.joinpath(searchdir, name)
      end, candidates)
    end
    return candidates
  end
end

---Turn the autotag on.
---
---If autotagging is disabled, this does nothing.
---
---@param node? OrgAttachNode
---@return nil
function Attach:tag(node)
  self.core:tag(node or self.core:get_current_node())
end

---Turn the autotag off.
---
---If autotagging is disabled, this does nothing.
---
---@param node? OrgAttachNode
---@return nil
function Attach:untag(node)
  self.core:untag(node or self.core:get_current_node())
end

---@class orgmode.attach.attach.Options
---@inlinedoc
---@field visit_dir? boolean if true, visit the directory subsequently using
---                          `org_attach_visit_command`
---@field method? OrgAttachMethod The method via which to attach `file`;
---                               default is taken from `org_attach_method`
---@field node? OrgAttachNode

---Move/copy/link file into attachment directory of the current outline node.
---
---@param file? string The file to attach.
---@param opts? orgmode.attach.attach.Options
---@return string|nil attachment_name
function Attach:attach(file, opts)
  local node = opts and opts.node or self.core:get_current_node()
  local visit_dir = opts and opts.visit_dir or false
  local method = opts and opts.method or config.org_attach_method
  ---@type string|nil
  file = file or vim.fn.input('File to keep as an attachment: ', '', 'file')
  if not file then
    error('Cancelled')
  end
  return self.core
      :attach(node, file, {
        attach_method = method,
        set_dir_method = get_set_dir_method(),
        new_dir = get_new_dir_prop,
      })
      :next(function(attachment_name)
        if attachment_name then
          utils.echo_info(('File %s is now an attachment'):format(attachment_name))
          if visit_dir then
            local attach_dir = self.core:get_dir(node)
            self.core:reveal_nvim(attach_dir)
          end
        end
        return attachment_name
      end)
      :wait(MAX_TIMEOUT)
end

---@class orgmode.attach.attach_url.Options
---@inlinedoc
---@field visit_dir? boolean if true, visit the directory subsequently using
---                          `org_attach_visit_command`
---@field node? OrgAttachNode

---Download a URL.
---
---@param url? string
---@param opts? orgmode.attach.attach_url.Options
---@return string|nil attachment_name
function Attach:attach_url(url, opts)
  if url and not remote_resource.should_fetch(url) then
    error(("remote resource %s is unsafe, won't download"):format(url))
  elseif not url then
    url = vim.fn.input('URL of the file to attach: ')
  end
  if not url then
    error('Cancelled')
  end
  local node = opts and opts.node or self.core:get_current_node()
  local visit_dir = opts and opts.visit_dir or false
  return self.core
      :attach_url(node, url, {
        set_dir_method = get_set_dir_method(),
        new_dir = get_new_dir_prop,
      })
      :next(function(attachment_name)
        if attachment_name then
          utils.echo_info(('File %s is now an attachment'):format(attachment_name))
          if visit_dir then
            local attach_dir = self.core:get_dir(node)
            self.core:reveal_nvim(attach_dir)
          end
        end
        return attachment_name
      end)
      :wait(MAX_TIMEOUT)
end

---Attach buffer's contents to current outline node.
---
---Throws a file-exists error if it would overwrite an existing filename.
---
---@param buffer? string | integer A buffer number or name.
---@param opts? orgmode.attach.attach_url.Options
---@return string|nil attachment_name
function Attach:attach_buffer(buffer, opts)
  if buffer and buffer ~= '' then
    buffer = get_bufnr_verbose(buffer)
  else
    buffer = select_buffer()
  end
  if not buffer then
    error('Cancelled')
  end
  local node = opts and opts.node or self.core:get_current_node()
  local visit_dir = opts and opts.visit_dir or false
  return self.core
      :attach_buffer(node, buffer, {
        set_dir_method = get_set_dir_method(),
        new_dir = get_new_dir_prop,
      })
      :next(function(attachment_name)
        if attachment_name then
          utils.echo_info(('File %s is now an attachment'):format(attachment_name))
          if visit_dir then
            local attach_dir = self.core:get_dir(node)
            self.core:reveal_nvim(attach_dir)
          end
        end
        return attachment_name
      end)
      :wait(MAX_TIMEOUT)
end

---Move/copy/link many files into attachment directory.
---
---@param files string[]
---@param opts? orgmode.attach.attach.Options
---@return string|nil attachment_name
function Attach:attach_many(files, opts)
  local node = opts and opts.node or self.core:get_current_node()
  local visit_dir = opts and opts.visit_dir or false
  local method = opts and opts.method or config.org_attach_method

  return self.core:attach_many(node, files, {
    set_dir_method = get_set_dir_method(),
    new_dir = get_new_dir_prop,
    attach_method = method,
  }):next(function(res)
    if res.successes + res.failures > 0 then
      local function plural(count)
        return count == 1 and '' or 's'
      end
      local msg = ('attached %d file%s to %s'):format(res.successes, plural(res.successes), node:get_title())
      local extra = res.failures > 0
          and { { ('failed to attach %d file%s'):format(res.failures, plural(res.failures)), 'ErrorMsg' } }
          or nil
      utils.echo_info(msg, extra)
      if res.successes > 0 and visit_dir then
        local attach_dir = self.core:get_dir(node)
        self.core:reveal_nvim(attach_dir)
      end
    end
    return nil
  end):wait(MAX_TIMEOUT)
end

---@class orgmode.attach.attach_new.Options
---@inlinedoc
---@field bang? boolean if true, open the new file with `:enew!`
---@field mods? table<string,any> command modifiers to pass to `:enew[!]`; see
---                               docs for `nvim_parse_cmd()` for a list

---Create a new attachment FILE for the current outline node.
---
---The attachment is opened as a new buffer.
---
---@param name? string
---@param node? OrgAttachNode
---@param enew_opts? orgmode.attach.attach_new.Options
---@return string|nil attachment_name
function Attach:attach_new(name, node, enew_opts)
  name = name or vim.fn.input('Create attachnment named: ')
  if not name or name == '' then
    error('Cancelled')
  end
  node = node or self.core:get_current_node()
  return self.core:attach_new(node, name, {
    set_dir_method = get_set_dir_method(),
    new_dir = get_new_dir_prop,
    enew_bang = enew_opts and enew_opts.bang or false,
    enew_mods = enew_opts and enew_opts.mods or {},
  }):next(function(attachment_name)
    if attachment_name then
      utils.echo_info(('new attachment %s'):format(attachment_name))
    end
    return attachment_name
  end):wait(MAX_TIMEOUT)
end

---Attach a file by copying it.
---
---@param node? OrgAttachNode
---@return string|nil attachment_name
function Attach:attach_cp(node)
  return self:attach(nil, { method = 'cp', node = node })
end

---Attach a file by moving (renaming) it.
---
---@param node? OrgAttachNode
---@return string|nil attachment_name
function Attach:attach_mv(node)
  return self:attach(nil, { method = 'mv', node = node })
end

---Attach a file by creating a hard link to it.
---
---Beware that this does not work on systems that do not support hard links.
---On some systems, this apparently does copy the file instead.
---
---@param node? OrgAttachNode
---@return string|nil attachment_name
function Attach:attach_ln(node)
  return self:attach(nil, { method = 'ln', node = node })
end

---Attach a file by creating a symbolic link to it.
---
---Beware that this does not work on systems that do not support symbolic
---links. On some systems, this apparently does copy the file instead.
---
---@param node? OrgAttachNode
---@return string|nil attachment_name
function Attach:attach_lns(node)
  return self:attach(nil, { method = 'lns', node = node })
end

---@class orgmode.attach.attach_to_other_buffer.Options
---@inlinedoc
---@field window? integer | string if passed, attach to the node pointed at in
---               the given window; you can pass a window-ID, window number, or
---               `winnr()`-style strings, e.g. `#` to use the previously
---               active window. Pass 0 for the current window. It's an error
---               if the window doesn't display an org file.
---@field ask? 'always'|'multiple' determines what to do if `window` is nil;
---            if 'always', collect all nodes displayed in a window and ask the
---            user to select one. If 'multiple', only ask if more than one
---            node is displayed. If false or nil, never ask the user; accept
---            the unambiguous choice or abort.
---@field prefer_recent? 'ask'|'buffer'|'window'|boolean if not nil but
---                      `window` is nil, and more than one node is displayed,
---                      and one of them is more preferable than the others,
---                      this one is used without asking the user.
---                      Preferred nodes are those displayed in the current
---                      window's current buffer and alternate buffer, as well
---                      as the previous window's current buffer. Pass 'buffer'
---                      to prefer the alternate buffer over the previous
---                      window. Pass 'window' for the same vice versa. Pass
---                      'ask' to ask the user in case of conflict. Pass 'true'
---                      to prefer only an unambiguous recent node over
---                      non-recent ones.
---@field include_hidden? boolean If not nil, include not only displayed nodes,
---                       but also those in hidden buffers; for those, the node
---                       pointed at by the `"` mark (position when last
---                       exiting the buffer) is chosen.
---@field visit_dir? boolean if not nil, open the relevant attachment directory
---                          after attaching the file.
---@field method? 'cp' | 'mv' | 'ln' | 'lns' The attachment method, same values
---               as in `org_attach_method`.

---@param file_or_files string | string[]
---@param opts? orgmode.attach.attach_to_other_buffer.Options
---@return string|nil attachment_name
function Attach:attach_to_other_buffer(file_or_files, opts)
  local files = utils.ensure_array(file_or_files) ---@type string[]
  local node = self:find_other_node(opts)
  return self:attach_many(files, {
    node = node,
    method = opts and opts.method,
    visit_dir = opts and opts.visit_dir,
  })
end

---@param attach_dir? string the directory to open
---@return nil
function Attach:reveal(attach_dir)
  attach_dir = attach_dir or self:get_dir_or_create()
  return self.core:reveal(attach_dir)
end

---@param attach_dir? string the directory to open
---@return nil
function Attach:reveal_nvim(attach_dir)
  attach_dir = attach_dir or self:get_dir_or_create()
  return self.core:reveal_nvim(attach_dir)
end

---@param name? string name of the file to open
---@param node? OrgAttachNode
---@param in_nvim? boolean if true, open as new buffer
---@return nil
function Attach:open(name, node, in_nvim)
  node = node or self.core:get_current_node()
  local attach_dir = self.core:get_dir(node)
  name = name or vim.fn.OrgmodeInput('Open attachment: ', '', self:make_completion({ dir = attach_dir }))
  if not name or name == '' then
    error('Cancelled')
  end
  local path = vim.fs.joinpath(attach_dir, name)
  local open = in_nvim and vim.cmd.edit or vim.ui.open
  EventManager.dispatch(EventManager.event.AttachOpened:new(node, path))
  open(path)
end

---@param name? string name of the file to open
---@param node? OrgAttachNode
---@return nil
function Attach:open_in_vim(name, node)
  return self:open(name, node, true)
end

---Delete a single attachment.
---
---@param name? string the name of the attachment to delete
---@param node? OrgAttachNode
---@return nil
function Attach:delete_one(name, node)
  node = node or self.core:get_current_node()
  local attach_dir = self.core:get_dir(node)
  name = name or vim.fn.OrgmodeInput('Delete attachment: ', '', self:make_completion({ dir = attach_dir }))
  if not name or name == '' then
    error('Cancelled')
  end
  return self.core:delete_one(node, name):wait(MAX_TIMEOUT)
end

---Delete all attachments from the current outline node.
---
---This actually deletes the entire attachment directory. A safer way is to
---open the directory with `reveal` and delete from there.
---
---@param force? boolean if true, delete directory will recursively deleted with no prompts.
---@param node? OrgAttachNode
---@return nil
function Attach:delete_all(force, node)
  if not force and not yes_or_no_or_cancel_slow('Remove all attachments? ') == 'yes' then
    error('Cancelled')
  end
  node = node or self.core:get_current_node()
  self.core:delete_all(node, function()
    return force or yes_or_no_or_cancel_slow('Recursive? ') == 'yes'
  end):next(function()
    utils.echo_info('Attachment directory removed')
    return
  end):wait(MAX_TIMEOUT)
end

---Maybe delete subtree attachments when archiving.
---
---This function is called via the `OrgHeadlineArchivedEvent.  The option
---`org_attach_archive_delete' controls its behavior."
---
---@param headline OrgHeadline
---@return nil
function Attach:maybe_delete_archived(headline)
  local delete = config.org_attach_archive_delete
  if delete == 'always' then
    self:delete_all(true, AttachNode.from_headline(headline))
  end
  if delete == 'ask' then
    self:delete_all(false, AttachNode.from_headline(headline))
  end
end

---@param directory string
---@return boolean
local function has_any_non_litter_files(directory)
  for name in fsops.iterdir(directory) do
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
---@param node? OrgAttachNode
---@return OrgPromise<nil>
function Attach:sync(node)
  node = node or self.core:get_current_node()
  local delete_empty_dir = ({
    always = true,
    never = false,
    ask = function()
      return yes_or_no_or_cancel_slow('Attachment directory is empty. Delete? ') == 'yes'
    end
  })[config.org_attach_sync_delete_empty_dir]
  if not delete_empty_dir then
    error(('invalid value for org_attach_sync_delete_empty_dir: %s'):format(config.org_attach_sync_delete_empty_dir))
  end
  return self.core:sync(node, delete_empty_dir):wait(MAX_TIMEOUT)
end

---@param core OrgAttachCore
---@param file OrgFile
---@param callback fun(attach_dir: string|false, basename: string): string|nil
---@return nil
local function on_every_attachment_link(core, file, callback)
  -- TODO: In a better world, this would use treesitter for parsing ...
  file:update_sync(function()
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
          attach_dir = core:get_dir_or_nil(node, true) or false
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
  end, MAX_TIMEOUT)
end

---Expand links in current buffer.
---
---It is meant to be added to `org_export_before_parsing_hook`."
---TODO: Add this hook. Will require refactoring `orgmode.export`.
---
---@param bufnr? integer
---@return nil
function Attach:expand_links(bufnr)
  bufnr = bufnr or 0
  local file = self.core.files:get(vim.api.nvim_buf_get_name(bufnr))
  local total = 0
  local miss = 0
  on_every_attachment_link(self.core, file, function(attach_dir, basename)
    total = total + 1
    if not attach_dir then
      miss = miss + 1
      return
    end
    return 'file:' .. vim.fs.joinpath(attach_dir, basename)
  end)
  if miss > 0 then
    utils.echo_warning(('failed to expand %d/%d attachment links'):format(miss, total))
  else
    utils.echo_info(('expanded %d attachment links'):format(total))
  end
end

return Attach