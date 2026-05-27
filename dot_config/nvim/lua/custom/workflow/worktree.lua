local M = {}
local opencode_runtime = require("custom.workflow.opencode")
local win_manager = require("custom.workflow.win_manager")

local DEFAULT_BASE_BRANCH = "main"
local BARE_REPO_DIRNAME = "repo.git"
local WORKSPACE_STYLE_GROUP = "custom-worktree-workspace-style"
local TABLINE_GROUP = "custom-worktree-tabline"
local TABLINE_GLOBAL = "custom_worktree_tabline"

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "workflow" })
end

local function shell_error(result)
  local stderr = (result.stderr or ""):gsub("%s+$", "")
  local stdout = (result.stdout or ""):gsub("%s+$", "")
  return stderr ~= "" and stderr or stdout
end

local function trim(value)
  local trimmed = (value or ""):gsub("%s+$", "")
  return trimmed
end

local function run_git(args, cwd)
  local result = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  return result.code == 0, result
end

local function path_type(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type or nil
end

local function is_directory(path)
  return path_type(path) == "directory"
end

local function expected_layout_error(cwd)
  return table.concat({
    "Expected project structure '<project>/repo.git' with worktree directories as siblings of repo.git.",
    string.format("Current tab directory: %s", cwd),
  }, " ")
end

local function get_current_tab_cwd()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local tabnr = vim.api.nvim_tabpage_get_number(current_tab)
  local cwd = vim.fn.getcwd(-1, tabnr)

  if cwd == nil or cwd == "" then
    cwd = vim.fn.getcwd()
  end

  return vim.fs.normalize(cwd)
end

local function is_valid_ref_name(value)
  if type(value) ~= "string" or value == "" then
    return false
  end

  if not value:match("^[A-Za-z0-9][A-Za-z0-9/_%-]*$") then
    return false
  end

  if value:find("//", 1, true)
    or value:find("..", 1, true)
    or value:find("@{", 1, true)
    or value:sub(1, 1) == "/"
    or value:sub(-1) == "/"
    or value:sub(-1) == "."
    or value:sub(-5) == ".lock"
  then
    return false
  end

  for segment in value:gmatch("[^/]+") do
    if segment:sub(1, 1) == "." then
      return false
    end
  end

  return true
end

local function is_valid_worktree_dir_name(value)
  if type(value) ~= "string" or value == "" then
    return false
  end

  if value == BARE_REPO_DIRNAME or value == "." or value == ".." then
    return false
  end

  return value:match("^[A-Za-z0-9][A-Za-z0-9._%-]*$") ~= nil
end

local function flatten_feature_name(feature_name)
  local flattened = feature_name:gsub("/", "-")
  flattened = flattened:gsub("%-+", "-")
  return flattened
end

local function resolve_workspace_context()
  local cwd = get_current_tab_cwd()
  local bare_repo_in_cwd = vim.fs.joinpath(cwd, BARE_REPO_DIRNAME)

  if is_directory(bare_repo_in_cwd) then
    local is_bare_ok, result = run_git({ "rev-parse", "--is-bare-repository" }, bare_repo_in_cwd)
    if not is_bare_ok or trim(result.stdout) ~= "true" then
      return nil, expected_layout_error(cwd)
    end

    return {
      mode = "root",
      current_dir = cwd,
      root_dir = cwd,
      bare_repo_dir = bare_repo_in_cwd,
    }
  end

  local parent_dir = vim.fs.dirname(cwd)
  if not parent_dir or parent_dir == cwd then
    return nil, expected_layout_error(cwd)
  end

  local sibling_bare_repo = vim.fs.joinpath(parent_dir, BARE_REPO_DIRNAME)
  if not is_directory(sibling_bare_repo) then
    return nil, expected_layout_error(cwd)
  end

  local is_bare_ok, result = run_git({ "rev-parse", "--is-bare-repository" }, sibling_bare_repo)
  if not is_bare_ok or trim(result.stdout) ~= "true" then
    return nil, expected_layout_error(cwd)
  end

  local is_worktree_ok, worktree_result = run_git({ "rev-parse", "--show-toplevel" }, cwd)
  if not is_worktree_ok then
    return nil, expected_layout_error(cwd)
  end

  local worktree_root = vim.fs.normalize(trim(worktree_result.stdout))
  if worktree_root ~= cwd then
    return nil, expected_layout_error(cwd)
  end

  return {
    mode = "worktree",
    current_dir = cwd,
    root_dir = parent_dir,
    bare_repo_dir = sibling_bare_repo,
  }
end

local function resolve_base_ref(bare_repo_dir, base_branch)
  local local_ok = run_git({ "rev-parse", "--verify", "refs/heads/" .. base_branch }, bare_repo_dir)
  if local_ok then
    return base_branch
  end

  local remote_ref = "origin/" .. base_branch
  local remote_ok = run_git({ "rev-parse", "--verify", "refs/remotes/" .. remote_ref }, bare_repo_dir)
  if remote_ok then
    return remote_ref
  end

  return nil
end

local function parse_new_worktree_args(opts)
  local parts = vim.split(vim.trim(opts.args or ""), "%s+", { trimempty = true })
  if #parts < 1 or #parts > 2 then
    return nil, "Usage: :NewWorktree <feature_name> [base_branch]"
  end

  local feature_name = parts[1]
  local base_branch = parts[2] or DEFAULT_BASE_BRANCH

  if not is_valid_ref_name(feature_name) then
    return nil, "Invalid feature name. Use only letters, numbers, '/', '-' and '_' in a safe git branch name format."
  end

  if not is_valid_ref_name(base_branch) then
    return nil, "Invalid base branch. Use only letters, numbers, '/', '-' and '_' in a safe git branch name format."
  end

  return {
    feature_name = feature_name,
    base_branch = base_branch,
  }
end

local function parse_open_worktree_args(opts)
  local parts = vim.split(vim.trim(opts.args or ""), "%s+", { trimempty = true })
  if #parts ~= 1 then
    return nil, "Usage: :OpenWorktree <directory_name>"
  end

  local directory_name = parts[1]
  if not is_valid_worktree_dir_name(directory_name) then
    return nil, "Invalid worktree directory name. Use only letters, numbers, '.', '-' and '_' without any path separators."
  end

  return {
    directory_name = directory_name,
  }
end

local function list_worktree_dirs(root_dir)
  local dirs = {}
  for name, entry_type in vim.fs.dir(root_dir) do
    if entry_type == "directory" and name ~= BARE_REPO_DIRNAME then
      table.insert(dirs, name)
    end
  end

  table.sort(dirs)
  return dirs
end

local function is_normal_file_buf(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)
  return vim.bo[buf].buftype == "" and not vim.startswith(name, "oil://")
end

local function apply_workspace_style_to_current_file_window()
  if not vim.t.workspace_name then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if is_normal_file_buf(buf) then
    win_manager.apply_workspace_window_style(win)
  end
end

local function setup_workspace_style_autocmd()
  local group = vim.api.nvim_create_augroup(WORKSPACE_STYLE_GROUP, { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = apply_workspace_style_to_current_file_window,
  })
end

local function complete_open_worktree(arg_lead)
  local context = resolve_workspace_context()
  if not context then
    return {}
  end

  local current_worktree_name = nil
  if context.mode == "worktree" then
    current_worktree_name = vim.fs.basename(context.current_dir)
  end

  local matches = {}
  for _, name in ipairs(list_worktree_dirs(context.root_dir)) do
    if name ~= current_worktree_name and (arg_lead == "" or vim.startswith(name, arg_lead)) then
      table.insert(matches, name)
    end
  end

  return matches
end

local function escape_tabline_text(value)
  return tostring(value or ""):gsub("%%", "%%%%")
end

local function tab_workspace_name(tab)
  local ok, name = pcall(function()
    return vim.t[tab].workspace_name
  end)

  if ok and type(name) == "string" and name ~= "" then
    return name
  end
end

local function tab_fallback_name(tab)
  local ok, win = pcall(vim.api.nvim_tabpage_get_win, tab)
  if not ok or not (win and vim.api.nvim_win_is_valid(win)) then
    return "[No Name]"
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return "[No Name]"
  end

  local tail = vim.fn.fnamemodify(name, ":t")
  return tail ~= "" and tail or name
end

local function redraw_tabline()
  pcall(vim.cmd, "redrawtabline")
end

function M.tab_label(tab)
  return tab_workspace_name(tab) or tab_fallback_name(tab)
end

function M.tabline()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local parts = {}

  for tabnr, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local hl = tab == current_tab and "%#TabLineSel#" or "%#TabLine#"
    local label = escape_tabline_text(M.tab_label(tab))
    table.insert(parts, string.format("%%%dT%s %d:%s ", tabnr, hl, tabnr, label))
  end

  table.insert(parts, "%#TabLineFill#%T")
  return table.concat(parts)
end

local function setup_tabline()
  _G[TABLINE_GLOBAL] = function()
    return require("custom.workflow.worktree").tabline()
  end

  vim.o.tabline = "%!v:lua." .. TABLINE_GLOBAL .. "()"

  local group = vim.api.nvim_create_augroup(TABLINE_GROUP, { clear = true })
  vim.api.nvim_create_autocmd({ "TabEnter", "TabClosed", "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = redraw_tabline,
  })
end

local function setup_workspace_tab(worktree_dir, workspace_name, reuse_current_tab)
  if not reuse_current_tab then
    vim.cmd.tabnew()
  end

  win_manager.ensure_opencode_win_closeable(opencode_runtime.command_for_tab())
  opencode_runtime.reset_tab_port()
  pcall(function()
    require("opencode.terminal").close()
  end)
  pcall(vim.cmd, "silent! only")

  local normalized_dir = vim.fs.normalize(worktree_dir)
  vim.cmd("tcd " .. vim.fn.fnameescape(normalized_dir))

  local actual_dir = get_current_tab_cwd()
  if actual_dir ~= normalized_dir then
    return false, string.format("Failed to switch tab directory before opening workspace. Expected %s but got %s", normalized_dir, actual_dir)
  end

  vim.t.workspace_name = workspace_name
  redraw_tabline()

  win_manager.apply_workspace_window_style(vim.api.nvim_get_current_win())
  vim.cmd("Oil " .. vim.fn.fnameescape(normalized_dir))
  win_manager.apply_workspace_window_style(vim.api.nvim_get_current_win())

  local target_tab = vim.api.nvim_get_current_tabpage()
  vim.defer_fn(function()
    if not vim.api.nvim_tabpage_is_valid(target_tab) then
      return
    end

    local current_tab = vim.api.nvim_get_current_tabpage()
    local tabnr = vim.api.nvim_tabpage_get_number(target_tab)
    local scheduled_dir = vim.fs.normalize(vim.fn.getcwd(-1, tabnr))
    if target_tab ~= current_tab or scheduled_dir ~= normalized_dir then
      return
    end

    if vim.g.opencode_opts and vim.g.opencode_opts.server and type(vim.g.opencode_opts.server.toggle) == "function" then
      vim.g.opencode_opts.server.toggle()
    else
      require("opencode").toggle()
    end
  end, 20)

  return true
end

local function create_worktree(feature_name, base_branch)
  local context, context_err = resolve_workspace_context()
  if not context then
    return nil, context_err
  end

  local worktree_dir_name = flatten_feature_name(feature_name)
  local worktree_dir = vim.fs.joinpath(context.root_dir, worktree_dir_name)

  if vim.uv.fs_stat(worktree_dir) then
    return nil, string.format("Target worktree directory already exists: %s", worktree_dir)
  end

  local base_ref = resolve_base_ref(context.bare_repo_dir, base_branch)
  if not base_ref then
    return nil, string.format("Could not resolve base branch '%s' locally or as origin/%s", base_branch, base_branch)
  end

  local ok, result = run_git({ "worktree", "add", "-b", feature_name, worktree_dir, base_ref }, context.bare_repo_dir)
  if not ok then
    return nil, shell_error(result)
  end

  return {
    feature_name = feature_name,
    worktree_dir = worktree_dir,
    base_ref = base_ref,
    reuse_current_tab = context.mode == "root",
  }
end

local function resolve_worktree_workspace_name(worktree_dir, fallback_name)
  local ok, result = run_git({ "branch", "--show-current" }, worktree_dir)
  if not ok then
    return nil, shell_error(result)
  end

  local branch_name = trim(result.stdout)
  if branch_name == "" then
    return fallback_name
  end

  return branch_name
end

local function open_existing_worktree(directory_name)
  local context, context_err = resolve_workspace_context()
  if not context then
    return nil, context_err
  end

  local worktree_dir = vim.fs.joinpath(context.root_dir, directory_name)
  if not is_directory(worktree_dir) then
    return nil, string.format("Worktree directory does not exist: %s", worktree_dir)
  end

  local workspace_name, name_err = resolve_worktree_workspace_name(worktree_dir, directory_name)
  if not workspace_name then
    return nil, name_err
  end

  return {
    directory_name = directory_name,
    feature_name = workspace_name,
    worktree_dir = worktree_dir,
    reuse_current_tab = context.mode == "root",
  }
end

function M.new_worktree(feature_name, base_branch)
  local worktree, err = create_worktree(feature_name, base_branch or DEFAULT_BASE_BRANCH)
  if not worktree then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  local ok, setup_err = setup_workspace_tab(worktree.worktree_dir, worktree.feature_name, worktree.reuse_current_tab)
  if not ok then
    notify(setup_err, vim.log.levels.ERROR)
    return false
  end

  notify(string.format("Created worktree '%s' from %s", worktree.feature_name, worktree.base_ref))
  return true
end

function M.open_worktree(directory_name)
  local worktree, err = open_existing_worktree(directory_name)
  if not worktree then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  local ok, setup_err = setup_workspace_tab(worktree.worktree_dir, worktree.feature_name, worktree.reuse_current_tab)
  if not ok then
    notify(setup_err, vim.log.levels.ERROR)
    return false
  end

  notify(string.format("Opened worktree '%s'", worktree.feature_name))
  return true
end

function M.new_worktree_command(opts)
  local parsed, err = parse_new_worktree_args(opts)
  if not parsed then
    notify(err, vim.log.levels.ERROR)
    return
  end

  M.new_worktree(parsed.feature_name, parsed.base_branch)
end

function M.open_worktree_command(opts)
  local parsed, err = parse_open_worktree_args(opts)
  if not parsed then
    notify(err, vim.log.levels.ERROR)
    return
  end

  M.open_worktree(parsed.directory_name)
end

function M.setup()
  setup_tabline()
  setup_workspace_style_autocmd()

  vim.api.nvim_create_user_command("NewWorktree", M.new_worktree_command, {
    nargs = "+",
    desc = "Create a new git worktree in the workflow layout",
  })

  vim.api.nvim_create_user_command("OpenWorktree", M.open_worktree_command, {
    nargs = 1,
    complete = complete_open_worktree,
    desc = "Open an existing git worktree in the workflow layout",
  })
end

return M
