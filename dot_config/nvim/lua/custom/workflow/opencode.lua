local M = {}

local BASE_CMD = "opencode --port"

local function current_tab()
  return vim.api.nvim_get_current_tabpage()
end

local function allocate_port()
  local tcp, err = vim.uv.new_tcp()
  if not tcp then
    error("Failed to create TCP handle for opencode port allocation: " .. tostring(err))
  end

  local bind_ok, bind_err = pcall(tcp.bind, tcp, "127.0.0.1", 0)
  if not bind_ok then
    tcp:close()
    error("Failed to bind TCP handle for opencode port allocation: " .. tostring(bind_err))
  end

  local sockname = tcp:getsockname()
  tcp:close()

  if not (sockname and sockname.port) then
    error("Failed to determine allocated opencode port")
  end

  return sockname.port
end

function M.base_cmd()
  return BASE_CMD
end

function M.get_tab_port(tab)
  tab = tab or current_tab()
  local ok, port = pcall(function()
    return vim.t[tab].opencode_port
  end)

  if not ok then
    return nil
  end

  return type(port) == "number" and port or nil
end

function M.set_tab_port(port, tab)
  tab = tab or current_tab()
  vim.t[tab].opencode_port = port
  return port
end

function M.ensure_tab_port(tab)
  tab = tab or current_tab()
  local port = M.get_tab_port(tab)
  if port then
    return port
  end

  return M.set_tab_port(allocate_port(), tab)
end

function M.reset_tab_port(tab)
  tab = tab or current_tab()
  return M.set_tab_port(allocate_port(), tab)
end

function M.command_for_tab(tab)
  local port = M.ensure_tab_port(tab)
  return string.format("%s %d", BASE_CMD, port)
end

return M
