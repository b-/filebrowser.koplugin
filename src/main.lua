local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template
local http = require("socket.http")
local ltn12 = require("ltn12")

local dataPath = "/"
local path = DataStorage:getFullDataDir()
local plugin_path = path .. "/plugins/filebrowser.koplugin/filebrowser"
local config_path = path .. "/plugins/filebrowser.koplugin/config.json"
local db_path = path .. "/plugins/filebrowser.koplugin/filebrowser-new.db"
local bin_path = plugin_path .. "/filebrowser"
local filebrowser_args = string.format("-d %s -c %s ", db_path, config_path)
local filebrowser_cmd = bin_path .. " " .. filebrowser_args
local log_path = plugin_path .. "/filebrowser.log"
local pid_path = "/tmp/filebrowser_koreader.pid"
local filebrowser_url = "https://github.com/filebrowser/filebrowser/releases/latest/download/%s-%s-filebrowser.tar.gz"

local silence_cmd = ""
-- uncomment below to prevent cmd output from cluttering up crash.log
silence_cmd = " > /dev/null 2>&1"

if os.execute("start-stop-daemon" .. silence_cmd) == 127 then
    logger.info("[Filebrowser] start-stop-daemon not found, plugin not loading")
    return { disabled = true, }
end

local Filebrowser = WidgetContainer:extend {
    name = "Filebrowser",
    is_doc_only = false,
}

function Filebrowser:init()
    self.filebrowser_port = G_reader_settings:readSetting("filebrowser_port") or "80"
    self.filebrowser_password_hash = G_reader_settings:readSetting("filebrowser_password") or "admin"
    self.allow_no_auth = G_reader_settings:isTrue("filebrowser_allow_no_auth")

    self:get_filebrowser_version()

    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()

    if not util.pathExists(bin_path) then
        logger.info("[Filebrowser] filebrowser binary missing")
        local info = InfoMessage:new {
            timeout = 5,
            icon = "notice-warning",
            text = _("filebrowser binary missing. Please update filebrowser."),
        }
        UIManager:show(info)
        return
    end
end

function Filebrowser:config()
    os.remove(config_path)
    os.remove(db_path)

    local init_cmd = filebrowser_cmd .. " config init" .. silence_cmd
    logger.dbg("init:", init_cmd)
    local status = os.execute(init_cmd)

    local default_user = "koreader"
    local default_password = "koreader123456789"
    local add_user_cmd = filebrowser_cmd ..
        "users add " .. default_user .. " " .. default_password .. " --perm.admin" .. silence_cmd
    logger.dbg("create_user:", add_user_cmd)
    status = os.execute(add_user_cmd)
    logger.dbg("status:", status)
    -- restrict user scope to /mnt/us, somehow adding this to the add_user_cmd doesn't work
    local update_user_cmd = filebrowser_cmd .. "users update " .. default_user .. " --scope /mnt/us" .. silence_cmd
    logger.dbg("update_user:", update_user_cmd)
    status = os.execute(update_user_cmd)
    logger.dbg("status:", status)

    local config_auth_method_cmd = string.format("%s -d %s -c %s config set --auth.method=",
        bin_path,
        db_path, config_path)
    if self.allow_no_auth then
        config_auth_method_cmd = config_auth_method_cmd .. "noauth" .. silence_cmd
    else
        config_auth_method_cmd = config_auth_method_cmd .. "json" .. silence_cmd
    end
    logger.dbg("config_auth_method:", config_auth_method_cmd)
    status = os.execute(config_auth_method_cmd)
    logger.dbg("status:", status)

    if status == 0 then
        logger.info("[Filebrowser] User '" .. default_user .. "' has been created and auth has been set to ",
            self.allow_no_auth and "noauth" or "json")
        local info = InfoMessage:new {
            text = _("Filebrowser initialized with user '" .. default_user .. "' and default password '" .. default_password .. "'. Please change the password after login."),
        }
        UIManager:show(info)
    else
        logger.info("[Filebrowser] Failed to reset admin password and auth, status Filebrowser:", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to reset Filebrowser config."),
        }
        UIManager:show(info)
    end
