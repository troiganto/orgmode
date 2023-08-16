local Files = require('orgmode.parser.files')
local utils = require('orgmode.utils')
local Hyperlinks = {}

---@class FindTargetContext Arguments for `find_matching_links()`.
---@field base? string The thing to look up, meaning depends on function
---@field line? string The full line with the link, may contain garbage before
---@field hyperlinks? SearchOptions do not set manually, added by `update_hyperlink_ctx()`
---@field skip_add_prefix? boolean if `true`, find full `Section` objects, otherwise completion strings

---@class SearchOptions Result of parsing a string
---@field filepath boolean|string if the link specifies a file, the resolved path to it; `false` otherwise
---@field headline boolean|string the headline to look up if the link specifies one; `false` otherwise
---@field custom_id boolean|string the CUSTOM_ID to look up if the link specifies one; `false` otherwise

---Find the file give by the `ctx.hyperlinks.filepath` or the current file.
---@param ctx FindTargetContext with SearchOptions set
---@return File
local function get_file_from_context(ctx)
  local filepath = (ctx.hyperlinks and ctx.hyperlinks.filepath)
  if not filepath then
    return Files.get_current_file()
  end
  local canonical = vim.loop.fs_realpath(filepath)
  if not canonical then
    return Files.get_current_file()
  end

  return Files.get(canonical)
end

