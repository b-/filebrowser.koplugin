local DataStorage = require("datastorage")
local Device =  require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

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

local silence_cmd = ""
-- uncomment below to prevent cmd output from cluttering up crash.log
silence_cmd = " > /dev/null 2>&1"

if not util.pathExists(bin_path) or os.execute("start-stop-daemon" .. silence_cmd) == 127 then
    logger.info("[Filebrowser] filebrowser binary missing, plugin not loading")
    return { disabled = true, }
end

local Filebrowser = WidgetContainer:extend {
    name = "Filebrowser",
    is_doc_only = false,
}

function Filebrowser:init()
    self.filebrowser_port = G_reader_settings:readSetting("filebrowser_port") or "80"
    self.filebrowser_password_hash = G_reader_settings:readSetting("filebrowser_password") or "admin"
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function Filebrowser:config()
    os.remove(config_path)
    os.remove(db_path)

    local init_cmd = filebrowser_cmd .. " config init" .. silence_cmd
    logger.dbg("init:", init_cmd)
    local status = os.execute(init_cmd)

    local add_user_cmd = filebrowser_cmd .. "users add koreader koreader123456789 --perm.admin" .. silence_cmd
    logger.dbg("create_user:", add_user_cmd)
    status = os.execute(add_user_cmd)
    logger.dbg("status:", status)

    local disable_auth_cmd = string.format("%s -d %s -c %s config set --auth.method=noauth", bin_path, db_path, config_path) .. silence_cmd
    logger.dbg("set_noauth:", disable_auth_cmd)
    status = status + os.execute(disable_auth_cmd)
    logger.dbg("status:", status)

    if status == 0 then
        logger.info("[Filebrowser] User 'koreader' has been created and auth has been disabled.")
    else
        logger.info("[Filebrowser] Failed to reset admin password and auth, status Filebrowser, status:", status)
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
        os.execute(string.format("iptables -A INPUT -p tcp --dport %s -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT", self.filebrowser_port))
        os.execute(string.format("iptables -A OUTPUT -p tcp --sport %s -m conntrack --ctstate ESTABLISHED -j ACCEPT", self.filebrowser_port))
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
        os.execute(string.format("iptables -D INPUT -p tcp --dport %s -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT", self.filebrowser_port))
        os.execute(string.format("iptables -D OUTPUT -p tcp --sport %s -m conntrack --ctstate ESTABLISHED -j ACCEPT", self.filebrowser_port))
    end
end

function Filebrowser:onToggleFilebrowser()
    if self:isRunning() then
        self:stop()
    else
        self:start()
    end
end

function Filebrowser:addToMainMenu(menu_items)
    menu_items.filebrowser = {
        text = _("Filebrowser"),
        sorting_hint = "network",
        keep_menu_open = true,
        checked_func = function() return self:isRunning() end,
        callback = function(touchmenu_instance)
            self:onToggleFilebrowser()
            -- sleeping might not be needed, but it gives the feeling
            -- something has been done and feedback is accurate
            ffiutil.sleep(1)
            touchmenu_instance:updateItems()
        end,
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