end

-- Since Filebrowser doesn't start as a deamon by default and has no option to
-- set a pidfile, we launch it using the start-stop-daemon helper. On Kobo and Kindle,
-- this command is provided by BusyBox:
-- https://busybox.net/downloads/BusyBox.html#start_stop_daemon
--
-- The full version has slightly more options, but seems to be a superset of
-- the BusyBox version, so it should also work with that:
-- https://man.cx/start-stop-daemon(8)
--
-- Use a pidfile to identify the process later, set --oknodo to not fail if
-- the process is already running and set --background to start as a
-- background process. On Filebrowser itself, set the root directory,
-- and a log file.
function Filebrowser:start()
    -- initalize database if first run or db was deleted
    if not util.fileExists(db_path) then
        self:config()
    end

    local cmd = string.format("start-stop-daemon -S -m -p %s -o -b -x %s -- %s -a 0.0.0.0 -r %s -p %s -l %s ",
        pid_path, bin_path, filebrowser_args, dataPath, self.filebrowser_port, log_path) .. silence_cmd
    logger.info("[Filebrowser] Launching Filebrowser:", cmd)
    local status = os.execute(cmd)

    if status == 0 then
        logger.info("[Filebrowser] Filebrowser started. Find Filebrowser logs at", log_path)
        local info = InfoMessage:new {
            timeout = 2,
            text = _("Filebrowser started!")
        }
        UIManager:show(info)
    else
        logger.info("[Filebrowser] Failed to start Filebrowser, status:", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to start Filebrowser."),
        }
        UIManager:show(info)
    end

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        logger.info("[Filebrowser] Opening port: ", self.filebrowser_port)
        os.execute(string.format("iptables -A INPUT -p tcp --dport %s -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT",
            self.filebrowser_port))
        os.execute(string.format("iptables -A OUTPUT -p tcp --sport %s -m conntrack --ctstate ESTABLISHED -j ACCEPT",
            self.filebrowser_port))
    end
end

function Filebrowser:isRunning()
    -- Run start-stop-daemon in “stop” mode (-K) with signal 0 (no-op)
    -- to test whether any process matches this pidfile and executable.
    -- Exit code: 0 → at least one process found, 1 → none found.
    local cmd = string.format("start-stop-daemon -K -s 0 -p %s -x %s", pid_path, bin_path) .. silence_cmd
    logger.info("[Filebrowser] Check if Filebrowser is running:", cmd)
    local status = os.execute(cmd)
    logger.info("[Filebrowser] Running status exit code (0 == running):", status)
    return status == 0
end

function Filebrowser:stop()
    -- Use start-stop-daemon -K to stop the process, with --oknodo to exit with
    -- status code 0 if there are no matching processes in the first place.
    local cmd
    -- cmd = string.format("start-stop-daemon -K -o -p %s -x %s", pid_path, bin_path) ???
    -- cmd = string.format("start-stop-daemon -K -o -p %s -x %s", pid_path, bin_path) ???
    cmd = string.format("cat %s | xargs kill", pid_path) .. silence_cmd
    logger.info("[Filebrowser] Stopping Filebrowser:", cmd)

    local status = os.execute(cmd)
    if status == 0 then
        logger.info("[Filebrowser] Filebrowser stopped.")
        UIManager:show(InfoMessage:new {
            text = _("Filebrowser stopped!"),
            timeout = 2,
        })
        if util.pathExists(pid_path) then
            logger.info("[Filebrowser] Removing PID file at", pid_path)
            os.remove(pid_path)
        end
    else
        logger.info("[Filebrowser] Failed to stop Filebrowser, status:", status)
        UIManager:show(InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to stop Filebrowser.")
        })
    end

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
        logger.info("[Filebrowser] Closing port: ", self.filebrowser_port)
        os.execute(string.format("iptables -D INPUT -p tcp --dport %s -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT",
            self.filebrowser_port))
        os.execute(string.format("iptables -D OUTPUT -p tcp --sport %s -m conntrack --ctstate ESTABLISHED -j ACCEPT",
            self.filebrowser_port))
    end