---Add `hyperlinks` to the given context and modify `ctx.base`.
---If the link points at a specific headline or CUSTOM_ID, `ctx.base` is changed to that headline or CUSTOM_ID.
---The file path, if one was given, is moved to `ctx.hyperlinks.filepath`.
---@param ctx FindTargetContext
---@return nil
local function update_hyperlink_ctx(ctx)
  if not ctx.line then
    return
  end

  -- TODO: Support text search, see here [https://orgmode.org/manual/External-Links.html]
  local hyperlinks_ctx = {
    filepath = false,
    headline = false,
    custom_id = false,
  }

  local file_match = ctx.line:match('file:(.-)::')
  if file_match then
    file_match = Hyperlinks.get_file_real_path(file_match)
  end

  if file_match then
    file_match = vim.loop.fs_realpath(file_match)
  end

  if file_match and Files.get(file_match) then
    hyperlinks_ctx.filepath = Files.get(file_match).filename
    hyperlinks_ctx.headline = ctx.line:match('file:.-::(%*.-)$')

    if not hyperlinks_ctx.headline then
      hyperlinks_ctx.custom_id = ctx.line:match('file:.-::(#.-)$')
    end

    ctx.base = hyperlinks_ctx.headline or hyperlinks_ctx.custom_id or ctx.base
  end

  ctx.hyperlinks = hyperlinks_ctx
end

---Assume `ctx.base` points at a file and look up all matching org files.
---Only ever returns string paths, not sections. Do not call when `skip_add_prefix` is true.
---@param ctx FindTargetContext
---@return string[]
function Hyperlinks.find_by_filepath(ctx)
  local filenames = Files.filenames()
  local file_base = ctx.base:gsub('^file:', '')
  local file_base_no_start_path = file_base:gsub('^%./', '') .. ''
  local is_relative_path = file_base:match('^%./')
  local current_file_directory = vim.fn.fnamemodify(utils.current_file_path(), ':p:h')
  local valid_filenames = {}
  for _, f in ipairs(filenames) do
    if is_relative_path then
      local match = f:match('^' .. current_file_directory .. '/(' .. file_base_no_start_path .. '[^/]*%.org)$')
      if match then
        table.insert(valid_filenames, './' .. match)
      end
    else
      if f:find('^' .. file_base) then
        table.insert(valid_filenames, f)
      end
    end
  end

  -- Outer checks already filter cases where `ctx.skip_add_prefix` is truthy,
  -- so no need to check it here
  return vim.tbl_map(function(path)
    return 'file:' .. path
  end, valid_filenames)
end

---Find headlines whose CUSTOM_ID matches `ctx.base` without the leading "#".
---@param ctx FindTargetContext
---@return Section[]|string[] @type depends on `ctx.skip_add_prefix`
function Hyperlinks.find_by_custom_id_property(ctx)
  local file = get_file_from_context(ctx)
  local headlines = file:find_headlines_with_property_matching('CUSTOM_ID', ctx.base:sub(2))
  if ctx.skip_add_prefix then
    return headlines
  end
  return vim.tbl_map(function(headline)
    return '#' .. headline.properties.items.custom_id
  end, headlines)
end

---Find headlines whose title matches `ctx.base` without the leading "*".
---@param ctx FindTargetContext
---@return Section[]|string[] @type depends on `ctx.skip_add_prefix`
function Hyperlinks.find_by_title_pointer(ctx)
  local file = get_file_from_context(ctx)
  local headlines = file:find_headlines_by_title(ctx.base:sub(2), false)
  if ctx.skip_add_prefix then
    return headlines
  end
  return vim.tbl_map(function(headline)
    return '*' .. headline.title
  end, headlines)
end

---Find headlines whose section contains the <<link target>> `ctx.base`.
---@param ctx FindTargetContext
---@return Section[]|string[] @type depends on `ctx.skip_add_prefix`
function Hyperlinks.find_by_dedicated_target(ctx)
  if not ctx.base or ctx.base == '' then
    return {}
  end
  local term = string.format('<<<?(%s[^>]*)>>>?', ctx.base):lower()
  local headlines = Files.get_current_file():find_headlines_matching_search_term(term, true)
  if ctx.skip_add_prefix then
    return headlines
  end
  local targets = {}
  for _, headline in ipairs(headlines) do
    for m in headline.title:lower():gmatch(term) do
      table.insert(targets, m)
    end
    for _, content in ipairs(headline.content) do
      for m in content:lower():gmatch(term) do
        table.insert(targets, m)
      end
    end
  end
  return targets
end

---Find headlines whose title starts with `ctx.base` in the current file.
---@param ctx FindTargetContext
---@return Section[]|string[] @type depends on `ctx.skip_add_prefix`
function Hyperlinks.find_by_title(ctx)
  if not ctx.base or ctx.base == '' then
    return {}
  end
  local headlines = Files.get_current_file():find_headlines_by_title(ctx.base, false)
  if ctx.skip_add_prefix then
    return headlines
  end
  return vim.tbl_map(function(headline)
    return headline.title
  end, headlines)
end

---@param ctx? FindTargetContext
---@return Section[]|string[] @type depends on `ctx.skip_add_prefix`
function Hyperlinks.find_matching_links(ctx)
  ctx = ctx or {}
  ctx.base = ctx.base and vim.trim(ctx.base) or nil

  update_hyperlink_ctx(ctx)

  if ctx.base:find('^file:') and not ctx.skip_add_prefix then
    return Hyperlinks.find_by_filepath(ctx)
  end

  local prefix = ctx.base:sub(1, 1)
  if prefix == '#' then
    return Hyperlinks.find_by_custom_id_property(ctx)
  end
  if prefix == '*' then
    return Hyperlinks.find_by_title_pointer(ctx)
  end

  local results = Hyperlinks.find_by_dedicated_target(ctx)
  local all = utils.concat(results, Hyperlinks.find_by_title(ctx))
  return all
end

---Resolve the given path relative to the current file's path.
---If the path begins with the protocol "file:", it is stripped.
---@param url_path string
---@return string
function Hyperlinks.get_file_real_path(url_path)
  local path = url_path
  path = path:gsub('^file:', '')
  if path:match('^~/') then
    path = path:gsub('^~', vim.loop.os_homedir())
  end
  if path:match('^/') then
    return path
  end
  path = path:gsub('^./', '')
  return vim.fn.fnamemodify(utils.current_file_path(), ':p:h') .. '/' .. path
end

return Hyperlinks
