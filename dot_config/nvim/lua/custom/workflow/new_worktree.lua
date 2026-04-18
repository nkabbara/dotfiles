local M = {}

local DEFAULT_BASE_BRANCH = "main"

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "workflow" })
end

local function shell_error(result)
  local stderr = (result.stderr or ""):gsub("%s+$", "")
  local stdout = (result.stdout or ""):gsub("%s+$", "")
  return stderr ~= "" and stderr or stdout
end

local function run_git(args, cwd)
  local result = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  return result.code == 0, result
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

local function flatten_feature_name(feature_name)
  local flattened = feature_name:gsub("/", "-")
  flattened = flattened:gsub("%-+", "-")
  return flattened
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

local function resolve_base_ref(repo_cwd, base_branch)
  local local_ok = run_git({ "rev-parse", "--verify", "refs/heads/" .. base_branch }, repo_cwd)
  if local_ok then
    return base_branch
  end

  local remote_ref = "origin/" .. base_branch
  local remote_ok = run_git({ "rev-parse", "--verify", "refs/remotes/" .. remote_ref }, repo_cwd)
  if remote_ok then
    return remote_ref
  end

  return nil
end

local function parse_args(opts)
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

local function create_worktree(feature_name, base_branch)
  local source_dir = get_current_tab_cwd()
  local parent_dir = vim.fs.dirname(source_dir)
  local worktree_dir_name = flatten_feature_name(feature_name)
  local worktree_dir = vim.fs.joinpath(parent_dir, worktree_dir_name)

  if vim.uv.fs_stat(worktree_dir) then
    return nil, string.format("Target worktree directory already exists: %s", worktree_dir)
  end

  local base_ref = resolve_base_ref(source_dir, base_branch)
  if not base_ref then
    return nil, string.format("Could not resolve base branch '%s' locally or as origin/%s", base_branch, base_branch)
  end

  local ok, result = run_git({ "worktree", "add", "-b", feature_name, worktree_dir, base_ref }, source_dir)
  if not ok then
    return nil, shell_error(result)
  end

  return {
    source_dir = source_dir,
    worktree_dir = worktree_dir,
    feature_name = feature_name,
    base_ref = base_ref,
  }
end

local function open_worktree_tab(worktree)
  vim.cmd.tabnew()
  vim.t.workflow_name = worktree.feature_name
  vim.cmd("tcd " .. vim.fn.fnameescape(worktree.worktree_dir))
  vim.cmd("Oil " .. vim.fn.fnameescape(worktree.worktree_dir))
  require("opencode").toggle()
end

function M.new_worktree(feature_name, base_branch)
  local worktree, err = create_worktree(feature_name, base_branch or DEFAULT_BASE_BRANCH)
  if not worktree then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  open_worktree_tab(worktree)
  notify(string.format("Created worktree '%s' from %s", worktree.feature_name, worktree.base_ref))
  return true
end

function M.command(opts)
  local parsed, err = parse_args(opts)
  if not parsed then
    notify(err, vim.log.levels.ERROR)
    return
  end

  M.new_worktree(parsed.feature_name, parsed.base_branch)
end

function M.setup()
  vim.api.nvim_create_user_command("NewWorktree", M.command, {
    nargs = "+",
    desc = "Create a new git worktree in a new workflow tab",
  })
end

return M
