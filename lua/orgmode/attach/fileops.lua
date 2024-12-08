local Promise = require('orgmode.utils.promise')
local uv = vim.uv

---Utility functions for dealing with files.
---This module currently is only used by `OrgAttach`. However, it is general
---enough that, if it is useful for other modules, that it could be moved to
---`utils`.
---
---IMPLEMENTATION NOTE: Every time we chain promises, we step out of fast-api
---mode and schedule another function. It is not clear what the performance
---implications are. A test run of copying a directory with 1000 files, this
---was reasonably fast and didn't block the editor.
local M = {}

--[[
-- libuv functions ported to use OrgPromise
--]]

---Like `vim.uv.fs_readlink`, but returns a promise.
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

---Like `vim.uv.fs_rename`, but returns a promise.
---@param path string
---@param new_path string
---@return OrgPromise<true> success
function M.rename(path, new_path)
  return Promise.new(function(resolve, reject)
    uv.fs_rename(path, new_path, function(err, success)
      if success then
        resolve(success)
      else
        reject(err)
      end
    end)
  end)
end

---Like `vim.uv.fs_copyfile`, but returns a promise.
---@param path string
---@param new_path string
---@param flags? integer | uv.fs_copyfile.flags_t
---@return OrgPromise<true> success
function M.copy_file(path, new_path, flags)
  return Promise.new(function(resolve, reject)
    uv.fs_copyfile(path, new_path, flags, function(err, success)
      if success then
        resolve(success)
      else
        reject(err)
      end
    end)
  end)
end

---Like `vim.uv.fs_link`, but returns a promise.
---@param path string
---@param new_path string
---@return OrgPromise<true> success
function M.hardlink(path, new_path)
  return Promise.new(function(resolve, reject)
    uv.fs_link(path, new_path, function(err, success)
      if success then
        resolve(success)
      else
        reject(err)
      end
    end)
  end)
end

---Like `vim.uv.fs_unlink`, but returns a promise.
---@param path string
---@return OrgPromise<true> success
function M.unlink(path)
  return Promise.new(function(resolve, reject)
    uv.fs_unlink(path, function(err, success)
      if success then
        resolve(success)
      else
        reject(err)
      end
    end)
  end)
end

--[[
-- Functions that have a direct libuv equivalent, but have been made more
-- convenient.
--]]

---Get file status.
---* `preserve_symlinks`: if true, do not resolve symlinks, like
---  `vim.uv.fs_lstat`. The default is to resolve symlinks, like
---  `vim.uv.fs_stat`.
---@param path string
---@param opts? {preserve_symlinks: boolean?}
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

---Like `stat`, but resolve to nil if the file does not exist.
---This wrapper simply catches `ENOENT` and resolves as successful nil in its
---stead.
---* `preserve_symlinks`: if true, do not resolve symlinks, like
---  `vim.uv.fs_lstat`. The default is to resolve symlinks, like
---  `vim.uv.fs_stat`.
---@param path string
---@param opts? {preserve_symlinks: boolean?}
---@return OrgPromise<uv.fs_stat.result | nil> stat
function M.stat_or_nil(path, opts)
  return Promise.new(function(resolve, reject)
    local preserve_symlinks = opts and opts.preserve_symlinks
    local fstat = preserve_symlinks and uv.fs_lstat or uv.fs_stat
    fstat(path, function(err, stat)
      if stat then
        resolve(stat)
      elseif err and vim.startswith(err, 'ENOENT:') then
        resolve(nil)
      else
        reject(err)
      end
    end)
  end)
end

---Like `vim.uv.fs_scandir`, but return an iterator.
---Each iteration yields a pair `(name, filetype)` as would be returned by
---`vim.uv.fs_scandir_next`.
---@param path string
---@return fun(state: uv.uv_fs_t): (string|nil, string|nil) iterator
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

---Like `vim.uv.fs_symlink`, but with the ability to catch `EEXIST`.
---@param path string
---@param new_path string
---@param flags? {exist_ok: boolean?} if `exist_ok` is true and `new_path`
---              exists already, resolve to false. The default is to raise the
---              error `EEXIST`.
---@return OrgPromise<boolean> created true if this creates a new symlink.
function M.symlink(path, new_path, flags)
  local exist_ok = flags and flags.exist_ok or false
  return Promise.new(function(resolve, reject)
    uv.fs_symlink(path, new_path, flags, function(err, success)
      if success then
        resolve(success)
      elseif exist_ok and err and vim.startswith(err, 'EEXIST') then
        resolve(false)
      else
        reject(err)
      end
    end)
  end)
end

---Like `vim.uv.fs_mkdir`, but with more convenience options.
---* `mode`: passed directly through, the default is 0o700 (u=rwx,g=,o=).
---* `parents`: if true, missing parent directories are created recursively
---* `exist_ok`: if true and `path` points at an existing directory, resolve to
---  false. The default is to raise the error `EEXIST`.
---@param path string
---@param opts? {mode: integer?, parents: boolean?, exist_ok: boolean?}
---@return OrgPromise<boolean> created true if this creates a new directory.
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
        M.is_dir(path):next(function(is_dir)
          if is_dir then
            resolve(false)
          else
            error(err)
          end
          return nil
        end)
        return
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

--[[
-- Additional functionality that builds upon libuv.
--]]

