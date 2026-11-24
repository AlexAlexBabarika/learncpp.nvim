local config = require("learncpp.config")
local html = require("learncpp.html")
local util = require("learncpp.util")

local M = {}

M.BASE = "https://www.learncpp.com"
local API = M.BASE .. "/wp-json/wp/v2/posts?per_page=100&_fields=link,title,content&page="
local VERSION = 2
local BATCH = 20

local index
local syncing = false

local function path(...)
  return vim.fs.joinpath(config.options.cache_dir, ...)
end

function M.lesson_path(slug)
  return path("lessons", slug .. ".md")
end

function M.url(slug)
  return M.BASE .. "/cpp-tutorial/" .. slug .. "/"
end

function M.slug_of(url)
  return url:match("learncpp%.com/cpp%-tutorial/([^/#?]+)") or url:match("^/cpp%-tutorial/([^/#?]+)")
end

function M.label(lesson)
  return (lesson.number ~= "" and lesson.number .. " — " or "") .. lesson.title
end

local function attach(data)
  data.by_slug = {}
  for i, lesson in ipairs(data.lessons) do
    lesson.order = i
    data.by_slug[lesson.slug] = lesson
  end
  return data
end

--- The cached table of contents and site index, or nil before the first sync.
function M.index()
  if index == nil then
    local ok, data = pcall(vim.json.decode, util.read(path("index.json")) or "")
    index = ok and type(data) == "table" and data.version == VERSION and attach(data) or false
  end
  return index or nil
end

function M.read(slug)
  local text = util.read(M.lesson_path(slug))
  return text and vim.split(text:gsub("\n$", ""), "\n", { plain = true })
end

function M.last()
  local ok, state = pcall(vim.json.decode, util.read(path("state.json")) or "")
  return ok and type(state) == "table" and state.last or nil
end

function M.set_last(slug)
  util.write(path("state.json"), vim.json.encode({ last = slug }))
end

