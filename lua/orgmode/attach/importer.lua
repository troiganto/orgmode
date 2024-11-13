local config = require('orgmode.config')
local fsops = require('orgmode.attach.fsops')
local Promise = require('orgmode.utils.promise')

local M = {}

---@param source string
---@param method OrgAttachMethod
---@return fun(target: string): OrgPromise<boolean> success
function M.import_file(source, method)
  if method == 'mv' then
    return function(target)
      return fsops.rename(source, target)
    end
  end
  if method == 'cp' then
    return function(target)
      return fsops.is_dir(source):next(function(is_dir)
        if is_dir then
          return fsops.copy_directory(source, target, {
            parents = false,
            keep_times = false,
            create_symlink = config.org_attach_copy_directory_create_symlink,
          })
        else
          return fsops.copy_file(source, target, { excl = true, ficlone = true, ficlone_force = false })
        end
      end)
    end
  end
  if method == 'ln' then
    return function(target)
      return fsops.hardlink(source, target)
    end
  end
  if method == 'lns' then
    return function(target)
      return fsops.symlink(source, target, { dir = false, junction = false, exist_ok = false })
    end
  end
  error('unknown org_attach_method: ' .. tostring(method))
end

---@param url string
---@return fun(target: string): OrgPromise<boolean> success
function M.import_url(url)
  return function(target)
    return fsops.download_file(url, target, { exist_ok = false })
  end
end

---Attach buffer's contents to current outline node.
---
---Throws a file-exists error if it would overwrite an existing filename.
---
---@param bufnr integer
---@return fun(target: string): OrgPromise<boolean> success
function M.import_buffer(bufnr)
  return function(target)
    return fsops.exists(target)
        :next(function(exists)
          if exists then
            return Promise.reject('EEXIST: ' .. target)
          end
          return nil
        end)
        :next(function()
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          return Promise.new(function(resolve, reject)
            local ok, res = pcall(vim.fn.writefile, lines, target, 's')
            if ok then
              resolve(res == 0)
            else
              reject(res)
            end
          end)
        end)
  end
end

return M