---Resolve to true if the given file exists, to false otherwise.
---* `preserve_symlinks`: if true, do not resolve symlinks. A broken symlink
---  would still appear as an existing file in this case.
---@param path string
---@param opts? {preserve_symlinks: boolean?}
---@return OrgPromise<boolean> result
function M.exists(path, opts)
  return M.stat_or_nil(path, opts):next(function(stat)
    return stat and true or false
  end)
end

---Resolve to true if the path points at a regular file.
---* `preserve_symlinks`: if true, do not recognize symlinks to files as files.
---@param path string
---@param opts? {preserve_symlinks: boolean?}
---@return OrgPromise<boolean> result
function M.is_file(path, opts)
  return M.stat_or_nil(path, opts):next(function(stat)
    return stat and stat.type == 'file'
  end)
end

---Resolve to true if the path points at a directory.
---* `preserve_symlinks`: if true, do not recognize symlinks to directories as
---  directories.
---@param path string
---@param opts? {preserve_symlinks: boolean?}
---@return OrgPromise<boolean> result
function M.is_dir(path, opts)
  return M.stat_or_nil(path, opts):next(function(stat)
    return stat and stat.type == 'directory'
  end)
end

---Resolve to true if the path points at a directory with zero files in it.
---* `preserve_symlinks`: if true, do not recognize symlinks to directories as
---  directories.
---@param path string
---@param opts? {preserve_symlinks: boolean?}
---@return OrgPromise<boolean> result
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

---Resolve to true if the path points at a symbolic link.
---@param path string
---@return OrgPromise<boolean> result
function M.is_symlink(path)
  return M.stat_or_nil(path, { preserve_symlinks = true }):next(function(stat)
    return stat and stat.type == 'link'
  end)
end

---Helper function to `copy_directory` and `remove_directory`.
---Scan through the given directory and return a mapping from filetype to list
---of filenames in that directory.
---@param path string
---@return table<string, string[]> map_types_to_names_lists
local function groupdir(path)
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

---Helper function to `copy_symlink` and `copy_stats`.
---Convert the time object returned by libuv back into seconds-since-the-epoch.
---@param time uv.fs_stat.result.time
---@return number epoch
local function to_epoch(time)
  return time.sec + time.nsec / 1e9
end

---Copy an existing symlink as a symlink.
---* `keep_times`: if true, copy access and modification timestamps as well.
---* `exist_ok`: if true, don't raise an error if `new_path` already points at
---  an object.
---If both `keep_times` and `exist_ok`, this updates the timestamps of an
---existing symbolic link.
---@param path string
---@param new_path string
---@param flags? {keep_times: boolean?, exist_ok: boolean?}
---@return OrgPromise<boolean> created true if this creates a new symlink.
function M.copy_symlink(path, new_path, flags)
  local keep_times = flags and flags.keep_times or false
  local exist_ok = flags and flags.exist_ok or false
  return M.readlink(path):next(function(target)
    return M.is_dir(target):next(function(dir)
      return M.symlink(target, new_path, { exist_ok = exist_ok, dir = dir, junction = true })
    end)
    ---@param created boolean
  end):next(function(created)
    if not keep_times then
      return created
    end
    return M.stat(path):next(function(stat)
      local atime = to_epoch(stat.atime)
      local mtime = to_epoch(stat.mtime)
      return Promise.new(function(resolve, reject)
        uv.fs_lutime(new_path, atime, mtime, function(err)
          if err then
            reject(err)
          else
            resolve(created)
          end
        end)
      end)
    end)
  end)
end

---Copy permission bits and (potentially) timestamps from one file to another.
---@param path string
---@param new_path string
---@param keep_times boolean if true, copy access and modification timestamps
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

---The meat of `copy_directory`, without `create_symlink` handling.
---@param path string
---@param new_path string
---@param opts? {parents: boolean?, create_symlink: boolean?, keep_times: boolean?}
---@return OrgPromise<true> success
local function copy_directory_impl(path, new_path, opts)
  local parents = opts and opts.parents or true
  local keep_times = opts and opts.keep_times or false
  return M.make_dir(new_path, { parents = parents, exist_ok = true })
      :next(function()
        local items = groupdir(path)

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

---Copy a directory recursively.
---* `parents`: if true, create non-existing parent directories
---* `create_symlink`: if true and `path` is a symbolic link, don't copy its
---  contents, but rather create a symbolic link to the same target
---* `keep_times`: if true, adjust file modification times of `new_path` to
---  those of `path`.
---@param path string
---@param new_path string
---@param opts? {parents: boolean?, create_symlink: boolean?, keep_times: boolean?}
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

---Delete a directory, potentially recursively.
---* `recursive`: if true, delete all contents of `path` before deleting it.
---  The default is to only delete `path` if its an empty directory.
---@param path string
---@param opts? {recursive: boolean?}
---@return OrgPromise<boolean> success
function M.remove_directory(path, opts)
  opts = opts or {}
  local recursive = opts.recursive or false
  local prev_jobs = {}
  if recursive then
    local items = groupdir(path)
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

--[[
-- Scary hacks 💀
--]]

---Helper function to `download_file`.
---This uses NetRW to download a file and returns the download location.
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

---Download a file via NetRW.
---The file is first downloaded to a temporary location (no matter the value of
---`exist_ok`) and only then copied over to `dest`. The copy operation uses the
---`exist_ok` flag exactly like `copy_file`.
---@param url string
---@param dest string
---@param opts? {exist_ok: boolean?}
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
