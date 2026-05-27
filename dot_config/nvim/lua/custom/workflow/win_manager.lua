-- Manages the tab-local workflow between the workspace window and the opencode window.
-- It switches focus between both sides and keeps the layout consistent across
-- floating and split window modes.
--
-- Main functions:
-- - find_opencode_win: finds the opencode window in the current tab.
-- - resize_layout: resizes the current layout when the editor changes size.
-- - focus_workspace_win: focuses the workspace side of the workflow.
-- - focus_opencode_win: focuses the opencode side of the workflow.

local M = {}
local opencode_runtime = require("custom.workflow.opencode")

local WORKFLOW_WIDTH = 0.45
local FOCUS_FLOAT_ZINDEX = 45
local BACKDROP_ZINDEX = 40
local OPENCODE_NORMAL_BORDER_HL = "OpencodeNormalModeBorder"
local OPENCODE_NORMAL_BORDER_COLOR = "#4f8680"
local WORKSPACE_FOCUS_BORDER_HL = "WorkspaceFocusModeBorder"
local WORKSPACE_FOCUS_BORDER_COLOR = "#6c7086"
local FOCUS_FLOAT_BORDER = { "", "", "", { "▐", WORKSPACE_FOCUS_BORDER_HL }, "", "", "", { "▌", WORKSPACE_FOCUS_BORDER_HL } }
local OPENCODE_NORMAL_FLOAT_BORDER = {
  "",
  "",
  "",
  { "▐", OPENCODE_NORMAL_BORDER_HL },
  "",
  "",
  "",
  { "▌", OPENCODE_NORMAL_BORDER_HL },
}
local WORKSPACE_FOCUS_FLOAT_BORDER = {
  "",
  "",
  "",
  { "▐", WORKSPACE_FOCUS_BORDER_HL },
  "",
  "",
  "",
  { "▌", WORKSPACE_FOCUS_BORDER_HL },
}
local WORKSPACE_NORMAL_FLOAT_BORDER = {
  "",
  "",
  "",
  { "▐", OPENCODE_NORMAL_BORDER_HL },
  "",
  "",
  "",
  { "▌", OPENCODE_NORMAL_BORDER_HL },
}
local tab_states = {}
local previous_workflow_laststatus = nil
local WORKSPACE_WIN_OPTS = {
  number = vim.o.number,
  relativenumber = vim.o.relativenumber,
  signcolumn = vim.o.signcolumn,
  foldcolumn = vim.o.foldcolumn,
  statuscolumn = vim.o.statuscolumn,
  list = vim.o.list,
  cursorline = vim.o.cursorline,
  cursorcolumn = vim.o.cursorcolumn,
  colorcolumn = vim.o.colorcolumn,
  wrap = vim.o.wrap,
  sidescrolloff = vim.o.sidescrolloff,
}

local function current_tab()
  return vim.api.nvim_get_current_tabpage()
end

local function state_key(tab)
  return tostring(tab)
end

local function get_state(tab)
  tab = tab or current_tab()
  local key = state_key(tab)
  if not tab_states[key] then
    tab_states[key] = {
      backdrop_win = nil,
      backdrop_buf = nil,
      last_workspace_buf = nil,
      workspace_focus_win = nil,
      workspace_focus_parent_win = nil,
      workspace_focus_autocmd = nil,
    }
  end
  return tab_states[key], tab
end

local function is_float(win)
  local config = vim.api.nvim_win_get_config(win)
  return config.relative ~= ""
end

local function is_opencode_terminal_win(win, opencode_cmd)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf):lower()
  local needle = (opencode_cmd or ""):lower()
  return (needle ~= "" and name:find(needle, 1, true) ~= nil) or name:find("opencode", 1, true) ~= nil
end