end

function Filebrowser:onToggleFilebrowser()
    if self:isRunning() then
        self:stop()
    else
        self:start()
    end
end

function Filebrowser:show_port_dialog(touchmenu_instance)
    self.port_dialog = InputDialog:new {
        title = _("Choose Filebrowser port"),
        input = self.filebrowser_port,
        input_type = "number",
        input_hint = self.filebrowser_port,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.port_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value = tonumber(self.port_dialog:getInputText())
                        if value and value >= 0 then
                            self.filebrowser_port = value
                            G_reader_settings:saveSetting("filebrowser_port", self.filebrowser_port)
                            UIManager:close(self.port_dialog)
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.port_dialog)
    self.port_dialog:onShowKeyboard()
end

function Filebrowser:show_filebrowser_update_dialog()
    local latest_version = self:get_filebrowser_latest_version()
    if not latest_version then
        local info = InfoMessage:new {
            timeout = 5,
            icon = "notice-warning",
            text = _("Failed to check for filebrowser update. Please check manually."),
        }
        UIManager:show(info)
        return
    end

    if self.filebrowser_version == latest_version then
        local info = InfoMessage:new {
            timeout = 2,
            text = _("Filebrowser is up to date."),
        }
        UIManager:show(info)
        return
    end

    self.filebrowser_update_dialog = InputDialog:new {
        title = _("Check for filebrowser update"),
        input = T(_("Current version: %1\nLatest version: %2\n\nUpdate filebrowser?"), self.filebrowser_version, latest_version),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.filebrowser_update_dialog)
                    end,
                },
                {
                    text = _("Update"),
                    callback = function()
                        self:download_filebrowser_binary()
                        self:get_filebrowser_version()
                        UIManager:close(self.filebrowser_update_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.filebrowser_update_dialog)
end

function Filebrowser:get_filebrowser_latest_version()
    local filebrowser_download_url = self:get_filebrowser_download_url()
    if not filebrowser_download_url then
        return
    end

    local b, code, headers = http.request {
        url = filebrowser_download_url,
        redirect = false,
    }
    if b ~= 1 or code ~= 302 or headers.location == nil then
        logger.warn("[Filebrowser] Failed to get filebrowser latest version, code:", code)
        return
    end

    return headers.location:match("v[%d%.]+")
end

function Filebrowser:get_filebrowser_version()
    self.filebrowser_version = "unknown"
    local version_output = io.popen(string.format("%s version", bin_path)):read("*a")
    if version_output then
        -- Extract version number from output like "File Browser v2.42.5/cacfb2bc"
        local version_match = version_output:match("v([%d%.]+)")
        if version_match then
            self.filebrowser_version = "v" .. version_match
        end
    end
end

function Filebrowser:download_filebrowser_binary()
    local download_url = self:get_filebrowser_download_url()
    if not download_url then
        return
    end

    local tmp_dir = plugin_path .. '/filebrowser_update'
    os.execute(string.format("rm -rf %s", tmp_dir))
    os.execute(string.format("mkdir -p %s", tmp_dir))

    -- download latest release of filebrowser from github
    logger.dbg("download_url:", download_url)
    local download_file = tmp_dir .. "/filebrowser.tar.gz"

    local res, code = http.request {
        url = download_url,
        sink = ltn12.sink.file(io.open(download_file, "wb"))
    }
    if res == nil or code ~= 200 then
        logger.warn("[Filebrowser] Failed to download filebrowser binary, code:", code)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to download filebrowser binary."),
        }
        UIManager:show(info)
        return
    end

    -- extract the binary to the plugin directory
    local res, err = Device:unpackArchive(download_file, tmp_dir)
    if not res then
        logger.warn("[Filebrowser] Failed to extract filebrowser binary, error:", err)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to extract filebrowser binary."),
        }
        UIManager:show(info)
        return
    end

    -- copy the binary to the plugin directory
    os.execute(string.format("cp -f %s/filebrowser %s", tmp_dir, bin_path))
    -- remove the temporary directory
    os.execute(string.format("rm -rf %s", tmp_dir))

    local info = InfoMessage:new {
        timeout = 2,
        text = _("filebrowser binary updated!")
    }
    UIManager:show(info)
