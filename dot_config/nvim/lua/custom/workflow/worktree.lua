local M = {}
local opencode_runtime = require("custom.workflow.opencode")
local win_manager = require("custom.workflow.win_manager")

local DEFAULT_BASE_BRANCH = "main"
local BARE_REPO_DIRNAME = "repo.git"
local WORKSPACE_STYLE_GROUP = "custom-worktree-workspace-style"
local TABLINE_GROUP = "custom-worktree-tabline"
local TABLINE_GLOBAL = "custom_worktree_tabline"
local DEFAULT_CONFIG = {
  copy_files = {
    enabled = false,
    source_branch = DEFAULT_BASE_BRANCH,
    paths = {},
    overwrite = true,
  },
  delete_workspace = {
    merged_into = "origin/main",
    fetch_remote = "origin",
    force_remove = true,
    protected_branches = { "main", "master" },
  },
}
local config = vim.deepcopy(DEFAULT_CONFIG)
local redraw_tabline

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

local function setup_config(opts)
  local next_config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CONFIG), opts or {})
  if opts and opts.copy_files and opts.copy_files.paths ~= nil and opts.copy_files.enabled == nil then
    next_config.copy_files.enabled = true
  end

  config = next_config
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

local function resolve_git_ref(bare_repo_dir, ref_name)
  if type(ref_name) ~= "string" or ref_name == "" then
    return nil
  end

  local direct_ok = run_git({ "rev-parse", "--verify", ref_name .. "^{tree}" }, bare_repo_dir)
  if direct_ok then
    return ref_name
  end

  return resolve_base_ref(bare_repo_dir, ref_name)
end