local function is_last_normal_win(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end

  if is_float(win) then
    return false
  end

  local normal_win_count = 0
  local tab = vim.api.nvim_win_get_tabpage(win)
  for _, tab_win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if not is_float(tab_win) then
      normal_win_count = normal_win_count + 1
      if normal_win_count > 1 then
        return false
      end
    end
  end

  return normal_win_count == 1
end

local function ensure_closeable_win(win)
  if not is_last_normal_win(win) then
    return
  end

  -- `opencode.terminal` hides/closes windows, and Neovim rejects that for the last normal window.
  vim.api.nvim_win_call(win, function()
    vim.cmd.vnew()
  end)
end

local function is_normal_file_buf(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  return vim.bo[buf].filetype ~= "oil"
end

local function remember_workspace_buf_from_win(state, win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if is_normal_file_buf(buf) then
    state.last_workspace_buf = buf
  end
end

local function restore_workspace_buf_into_win(state, win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  if not is_normal_file_buf(state.last_workspace_buf) then
    return
  end

  local current_buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[current_buf].filetype == "oil" then
    pcall(vim.api.nvim_win_set_buf, win, state.last_workspace_buf)
  end
end

local function nudge_terminal_redraw(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" then
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)
  vim.cmd("startinsert")
  vim.cmd("stopinsert")
  if vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
end

local function enable_workflow_statusline()
  if previous_workflow_laststatus == nil then
    previous_workflow_laststatus = vim.o.laststatus
  end

  if vim.o.laststatus ~= 3 then
    vim.o.laststatus = 3
    pcall(vim.cmd, "redrawstatus")
  end
end

local function focus_float_height()
  local statusline_height = (vim.o.laststatus == 0) and 0 or 1
  return math.max(1, vim.o.lines - vim.o.cmdheight - statusline_height)
end

local function centered_float_opts()
  local width = math.max(60, math.floor(vim.o.columns * WORKFLOW_WIDTH))
  local total_height = focus_float_height()

  return {
    relative = "editor",
    style = "minimal",
    border = FOCUS_FLOAT_BORDER,
    width = width,
    height = total_height,
    col = math.floor((vim.o.columns - width) / 2),
    row = 0,
    zindex = FOCUS_FLOAT_ZINDEX,
  }
end

local function apply_focus_float_style(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  pcall(vim.api.nvim_set_option_value, "winhl", "", { win = win })
end

local function apply_opencode_normal_float_style(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  vim.api.nvim_set_hl(0, OPENCODE_NORMAL_BORDER_HL, {
    fg = OPENCODE_NORMAL_BORDER_COLOR,
  })
end

local function apply_workspace_focus_float_style(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  vim.api.nvim_set_hl(0, WORKSPACE_FOCUS_BORDER_HL, {
    fg = WORKSPACE_FOCUS_BORDER_COLOR,
  })
end

local function set_focus_float_border(win, border)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative == "" then
    return
  end

  cfg.border = border
  pcall(vim.api.nvim_win_set_config, win, cfg)
end

local function split_opts()
  return {
    split = "right",
    width = math.floor(vim.o.columns * 0.5),
  }
end

local function is_workspace_focus_open(state)
  return state.workspace_focus_win and vim.api.nvim_win_is_valid(state.workspace_focus_win)
end

local function delete_workspace_focus_autocmd(state)
  if state.workspace_focus_autocmd then
    pcall(vim.api.nvim_del_autocmd, state.workspace_focus_autocmd)
    state.workspace_focus_autocmd = nil
  end
end

local function sync_workspace_focus_to_parent(state)
  if not (is_workspace_focus_open(state) and state.workspace_focus_parent_win) then
    return
  end
  if not vim.api.nvim_win_is_valid(state.workspace_focus_parent_win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(state.workspace_focus_win)
  if not is_normal_file_buf(buf) then
    return
  end

  local ok = true
  if vim.api.nvim_win_get_buf(state.workspace_focus_parent_win) ~= buf then
    ok = pcall(vim.api.nvim_win_set_buf, state.workspace_focus_parent_win, buf)
  end
  if not ok then
    return
  end

  state.last_workspace_buf = buf
  pcall(
    vim.api.nvim_win_set_cursor,
    state.workspace_focus_parent_win,
    vim.api.nvim_win_get_cursor(state.workspace_focus_win)
  )
end

local function setup_workspace_focus_sync(state)
  delete_workspace_focus_autocmd(state)

  state.workspace_focus_autocmd = vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Sync focused workspace buffer into its parent window",
    callback = function()
      if not is_workspace_focus_open(state) then
        state.workspace_focus_autocmd = nil
        return true
      end
      if vim.api.nvim_get_current_win() ~= state.workspace_focus_win then
        return
      end

      sync_workspace_focus_to_parent(state)
    end,
  })
end

local function apply_opencode_window_style(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  local win_opts = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    list = false,
    cursorline = false,
    cursorcolumn = false,
    colorcolumn = "",
    wrap = false,
    sidescrolloff = 0,
  }

  for name, value in pairs(win_opts) do
    pcall(vim.api.nvim_set_option_value, name, value, { win = win })
  end
end

function M.apply_workspace_window_style(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  for name, value in pairs(WORKSPACE_WIN_OPTS) do
    pcall(vim.api.nvim_set_option_value, name, value, { win = win })
  end
end

local function close_backdrop(state)
  if state.backdrop_win and vim.api.nvim_win_is_valid(state.backdrop_win) then
    vim.api.nvim_win_close(state.backdrop_win, true)
  end
  state.backdrop_win = nil

  if state.backdrop_buf and vim.api.nvim_buf_is_valid(state.backdrop_buf) then
    vim.api.nvim_buf_delete(state.backdrop_buf, { force = true })
  end
  state.backdrop_buf = nil
end

local function close_workspace_focus(state, opts)
  opts = opts or {}

  if is_workspace_focus_open(state) then
    if opts.remember then
      sync_workspace_focus_to_parent(state)
      remember_workspace_buf_from_win(state, state.workspace_focus_win)
    end
    vim.api.nvim_win_close(state.workspace_focus_win, true)
  end

  delete_workspace_focus_autocmd(state)
  state.workspace_focus_win = nil

  if
    opts.restore_parent
    and state.workspace_focus_parent_win
    and vim.api.nvim_win_is_valid(state.workspace_focus_parent_win)
  then
    vim.api.nvim_set_current_win(state.workspace_focus_parent_win)
  end

  state.workspace_focus_parent_win = nil
end

local function ensure_backdrop(state)
  local total_height = focus_float_height()

  vim.api.nvim_set_hl(0, "OpencodeBackdrop", { bg = "#000000", fg = "#000000" })

  if not (state.backdrop_buf and vim.api.nvim_buf_is_valid(state.backdrop_buf)) then
    state.backdrop_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.backdrop_buf })
  end

  local opts = {
    relative = "editor",
    style = "minimal",
    border = "none",
    focusable = false,
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = total_height,
    zindex = BACKDROP_ZINDEX,
  }

  if state.backdrop_win and vim.api.nvim_win_is_valid(state.backdrop_win) then
    vim.api.nvim_win_set_config(state.backdrop_win, opts)
  else
    state.backdrop_win = vim.api.nvim_open_win(state.backdrop_buf, false, opts)
  end

  pcall(
    vim.api.nvim_set_option_value,
    "winhl",
    "Normal:OpencodeBackdrop,NormalFloat:OpencodeBackdrop,EndOfBuffer:OpencodeBackdrop",
    { win = state.backdrop_win }
  )
  pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "wrap", false, { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "list", false, { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "number", false, { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", "0", { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "statuscolumn", "", { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "colorcolumn", "", { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "cursorline", false, { win = state.backdrop_win })
  pcall(vim.api.nvim_set_option_value, "cursorcolumn", false, { win = state.backdrop_win })
end

function M.find_opencode_win(opencode_cmd, tab)
  tab = tab or current_tab()
  if not (tab and vim.api.nvim_tabpage_is_valid(tab)) then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if is_opencode_terminal_win(win, opencode_cmd) then
      return win
    end
  end
end

local function is_terminal_normal_mode()
  local mode = vim.api.nvim_get_mode().mode
  return mode == "n" or mode == "nt"
end

local function is_workspace_normal_mode()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "n"
end

local function sync_workspace_focus_border()
  for _, state in pairs(tab_states) do
    if is_workspace_focus_open(state) then
      local win = state.workspace_focus_win
      apply_focus_float_style(win)
      apply_workspace_focus_float_style(win)
      set_focus_float_border(win, WORKSPACE_FOCUS_FLOAT_BORDER)

      if vim.api.nvim_get_current_win() == win and is_workspace_normal_mode() then
        apply_opencode_normal_float_style(win)
        set_focus_float_border(win, WORKSPACE_NORMAL_FLOAT_BORDER)
      end
    end
  end
end

local function sync_opencode_focus_border(opencode_cmd, tab)
  tab = tab or current_tab()
  if not (tab and vim.api.nvim_tabpage_is_valid(tab)) then
    return
  end

  local win = M.find_opencode_win(opencode_cmd, tab)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative == "" then
    return
  end

  apply_focus_float_style(win)
  apply_workspace_focus_float_style(win)

  set_focus_float_border(win, FOCUS_FLOAT_BORDER)

  if vim.api.nvim_get_current_win() == win and is_terminal_normal_mode() then
    apply_opencode_normal_float_style(win)
    set_focus_float_border(win, OPENCODE_NORMAL_FLOAT_BORDER)
  end
end

function M.ensure_opencode_win_closeable(opencode_cmd, tab)
  local win = M.find_opencode_win(opencode_cmd, tab)
  if win then
    ensure_closeable_win(win)
  end
end

local function resolve_opencode_cmd(tab, opencode_cmd)
  if opencode_cmd and opencode_cmd ~= "" then
    return opencode_cmd
  end

  return opencode_runtime.command_for_tab(tab)
end

local function is_opencode_float_open(opencode_cmd, tab)
  local win = M.find_opencode_win(opencode_cmd, tab)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  local cfg = vim.api.nvim_win_get_config(win)
  return cfg.relative ~= ""
end

local function has_workflow_ui_open()
  for _, state in pairs(tab_states) do
    if is_workspace_focus_open(state) then
      return true
    end
  end

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local win = M.find_opencode_win(nil, tab)
    if win and vim.api.nvim_win_is_valid(win) then
      return true
    end
  end

  return false
end

local function restore_workflow_statusline_if_unused()
  if previous_workflow_laststatus == nil then
    return
  end
  if has_workflow_ui_open() then
    return
  end

  vim.o.laststatus = previous_workflow_laststatus
  previous_workflow_laststatus = nil
  pcall(vim.cmd, "redrawstatus")
end

function M.sync_statusline()
  if has_workflow_ui_open() then
    enable_workflow_statusline()
  else
    restore_workflow_statusline_if_unused()
  end
end

local function sync_backdrop(state, opencode_cmd, tab)
  M.sync_statusline()

  if is_workspace_focus_open(state) or is_opencode_float_open(opencode_cmd, tab) then
    ensure_backdrop(state)
  else
    close_backdrop(state)
  end
end

local function open_workspace_focus_in_win(state, win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  state.workspace_focus_parent_win = win
  state.workspace_focus_win = vim.api.nvim_open_win(buf, true, centered_float_opts())
  apply_focus_float_style(state.workspace_focus_win)
  M.apply_workspace_window_style(state.workspace_focus_win)
  sync_workspace_focus_border()
  pcall(vim.api.nvim_win_set_cursor, state.workspace_focus_win, cursor)
  setup_workspace_focus_sync(state)
end

function M.resize_layout(opencode_cmd)
  local state, tab = get_state()
  opencode_cmd = resolve_opencode_cmd(tab, opencode_cmd)

  if is_workspace_focus_open(state) then
    pcall(vim.api.nvim_win_set_config, state.workspace_focus_win, centered_float_opts())
    sync_workspace_focus_border()
  end

  local opencode_win = M.find_opencode_win(opencode_cmd, tab)
  if opencode_win and vim.api.nvim_win_is_valid(opencode_win) then
    local cfg = vim.api.nvim_win_get_config(opencode_win)
    if cfg.relative ~= "" then
      pcall(vim.api.nvim_win_set_config, opencode_win, centered_float_opts())
      sync_opencode_focus_border(opencode_cmd, tab)
    else
      pcall(vim.api.nvim_win_set_width, opencode_win, math.floor(vim.o.columns * 0.5))
    end
  end

  sync_backdrop(state, opencode_cmd, tab)
end

local function find_workspace_win(opencode_cmd, tab)
  local opencode_win = M.find_opencode_win(opencode_cmd, tab)
  local current_win = vim.api.nvim_get_current_win()

  local function is_valid_workspace_target(win)
    if not (win and vim.api.nvim_win_is_valid(win)) then
      return false
    end
    if win == opencode_win or is_float(win) then
      return false
    end

    local buf = vim.api.nvim_win_get_buf(win)
    local bt = vim.bo[buf].buftype
    local ft = vim.bo[buf].filetype
    return bt == "" or ft == "oil"
  end

  if is_valid_workspace_target(current_win) then
    return current_win
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if is_valid_workspace_target(win) then
      return win
    end
  end
end

function M.statusline_win()
  local current_win = vim.api.nvim_get_current_win()
  if not is_opencode_terminal_win(current_win) then
    return nil
  end

  local workspace_win = find_workspace_win(nil, vim.api.nvim_win_get_tabpage(current_win))
  if workspace_win and vim.api.nvim_win_is_valid(workspace_win) then
    return workspace_win
  end
end

function M.focus_workspace_win(opencode_cmd)
  local state, tab = get_state()
  opencode_cmd = resolve_opencode_cmd(tab, opencode_cmd)

  if is_workspace_focus_open(state) then
    close_workspace_focus(state, { restore_parent = true, remember = true })
    sync_backdrop(state, opencode_cmd, tab)
    return
  end

  enable_workflow_statusline()

  local opencode_win = M.find_opencode_win(opencode_cmd, tab)
  if opencode_win and vim.api.nvim_win_is_valid(opencode_win) then
    local cfg = vim.api.nvim_win_get_config(opencode_win)
    if cfg.relative ~= "" then
      local opts = split_opts()
      -- Float -> split while preserving the same opencode session.
      require("opencode.terminal").toggle(opencode_cmd, opts)
      require("opencode.terminal").toggle(opencode_cmd, opts)

      vim.defer_fn(function()
        if not vim.api.nvim_tabpage_is_valid(tab) then
          return
        end
        local split_win = M.find_opencode_win(opencode_cmd, tab)
        if split_win and vim.api.nvim_win_is_valid(split_win) then
          apply_opencode_window_style(split_win)
        end
      end, 40)
    end
  end

  local win = find_workspace_win(opencode_cmd, tab)
  if not win then
    sync_backdrop(state, opencode_cmd, tab)
    vim.notify("No workspace window found", vim.log.levels.WARN, { title = "opencode" })
    return
  end

  restore_workspace_buf_into_win(state, win)
  remember_workspace_buf_from_win(state, win)
  open_workspace_focus_in_win(state, win)
  sync_backdrop(state, opencode_cmd, tab)
end

function M.focus_opencode_win(opencode_cmd)
  local state, tab = get_state()
  opencode_cmd = resolve_opencode_cmd(tab, opencode_cmd)
  local return_focus_to_workspace = false

  enable_workflow_statusline()

  -- Show backdrop first to mask intermediate layout transitions and reduce flicker.
  ensure_backdrop(state)

  if is_workspace_focus_open(state) then
    close_workspace_focus(state, { restore_parent = false, remember = true })
  else
    remember_workspace_buf_from_win(state, vim.api.nvim_get_current_win())
  end

  local existing_win = M.find_opencode_win(opencode_cmd, tab)
  local float_opts = centered_float_opts()

  if existing_win and vim.api.nvim_win_is_valid(existing_win) then
    local config = vim.api.nvim_win_get_config(existing_win)
    if config.relative == "" then
      -- Preserve the same session: hide and re-show in float mode.
      ensure_closeable_win(existing_win)
      require("opencode.terminal").toggle(opencode_cmd, float_opts)
      require("opencode.terminal").toggle(opencode_cmd, float_opts)
    else
      return_focus_to_workspace = true
      -- Float -> split toggle (preserve same session/buffer).
      local opts = split_opts()
      require("opencode.terminal").toggle(opencode_cmd, opts)
      require("opencode.terminal").toggle(opencode_cmd, opts)
    end
  else
    -- If hidden or not running, toggle with float opts to show existing-or-new.
    require("opencode.terminal").toggle(opencode_cmd, float_opts)
  end

  vim.defer_fn(function()
    if not vim.api.nvim_tabpage_is_valid(tab) then
      return
    end

    local opencode_win = M.find_opencode_win(opencode_cmd, tab)
    if not opencode_win or not vim.api.nvim_win_is_valid(opencode_win) then
      close_backdrop(state)
      restore_workflow_statusline_if_unused()
      vim.notify("Could not find opencode window", vim.log.levels.WARN, { title = "opencode" })
      return
    end

    apply_opencode_window_style(opencode_win)

    local cfg = vim.api.nvim_win_get_config(opencode_win)
    if cfg.relative ~= "" then
      sync_opencode_focus_border(opencode_cmd, tab)
      ensure_backdrop(state)
    else
      close_backdrop(state)
      M.sync_statusline()
    end

    nudge_terminal_redraw(opencode_win)
    if vim.api.nvim_get_current_tabpage() == tab then
      if return_focus_to_workspace then
        local workspace_win = find_workspace_win(opencode_cmd, tab)
        if workspace_win and vim.api.nvim_win_is_valid(workspace_win) then
          vim.api.nvim_set_current_win(workspace_win)
        else
          vim.api.nvim_set_current_win(opencode_win)
        end
      else
        vim.api.nvim_set_current_win(opencode_win)
      end
    end
  end, 120)
end

local opencode_focus_border_group = vim.api.nvim_create_augroup("custom-opencode-focus-border", { clear = true })

vim.api.nvim_create_autocmd({ "ModeChanged", "TermEnter", "TermLeave", "WinEnter", "WinLeave", "BufEnter" }, {
  group = opencode_focus_border_group,
  desc = "Update workflow focus borders for current mode",
  callback = function()
    vim.schedule(function()
      sync_workspace_focus_border()
      sync_opencode_focus_border()
    end)
  end,
})

local workflow_statusline_group = vim.api.nvim_create_augroup("custom-opencode-workflow-statusline", { clear = true })

vim.api.nvim_create_autocmd({ "BufWinEnter", "TermOpen", "TermClose", "WinClosed", "TabEnter", "TabClosed" }, {
  group = workflow_statusline_group,
  desc = "Sync global statusline mode for opencode workflow",
  callback = function()
    vim.schedule(M.sync_statusline)
  end,
})

return M