--- Chapters and lesson rows from the table of contents on the home page.
function M.parse_toc(src)
  local chapters, rows = {}, {}
  local field, buf, href, number
  for _, tok in ipairs(html.tokenize(src)) do
    if tok.open == "div" then
      field, buf, href = (tok.attrs.class or ""):match("^lessontable%-([%w-]+)"), {}, nil
    elseif tok.open == "a" and field == "row-title" then
      href = tok.attrs.href
    elseif tok.text and field then
      buf[#buf + 1] = tok.text
    elseif tok.close == "div" and field then
      local text = vim.trim(html.decode(table.concat(buf)))
      local slug = href and M.slug_of(href)
      if field == "header-chapter" then
        chapters[#chapters + 1] = { label = text, title = "" }
      elseif field == "header-title" and chapters[#chapters] then
        chapters[#chapters].title = text
      elseif field == "row-number" then
        number = text
      elseif field == "row-title" and slug then
        rows[#rows + 1] = { slug = slug, number = number or "", title = text, chapter = #chapters }
      end
      field = nil
    end
  end
  return chapters, rows
end

--- Terms of the site's own index page, each with the lessons it points at.
function M.parse_terms(src)
  local all, by_term, cur = {}, {}, nil
  for _, tok in ipairs(html.tokenize(src)) do
    if tok.open == "li" and tok.attrs.id then
      cur = { term = html.decode(tok.attrs.id), slugs = {}, see = {} }
      all[#all + 1], by_term[cur.term] = cur, cur
    elseif tok.open == "a" and cur and tok.attrs.class == "index" then
      local href = html.decode(tok.attrs.href or "")
      local slug = M.slug_of(href)
      if href:sub(1, 1) == "#" then
        cur.see[#cur.see + 1] = href:sub(2)
      elseif slug and not vim.list_contains(cur.slugs, slug) then
        cur.slugs[#cur.slugs + 1] = slug
      end
    end
  end
  local terms = {}
  for _, entry in ipairs(all) do
    local slugs = vim.list_slice(entry.slugs)
    for _, target in ipairs(entry.see) do
      for _, slug in ipairs(by_term[target] and by_term[target].slugs or {}) do
        if not vim.list_contains(slugs, slug) then
          slugs[#slugs + 1] = slug
        end
      end
    end
    if #slugs > 0 then
      terms[#terms + 1] = { term = entry.term, slugs = slugs }
    end
  end
  return terms
end

local function sort_key(lesson)
  local chapter, sub = lesson.number:match("^(%w+)%.(%w+)$")
  local n = tonumber(chapter)
  return ("%d%04d%s%04d%s"):format(n and 0 or 1, n or 0, n and "" or chapter or "~", tonumber(sub) or 9999, lesson.slug)
end

local function fetch(url, cb, with_headers)
  local cmd = { "curl", "-sS", "-L", "--fail", "--compressed", "-A", "learncpp.nvim" }
  if with_headers then
    cmd[#cmd + 1] = "-i"
  end
  cmd[#cmd + 1] = url
  vim.system(cmd, { text = true }, function(res)
    if res.code ~= 0 then
      local err = vim.trim(res.stderr or "")
      return cb(err ~= "" and err or "curl exited with code " .. res.code)
    end
    cb(nil, res.stdout)
  end)
end

local function build(pages, home, site_index, done)
  local posts = {}
  for p, body in ipairs(pages) do
    local ok, page = pcall(vim.json.decode, body)
    if not ok or type(page) ~= "table" then
      return done("could not parse page " .. p .. " of the lesson list")
    end
    for _, post in ipairs(page) do
      local slug = M.slug_of(post.link or "")
      if slug then
        posts[slug] = post
      end
    end
  end

  local chapters, rows = M.parse_toc(home)
  local lessons, listed, rest = {}, {}, {}
  for _, row in ipairs(rows) do
    if posts[row.slug] and not listed[row.slug] then
      listed[row.slug] = true
      lessons[#lessons + 1] = row
    end
  end
  for slug, post in pairs(posts) do
    if not listed[slug] then
      local full = html.decode(post.title.rendered)
      local number, title = full:match("^(%S+) — (.+)$")
      rest[#rest + 1] = { slug = slug, number = number or "", title = title or full, chapter = #chapters + 1 }
    end
  end
  if #rest > 0 then
    table.sort(rest, function(a, b)
      return sort_key(a) < sort_key(b)
    end)
    chapters[#chapters + 1] = { label = "Other", title = "Not in the table of contents" }
    vim.list_extend(lessons, rest)
  end
  if #lessons == 0 then
    return done("the learncpp.com API returned no lessons")
  end

  vim.fn.mkdir(path("lessons"), "p")
  local i = 0
  local step
  local function convert_batch()
    for _ = 1, math.min(BATCH, #lessons - i) do
      i = i + 1
      local lesson = lessons[i]
      local body = html.convert(posts[lesson.slug].content.rendered, M.BASE)
      local lines = { "# " .. M.label(lesson), "", "<" .. M.url(lesson.slug) .. ">", "" }
      lesson.spoilers = {}
      for _, range in ipairs(body.spoilers) do
        lesson.spoilers[#lesson.spoilers + 1] = { range[1] + #lines, range[2] + #lines }
      end
      vim.list_extend(lines, body.lines)
      util.write(M.lesson_path(lesson.slug), table.concat(lines, "\n") .. "\n")
    end
    if i < #lessons then
      return vim.schedule(step)
    end
    local data = {
      version = VERSION,
      synced = os.time(),
      chapters = chapters,
      lessons = lessons,
      terms = M.parse_terms(site_index),
    }
    util.write(path("index.json"), vim.json.encode(data))
    index = attach(data)
    done(nil, index)
  end
  function step()
    local ok, err = pcall(convert_batch)
    if not ok then
      done(err)
    end
  end
  step()
end

--- Download every lesson and rebuild the cache. `cb(err, index)` runs on the main loop.
function M.sync(cb)
  if syncing then
    return cb("a sync is already running")
  elseif vim.fn.executable("curl") == 0 then
    return cb("curl is required to download lessons")
  end
  syncing = true
  local finished = false
  local function done(err, result)
    if finished then
      return
    end
    finished, syncing = true, false
    vim.schedule(function()
      cb(err, result)
    end)
  end

  fetch(API .. 1, function(err, out)
    if err then
      return done(err)
    end
    local body_start = out:find("\n%[")
    local total = body_start and tonumber(out:sub(1, body_start):lower():match("x%-wp%-totalpages:%s*(%d+)"))
    if not total then
      return done("unexpected response from the learncpp.com API")
    end
    -- The lessons are required; the home page (ordering) and site index (lookup) only improve the result.
    local jobs = { home = M.BASE .. "/", site_index = M.BASE .. "/learn-cpp-site-index/" }
    for p = 2, total do
      jobs[p] = API .. p
    end
    local results, pending = { out:sub(body_start + 1) }, vim.tbl_count(jobs)
    for key, url in pairs(jobs) do
      fetch(url, function(job_err, body)
        if job_err and type(key) == "number" then
          return done(job_err)
        end
        results[key] = body or ""
        pending = pending - 1
        if pending == 0 then
          vim.schedule(function()
            local ok, build_err = pcall(build, results, results.home, results.site_index, done)
            if not ok then
              done(build_err)
            end
          end)
        end
      end)
    end
  end, true)
end

--- Run `cb(index)` once the cache exists, downloading it on first use.
function M.ensure(cb)
  local cached = M.index()
  if cached then
    return cb(cached)
  end
  util.notify("Downloading lessons from learncpp.com (first run)...")
  M.sync(function(err, fresh)
    if err then
      return util.notify("sync failed: " .. err, vim.log.levels.ERROR)
    end
    util.notify(("Cached %d lessons"):format(#fresh.lessons))
    cb(fresh)
  end)
end

return M