local function is_safe_relative_path(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then
    return false
  end

  for segment in path:gmatch("[^/\\]+") do
    if segment == ".." then
      return false
    end
  end

  return true
end

local function branch_matches_ref(branch_ref, branch_name)
  return branch_ref == branch_name
    or branch_ref == "refs/heads/" .. branch_name
    or branch_ref == "refs/remotes/" .. branch_name
end

local function source_worktree_for_branch(root_dir, bare_repo_dir, source_branch)
  local ok, result = run_git({ "worktree", "list", "--porcelain" }, bare_repo_dir)
  if ok then
    local worktree_dir = nil
    for line in (result.stdout .. "\n"):gmatch("(.-)\n") do
      if line == "" then
        worktree_dir = nil
      else
        worktree_dir = line:match("^worktree%s+(.+)$") or worktree_dir
        local branch_ref = line:match("^branch%s+(.+)$")
        if worktree_dir and branch_ref and branch_matches_ref(branch_ref, source_branch) then
          return vim.fs.normalize(worktree_dir)
        end
      end
    end
  end

  local candidate_dir = vim.fs.joinpath(root_dir, flatten_feature_name(source_branch))
  if is_directory(candidate_dir) then
    return candidate_dir
  end
end

local function ensure_parent_dir(path)
  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    vim.fn.mkdir(parent, "p")
  end
end

local function copy_file_from_worktree(source_worktree, destination_dir, relative_path, overwrite)
  if not source_worktree then
    return false, "no source worktree"
  end

  local source_path = vim.fs.joinpath(source_worktree, relative_path)
  local destination_path = vim.fs.joinpath(destination_dir, relative_path)
  local source_stat = vim.uv.fs_stat(source_path)
  if not source_stat then
    return false, "not found in source worktree"
  end
  if source_stat.type ~= "file" then
    return false, "source path is not a file"
  end
  if not overwrite and vim.uv.fs_stat(destination_path) then
    return true
  end

  ensure_parent_dir(destination_path)
  local ok, err = vim.uv.fs_copyfile(source_path, destination_path)
  if not ok then
    return false, err or "copy failed"
  end

  return true
end

local function restore_file_from_ref(source_ref, destination_dir, relative_path, overwrite)
  local destination_path = vim.fs.joinpath(destination_dir, relative_path)
  if not overwrite and vim.uv.fs_stat(destination_path) then
    return true
  end

  ensure_parent_dir(destination_path)
  local ok, result = run_git({ "restore", "--source", source_ref, "--worktree", "--", relative_path }, destination_dir)
  if ok then
    return true
  end

  return false, shell_error(result)
end

local function copy_configured_workspace_files(workspace)
  local copy_config = config.copy_files or {}
  local paths = copy_config.paths or {}
  if not copy_config.enabled or #paths == 0 then
    return true
  end

  local source_branch = copy_config.source_branch or DEFAULT_BASE_BRANCH
  local source_ref = resolve_git_ref(workspace.bare_repo_dir, source_branch)
  local source_worktree = source_worktree_for_branch(workspace.root_dir, workspace.bare_repo_dir, source_branch)
  local overwrite = copy_config.overwrite ~= false
  local failures = {}

  for _, relative_path in ipairs(paths) do
    if not is_safe_relative_path(relative_path) then
      table.insert(failures, string.format("%s: invalid relative path", tostring(relative_path)))
    else
      local ok, err = copy_file_from_worktree(source_worktree, workspace.worktree_dir, relative_path, overwrite)
      if not ok and source_ref then
        ok, err = restore_file_from_ref(source_ref, workspace.worktree_dir, relative_path, overwrite)
      end

      if not ok then
        table.insert(failures, string.format("%s: %s", relative_path, err or "copy failed"))
      end
    end
  end

  if #failures > 0 then
    notify(
      string.format("Could not copy workspace files from '%s': %s", source_branch, table.concat(failures, "; ")),
      vim.log.levels.WARN
    )
    return false
  end

  return true
end

local function current_branch(worktree_dir)
  local ok, result = run_git({ "branch", "--show-current" }, worktree_dir)
  if not ok then
    return nil, shell_error(result)
  end

  local branch = trim(result.stdout)
  if branch == "" then
    return nil, "Current workspace is in detached HEAD state"
  end

  return branch
end

local function is_protected_branch(branch)
  local protected = (config.delete_workspace or {}).protected_branches or {}
  for _, protected_branch in ipairs(protected) do
    if branch == protected_branch then
      return true
    end
  end

  return false
end

local function fetch_delete_target(bare_repo_dir)
  local remote = (config.delete_workspace or {}).fetch_remote
  if remote == false or remote == nil or remote == "" then
    return true
  end

  local ok, result = run_git({ "fetch", tostring(remote) }, bare_repo_dir)
  if ok then
    return true
  end

  return false, string.format("Failed to fetch '%s': %s", remote, shell_error(result))
end

local function ensure_ref_exists(bare_repo_dir, ref)
  local ok, result = run_git({ "rev-parse", "--verify", ref .. "^{commit}" }, bare_repo_dir)
  if ok then
    return true
  end

  return false, string.format("Could not resolve merge target '%s': %s", ref, shell_error(result))
end

local function ensure_branch_merged(workspace)
  local delete_config = config.delete_workspace or {}
  local merged_into = delete_config.merged_into or "origin/main"

  local fetch_ok, fetch_err = fetch_delete_target(workspace.bare_repo_dir)
  if not fetch_ok then
    return false, fetch_err
  end

  local ref_ok, ref_err = ensure_ref_exists(workspace.bare_repo_dir, merged_into)
  if not ref_ok then
    return false, ref_err
  end

  local ok = run_git({ "merge-base", "--is-ancestor", workspace.branch, merged_into }, workspace.bare_repo_dir)
  if ok then
    return true
  end

  return false, string.format("Branch '%s' is not fully merged into '%s'", workspace.branch, merged_into)
end

local function worktree_status(worktree_dir)
  local ok, result = run_git({ "status", "--porcelain", "--untracked-files=all" }, worktree_dir)
  if not ok then
    return nil, shell_error(result)
  end

  return trim(result.stdout)
end

local function is_path_inside(path, dir)
  if path == "" then
    return false
  end

  local normalized_path = vim.fs.normalize(path)
  local normalized_dir = vim.fs.normalize(dir)
  return normalized_path == normalized_dir or vim.startswith(normalized_path, normalized_dir .. "/")
end

local function tab_has_buffer(tab, buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return true
    end
  end

  return false
end

local function modified_workspace_buffer(worktree_dir)
  local current_tab = vim.api.nvim_get_current_tabpage()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
      local name = vim.api.nvim_buf_get_name(buf)
      if is_path_inside(name, worktree_dir) then
        return name
      end
      if name == "" and tab_has_buffer(current_tab, buf) then
        return "[No Name]"
      end
    end
  end
end

local function resolve_delete_workspace()
  local context, context_err = resolve_workspace_context()
  if not context then
    return nil, context_err
  end
  if context.mode ~= "worktree" then
    return nil, "Deleteworkspace must be run from inside a workspace worktree"
  end

  local branch, branch_err = current_branch(context.current_dir)
  if not branch then
    return nil, branch_err
  end
  if is_protected_branch(branch) then
    return nil, string.format("Refusing to delete protected branch '%s'", branch)
  end

  return {
    branch = branch,
    worktree_dir = context.current_dir,
    root_dir = context.root_dir,
    bare_repo_dir = context.bare_repo_dir,
  }
end

local function resolve_close_workspace()
  local context, context_err = resolve_workspace_context()
  if not context then
    return nil, context_err
  end
  if context.mode ~= "worktree" then
    return nil, "Closeworkspace must be run from inside a workspace worktree"
  end

  return {
    worktree_dir = context.current_dir,
    root_dir = context.root_dir,
    bare_repo_dir = context.bare_repo_dir,
    name = vim.t.workspace_name or vim.fs.basename(context.current_dir),
  }
end

local function ensure_workspace_clean(workspace)
  local modified_buffer = modified_workspace_buffer(workspace.worktree_dir)
  if modified_buffer then
    return false, string.format("Workspace has an unsaved buffer: %s", modified_buffer)
  end

  local status, status_err = worktree_status(workspace.worktree_dir)
  if status == nil then
    return false, status_err
  end
  if status ~= "" then
    return false, "Workspace has uncommitted or untracked changes"
  end

  return true
end

local function remove_workspace_worktree(workspace)
  pcall(function()
    require("opencode.terminal").close()
  end)
  vim.cmd("tcd " .. vim.fn.fnameescape(workspace.root_dir))

  local args = { "worktree", "remove" }
  if (config.delete_workspace or {}).force_remove ~= false then
    table.insert(args, "--force")
  end
  table.insert(args, workspace.worktree_dir)

  local ok, result = run_git(args, workspace.bare_repo_dir)
  if ok then
    return true
  end

  return false, shell_error(result)
end

local function delete_workspace_branch(workspace)
  local ok, result = run_git({ "branch", "-D", workspace.branch }, workspace.bare_repo_dir)
  if ok then
    return true
  end

  return false, shell_error(result)
end

local function leave_deleted_workspace(workspace)
  vim.t.workspace_name = nil
  redraw_tabline()

  if #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, "tabclose!")
    return
  end

  pcall(vim.cmd, "enew!")
  vim.cmd("tcd " .. vim.fn.fnameescape(workspace.root_dir))
  pcall(vim.cmd, "Oil " .. vim.fn.fnameescape(workspace.root_dir))
end

local function leave_workspace(workspace)
  vim.t.workspace_name = nil
  redraw_tabline()

  if #vim.api.nvim_list_tabpages() > 1 then
    local ok, err = pcall(vim.cmd, "tabclose")
    if ok then
      return true
    end

    return false, err
  end

  vim.cmd("tcd " .. vim.fn.fnameescape(workspace.root_dir))
  pcall(vim.cmd, "silent! only")
  local ok, err = pcall(vim.cmd, "Oil " .. vim.fn.fnameescape(workspace.root_dir))
  if ok then
    return true
  end

  return false, err
end

local function parse_new_workspace_args(opts)
  local parts = vim.split(vim.trim(opts.args or ""), "%s+", { trimempty = true })
  if #parts < 1 or #parts > 2 then
    return nil, "Usage: :Newworkspace <feature_name> [base_branch]"
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

local function parse_open_workspace_args(opts)
  local parts = vim.split(vim.trim(opts.args or ""), "%s+", { trimempty = true })
  if #parts ~= 1 then
    return nil, "Usage: :Openworkspace <directory_name>"
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

local function complete_open_workspace(arg_lead)
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

redraw_tabline = function()
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
    root_dir = context.root_dir,
    bare_repo_dir = context.bare_repo_dir,
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

function M.new_workspace(feature_name, base_branch)
  local worktree, err = create_worktree(feature_name, base_branch or DEFAULT_BASE_BRANCH)
  if not worktree then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  copy_configured_workspace_files(worktree)

  local ok, setup_err = setup_workspace_tab(worktree.worktree_dir, worktree.feature_name, worktree.reuse_current_tab)
  if not ok then
    notify(setup_err, vim.log.levels.ERROR)
    return false
  end

  notify(string.format("Created worktree '%s' from %s", worktree.feature_name, worktree.base_ref))
  return true
end

function M.open_workspace(directory_name)
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

function M.close_workspace()
  local workspace, workspace_err = resolve_close_workspace()
  if not workspace then
    notify(workspace_err, vim.log.levels.ERROR)
    return false
  end

  local modified_buffer = modified_workspace_buffer(workspace.worktree_dir)
  if modified_buffer then
    notify(string.format("Workspace has an unsaved buffer: %s", modified_buffer), vim.log.levels.ERROR)
    return false
  end

  local ok, err = leave_workspace(workspace)
  if not ok then
    notify(string.format("Could not close workspace '%s': %s", workspace.name, err), vim.log.levels.ERROR)
    return false
  end

  notify(string.format("Closed workspace '%s'", workspace.name))
  return true
end

function M.delete_workspace()
  local workspace, workspace_err = resolve_delete_workspace()
  if not workspace then
    notify(workspace_err, vim.log.levels.ERROR)
    return false
  end

  local clean_ok, clean_err = ensure_workspace_clean(workspace)
  if not clean_ok then
    notify(clean_err, vim.log.levels.ERROR)
    return false
  end

  local merged_ok, merged_err = ensure_branch_merged(workspace)
  if not merged_ok then
    notify(merged_err, vim.log.levels.ERROR)
    return false
  end

  local remove_ok, remove_err = remove_workspace_worktree(workspace)
  if not remove_ok then
    notify(string.format("Could not remove workspace '%s': %s", workspace.branch, remove_err), vim.log.levels.ERROR)
    return false
  end

  local branch_ok, branch_err = delete_workspace_branch(workspace)
  if not branch_ok then
    notify(string.format("Removed workspace but could not delete branch '%s': %s", workspace.branch, branch_err), vim.log.levels.ERROR)
    return false
  end

  notify(string.format("Deleted workspace and branch '%s'", workspace.branch))
  leave_deleted_workspace(workspace)
  return true
end

function M.new_workspace_command(opts)
  local parsed, err = parse_new_workspace_args(opts)
  if not parsed then
    notify(err, vim.log.levels.ERROR)
    return
  end

  M.new_workspace(parsed.feature_name, parsed.base_branch)
end

function M.open_workspace_command(opts)
  local parsed, err = parse_open_workspace_args(opts)
  if not parsed then
    notify(err, vim.log.levels.ERROR)
    return
  end

  M.open_workspace(parsed.directory_name)
end

function M.close_workspace_command()
  M.close_workspace()
end

function M.delete_workspace_command()
  M.delete_workspace()
end

function M.setup(opts)
  setup_config(opts)
  setup_tabline()
  setup_workspace_style_autocmd()

  vim.api.nvim_create_user_command("Newworkspace", M.new_workspace_command, {
    nargs = "+",
    desc = "Create a new workspace in the workflow layout",
  })

  vim.api.nvim_create_user_command("Openworkspace", M.open_workspace_command, {
    nargs = 1,
    complete = complete_open_workspace,
    desc = "Open an existing workspace in the workflow layout",
  })

  vim.api.nvim_create_user_command("Closeworkspace", M.close_workspace_command, {
    nargs = 0,
    desc = "Close the current workspace tab",
  })

  vim.api.nvim_create_user_command("Deleteworkspace", M.delete_workspace_command, {
    nargs = 0,
    desc = "Delete the current workspace after verifying it is merged",
  })
end

return M
