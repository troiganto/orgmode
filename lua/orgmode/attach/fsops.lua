local Promise = require('orgmode.utils.promise')
local uv = vim.uv

local M = {}

---@param path string
---@return OrgPromise<uv.fs_stat.result> stat
function M.stat(path)
  return Promise.new(function(resolve, reject)
    uv.fs_stat(path, function(err, stat)
      if stat then
        resolve(stat)
      else
        reject(err)
      end
    end)
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
---@return OrgPromise<boolean> stat
function M.exists(path)
  return Promise.new(function(resolve, reject)
    uv.fs_stat(path, function(err, stat)
      if stat then
        resolve(true)
      elseif err and err:match('^ENOENT:') then
        resolve(false)
      else
        reject(err)
      end
    end)
  end)
end

---@param path string
---@return OrgPromise<string | nil> stat
local function get_type(path)
  return Promise.new(function(resolve, reject)
    uv.fs_stat(path, function(err, stat)
      if err then
        if err:match('^ENOENT:') then
          return resolve(nil)
        end
        return reject(err)
      end
      assert(stat)
      if stat.type ~= 'link' then
        return resolve(stat.type)
      end
      M.readlink(path):next(function(link)
        return get_type(link)
      end):catch(function(linkerr)
        reject(linkerr)
      end)
    end)
  end)
end

---@param path string
---@return OrgPromise<boolean> stat
function M.is_file(path)
  return get_type(path):next(function(type)
    return type == 'file'
  end)
end

---@param path string
---@return OrgPromise<boolean> stat
function M.is_dir(path)
  return get_type(path):next(function(type)
    return type == 'directory'
  end)
end

---@param path string
---@return OrgPromise<boolean> stat
function M.is_symlink(path)
  return Promise.new(function(resolve, reject)
    uv.fs_stat(path, function(err, stat)
      if err then
        if err:match('^ENOENT:') then
          return resolve(false)
        end
        return reject(err)
      end
      resolve(stat and stat.type == 'link')
    end)
  end)
end

---@param path string
---@param new_path string
---@param flags? integer | uv.fs_copyfile.flags_t
---@return OrgPromise<boolean> success
function M.copy_file(path, new_path, flags)
  return Promise.new(function(resolve, reject)
    vim.uv.fs_copyfile(path, new_path, flags, function(err, success)
      if err then
        reject(err)
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
---@param opts orgmode.attach.fsops.make_dir.flags
function M.make_dir(path, opts)
  opts.mode = opts.mode or 448 -- 0700 -> decimal
  opts.parents = opts.parents or false
  opts.exist_ok = opts.exist_ok or true
end

---@class orgmode.attach.fsops.copy_directory.flags
---@field interactive? boolean
---@field parents? boolean

---@param path string
---@param new_path string
---@param opts? orgmode.attach.fsops.copy_directory.flags
---@return OrgPromise<nil>
function M.copy_directory(path, new_path, opts)
end

return M