end

function Filebrowser:get_filebrowser_download_url()
    -- get platform and arch using uname -s and uname -m
    local platform = io.popen("uname -s"):read("*a"):lower()
    local arch = io.popen("uname -m"):read("*a"):lower()
    logger.dbg("platform:", platform)
    logger.dbg("arch:", arch)
    platform = platform:match("^%s*(.-)%s*$")
    arch = arch:match("^%s*(.-)%s*$")

    if platform ~= "linux" and platform ~= "darwin" then
        local info = InfoMessage:new {
            timeout = 5,
            icon = "notice-warning",
            text = _("Unsupported platform: " .. platform .. ". Please download the binary manually.")
        }
        UIManager:show(info)
        return
    end

    if arch:match("^armv%d") then
        arch = arch:match("^armv%d")
    elseif arch:match("^aarch64") or arch:match("^arm64") then
        arch = "arm64"
    elseif arch:match("^x86_64") or arch:match("^amd64") then
        arch = "amd64"
    else
        local info = InfoMessage:new {
            timeout = 5,
            icon = "notice-warning",
            text = _("Unsupported architecture: " .. arch .. ". Please download the binary manually.")
        }
        UIManager:show(info)
        return
    end

    return string.format(filebrowser_url, platform, arch)
end

function Filebrowser:addToMainMenu(menu_items)
    menu_items.filebrowser = {
        text = _("Filebrowser"),
        sorting_hint = "network",
        sub_item_table = {
            {
                text = _("Filebrowser"),
                keep_menu_open = true,
                checked_func = function() return self:isRunning() end,
                enabled_func = function() return util.pathExists(bin_path) end,
                callback = function(touchmenu_instance)
                    self:onToggleFilebrowser()
                    -- sleeping might not be needed, but it gives the feeling
                    -- something has been done and feedback is accurate
                    ffiutil.sleep(1)
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text_func = function()
                    return T(_("Filebrowser port (%1)"), self.filebrowser_port)
                end,
                keep_menu_open = true,
                enabled_func = function() return not self:isRunning() end,
                callback = function(touchmenu_instance)
                    self:show_port_dialog(touchmenu_instance)
                end,
            },
            {
                text = _("Login without password (DANGEROUS)"),
                checked_func = function() return self.allow_no_auth end,
                enabled_func = function() return not self:isRunning() end,
                callback = function()
                    self.allow_no_auth = not self.allow_no_auth
                    G_reader_settings:flipNilOrFalse("filebrowser_allow_no_auth")
                    local config_auth_method_cmd = string.format("%s -d %s -c %s config set --auth.method=",
                        bin_path,
                        db_path, config_path)
                    if self.allow_no_auth then
                        config_auth_method_cmd = config_auth_method_cmd .. "noauth" .. silence_cmd
                    else
                        config_auth_method_cmd = config_auth_method_cmd .. "json" .. silence_cmd
                    end
                    logger.dbg("config_auth_method:", config_auth_method_cmd)
                    local status = os.execute(config_auth_method_cmd)
                    logger.dbg("status:", status)
                end,
            },
            {
                text_func = function()
                    return T(_("Update filebrowser (current: %1)"), self.filebrowser_version)
                end,
                keep_menu_open = true,
                enabled_func = function() return not self:isRunning() end,
                callback = function(touchmenu_instance)
                    self:show_filebrowser_update_dialog()
                    touchmenu_instance:updateItems()
                end,
            },
        }
    }
end

function Filebrowser:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_filebrowser", {
        category = "none",
        event = "ToggleFilebrowser",
        title = _("Toggle Filebrowser"),
        general = true
    })
end

return Filebrowser
