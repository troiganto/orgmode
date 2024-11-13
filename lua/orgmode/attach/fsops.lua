local Promise = require('orgmode.utils.promise')
local uv = vim.uv

local M = {}

---@param time uv.fs_stat.result.time
---@return number epoch
local function to_epoch(time)
  return time.sec + time.nsec / 1e9
end

---@param path string
---@return fun(state: uv.uv_fs_t): string|nil, string|nil iterator
---@return uv.uv_fs_t state
---@return nil initial
function M.iterdir(path)
  ---@param state uv.uv_fs_t
  ---@return string|nil name
  ---@return string|nil type
  local function iter(state)
    local name, ftype = uv.fs_scandir_next(state)
    if name then
      return name, ftype
    elseif ftype then
      error(ftype)
    end
  end
  local node, err = uv.fs_scandir(path)
  if not node then
    error(err)
  end
  return iter, node, nil
end

---@param path string
---@return table<string, string[]> map_types_to_names_lists
function M.groupdir(path)
  local node, err = uv.fs_scandir(path)
  if not node then
    error(err)
  end
  local res = {}
  while true do
    local name, ftype = uv.fs_scandir_next(node)
    if not name then
      if ftype then
        error(ftype)
      end
      break
    end
    local names = res[ftype] or {}
    names[1 + #names] = name
    res[ftype] = names
  end
  return res
end

---@param path string
---@param opts? {preserve_symlinks?: boolean}
---@return OrgPromise<uv.fs_stat.result> stat
function M.stat(path, opts)
  return Promise.new(function(resolve, reject)
    local preserve_symlinks = opts and opts.preserve_symlinks
    local fstat = preserve_symlinks and uv.fs_lstat or uv.fs_stat
    fstat(path, function(err, stat)
      if stat then
        resolve(stat)
      else
        reject(err)
      end
    end)
  end)
end

---@param path string
---@param opts? {preserve_symlinks?: boolean}
---@return OrgPromise<uv.fs_stat.result | nil> stat
function M.stat_or_nil(path, opts)
  return M.stat(path, opts):catch(function(err)
    if vim.startswith(err, 'ENOENT:') then
      ---@diagnostic disable-next-line redundant-return-value
      return nil
    end
    ---@diagnostic disable-next-line redundant-return-value
    return Promise.reject(err)
  end)
end

---@param path string
---@return OrgPromise<string> path
function M.readlink(path)
  return Promise.new(function(resolve, reject)
    uv.fs_readlink(path, function(err, link)
      if link then
        resolve(link)
      else
        reject(err)
      end
    end)
  end)
end

---@param path string
---@param opts? {preserve_symlinks?: boolean}
---@return OrgPromise<boolean> stat
function M.exists(path, opts)
  return M.stat_or_nil(path, opts):next(function(stat)
    return stat and true or false
  end)
end

---@param path string
---@param opts? {preserve_symlinks?: boolean}
---@return OrgPromise<boolean> stat
function M.is_file(path, opts)
  return M.stat_or_nil(path, opts):next(function(stat)
    return stat and stat.type == 'file'
  end)
end

---@param path string
---@param opts? {preserve_symlinks?: boolean}
---@return OrgPromise<boolean> stat
function M.is_dir(path, opts)
  return M.stat_or_nil(path, opts):next(function(stat)
    return stat and stat.type == 'directory'
  end)
end

---@param path string
---@param opts? {preserve_symlinks?: boolean}
---@return OrgPromise<boolean> stat
function M.is_empty_dir(path, opts)
  return M.is_dir(path, opts):next(function(is_dir)
    if is_dir then
      for _, _ in M.iterdir(path) do
        return false
      end
      return true
    end
    return false
  end)
end

---@param path string
---@return OrgPromise<boolean> stat
function M.is_symlink(path)
  return M.stat_or_nil(path, { preserve_symlinks = true }):next(function(stat)
    return stat and stat.type == 'link'
  end)
end

---@param path string
---@param new_path string
---@return OrgPromise<boolean> success
function M.rename(path, new_path)
  return Promise.new(function(resolve, reject)
    uv.fs_rename(path, new_path, function(err, success)
      if err then
        reject(err)
      else
        resolve(success)
      end
    end)
  end)
end

---@param path string
---@param new_path string
---@param flags? integer | uv.fs_copyfile.flags_t
---@return OrgPromise<boolean> success
function M.copy_file(path, new_path, flags)
  return Promise.new(function(resolve, reject)
    uv.fs_copyfile(path, new_path, flags, function(err, success)
      if err then
        reject(err)
      else
        resolve(success)
      end
    end)
  end)
end

---@param path string
---@param new_path string
---@param flags? {keep_times?: boolean, exist_ok?: boolean}
---@return OrgPromise<boolean> success
function M.copy_symlink(path, new_path, flags)
  local keep_times = flags and flags.keep_times or false
  local exist_ok = flags and flags.exist_ok or false
  return M.readlink(path):next(function(target)
    return M.is_dir(target):next(function(dir)
      return M.symlink(target, new_path, { exist_ok = exist_ok, dir = dir, junction = true })
    end)
  end):next(function(success)
    if not keep_times then
      return success
    end
    return M.stat(path):next(function(stat)
      local atime = to_epoch(stat.atime)
      local mtime = to_epoch(stat.mtime)
      return Promise.new(function(resolve, reject)
        uv.fs_lutime(new_path, atime, mtime, function(err, success2)
          if err then
            reject(err)
          else
            resolve(success2 or false)
          end
        end)
      end)
    end)
  end)
end

---@param path string
---@param new_path string
---@return OrgPromise<boolean> success
function M.hardlink(path, new_path)
  return Promise.new(function(resolve, reject)
    uv.fs_link(path, new_path, function(err, success)
      if err then
        reject(err)
      else
        resolve(success)
      end
    end)
  end)
end

---@class orgmode.attach.fsops.symlink.flags: uv.fs_symlink.flags
---@field exist_ok? boolean

---@param path string
---@param new_path string
---@param flags? orgmode.attach.fsops.symlink.flags
---@return OrgPromise<boolean> success
function M.symlink(path, new_path, flags)
  local exist_ok = flags and flags.exist_ok
  return Promise.new(function(resolve, reject)
    uv.fs_symlink(path, new_path, flags, function(err, success)
      if err then
        if exist_ok and vim.startswith(err, 'EEXIST:') then
          resolve(false)
        else
          reject(err)
        end
      else
        resolve(success)
      end
    end)
  end)
end

---@class orgmode.attach.fsops.make_dir.flags
---@field mode? integer
---@field parents? boolean
---@field exist_ok? boolean

---@param path string
---@param opts? orgmode.attach.fsops.make_dir.flags
---@return OrgPromise<boolean> already_exists
function M.make_dir(path, opts)
  opts = opts or {}
  local mode = opts.mode or 448 -- 0700 -> decimal
  local parents = opts.parents or false
  local exist_ok = opts.exist_ok or true
  return Promise.new(function(resolve, reject)
    uv.fs_mkdir(path, mode, function(err)
      if not err then
        return resolve(false)
      elseif vim.startswith(err, 'EEXIST:') and exist_ok then
        return resolve(true)
      elseif vim.startswith(err, 'ENOENT:') and parents then
        -- Remove trailing slashes.
        path = path:match('^(.*[^/])') or path
        local parent = vim.fs.dirname(path)
        -- Avoid infinite loop if root doesn't exist:
        -- https://debbugs.gnu.org/cgi/bugreport.cgi?bug=2309
        if parent == path then
          return reject(err)
        end
        M.make_dir(parent, { mode = mode, parents = true, exist_ok = false })
            :next(function()
              return M.make_dir(path, {
                mode = mode, parents = false, exist_ok = false })
            end)
        ---@diagnostic disable-next-line
            :next(resolve, reject)
      else
        return reject(err)
      end
    end)
  end)
end

---@param path string
---@param new_path string
---@param keep_times boolean
---@return OrgPromise<nil>
local function copy_stats(path, new_path, keep_times)
  return M.stat(path):next(function(stat)
    uv.fs_chmod(new_path, stat.mode)
    if not keep_times then
      return nil
    end
    local atime = to_epoch(stat.atime)
    local mtime = to_epoch(stat.mtime)
    uv.fs_utime(new_path, atime, mtime)
    return M.is_symlink(new_path):next(function(is_new_path_symlink)
      if is_new_path_symlink then
        uv.fs_lutime(new_path, atime, mtime)
      end
      return nil
    end)
  end)
end

---@class orgmode.attach.fsops.copy_directory.flags
---@field parents? boolean if true, create non-existing parent directories
---@field create_symlink? boolean if true and `path` is a symbolic link, don't
---                               copy its contents, but rather create a
---                               symbolic link to the same target
---@field keep_times? boolean if true, adjust file modification times of
---                           `new_path` to those of `path`.

---The meat of `copy_directory`, without `create_symlink` handling.
---@param path string
---@param new_path string
---@param opts? orgmode.attach.fsops.copy_directory.flags
---@return OrgPromise<true> success
local function copy_directory_impl(path, new_path, opts)
  local parents = opts and opts.parents or true
  local keep_times = opts and opts.keep_times or false
  return M.make_dir(new_path, { parents = parents, exist_ok = true })
      :next(function(already_exists)
        local items = M.groupdir(path)

        local copy_files = Promise.map(function(name)
          M.copy_file(
            vim.fs.joinpath(path, name),
            vim.fs.joinpath(new_path, name),
            { excl = false, ficlone = true, ficlone_force = false }
          )
        end, items.file or {}, 1)

        local copy_links = Promise.map(function(name)
          return M.copy_symlink(
            vim.fs.joinpath(path, name),
            vim.fs.joinpath(new_path, name),
            { exist_ok = true, keep_times = keep_times }
          )
        end, items.link or {}, 1)

        local copy_dirs = Promise.map(function(name)
          M.copy_directory(
            vim.fs.joinpath(path, name),
            vim.fs.joinpath(new_path, name),
            opts
          )
        end, items.directory or {}, 1)

        return Promise.all({ copy_files, copy_links, copy_dirs })
      end)
      :next(function()
        return copy_stats(path, new_path, keep_times)
      end)
      :next(function()
        return true
      end)
end

---@param path string
---@param new_path string
---@param opts? orgmode.attach.fsops.copy_directory.flags
---@return OrgPromise<true> success
function M.copy_directory(path, new_path, opts)
  local create_symlink = opts and opts.create_symlink or false
  return M.readlink(path):next(function(path_symlink_target)
    if not create_symlink then
      return false
    end
    -- Source directory is a symbolic link, copy only the link.
    return M.is_dir(new_path):next(function(new_path_is_dir)
      if new_path_is_dir then
        new_path = vim.fs.joinpath(new_path, vim.fs.basename(path))
      end
      return M.symlink(path_symlink_target, new_path, {
        dir = true, junction = true, exist_ok = true })
    end):next(function() return true end)
    ---@diagnostic disable-next-line
  end, function(err)
    -- readlink failed; either path isn't a symbolic link or another error
    -- occurred.
    if vim.startswith(err, 'EINVAL:') then
      return Promise.resolve(false)
    end
    return Promise.reject(err)
  end):next(function(handled)
    -- Source directory is not a symbolic link; create destination
    -- directory, then copy recursively.
    if handled then return true end
    return copy_directory_impl(path, new_path, opts)
  end)
end

---@param path string
---@return OrgPromise<boolean> success
function M.unlink(path)
  return Promise.new(function(resolve, reject)
    uv.fs_unlink(path, function(err, success)
      if err then
        reject(err)
      else
        resolve(success)
      end
    end)
  end)
end

---@param path string
---@param opts? {recursive?: boolean}
---@return OrgPromise<boolean> success
function M.remove_directory(path, opts)
  opts = opts or {}
  local recursive = opts.recursive or false
  local prev_jobs = {}
  if recursive then
    local items = M.groupdir(path)
    local subdirs = items.directory or {}
    items.directory = nil
    local rm_dirs = Promise.map(function(subdir)
      return M.remove_directory(vim.fs.joinpath(path, subdir), opts)
    end, subdirs, 1)
    local rest = {}
    for _, names in pairs(items) do
      vim.list_extend(rest, names)
    end
    local rm_files = Promise.map(function(name)
      return M.unlink(vim.fs.joinpath(path, name))
    end, rest, 1)
    prev_jobs = { rm_dirs, rm_files }
  end
  return Promise.all(prev_jobs)
      :next(function()
        return Promise.new(function(resolve, reject)
          uv.fs_rmdir(path, function(err, success)
            if err then
              reject(err)
            else
              resolve(success)
            end
          end)
        end)
      end)
end

---@param url string
---@return OrgPromise<string> tmpfile
local function netrw_read(url)
  return Promise.new(function(resolve, reject)
    if not vim.g.loaded_netrwPlugin then
      return reject('Netrw plugin must be loaded in order to download urls.')
    end
    vim.schedule(function()
      local ok, err = pcall(vim.fn['netrw#NetRead'], 3, url)
      if ok then
        resolve(vim.b.netrw_tmpfile)
      else
        reject(err)
      end
    end)
  end)
end

---@param url string
---@param dest string
---@param opts? {exist_ok?: boolean}
---@return OrgPromise<boolean> success
function M.download_file(url, dest, opts)
  opts = opts or {}
  local exist_ok = opts.exist_ok or false
  return netrw_read(url):next(function(source)
    return M.copy_file(source, dest,
      { excl = not exist_ok, ficlone = true, ficlone_force = false })
  end)
end

return M
