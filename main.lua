-- set to the root directory you want to manage
-- on Kindle this should probably be:
-- local dataPath = "/mnt/us"
local dataPath = "/"

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device =  require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")  -- luacheck:ignore
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local path = DataStorage:getFullDataDir()
local plugPath = path .. "/plugins/filebrowser.koplugin/filebrowser"
local configPath = path .. "/plugins/filebrowser.koplugin/config.json"
local dbPath = path .. "/plugins/filebrowser.koplugin/filebrowser.db"
local binPath = plugPath .. "/filebrowser"
local filebrowserArgs = string.format(
    "%s %s %s %s ",
    "-d", dbPath,
    "-c ", configPath
)
local filebrowserCmd = string.format("%s %s %s %s %s ",
        binPath,
        "-d", dbPath,
        "-c ", configPath
)
local logPath = plugPath .. "/filebrowser.log"
local pidFilePath = "/tmp/filebrowser_koreader.pid"

if not util.pathExists(binPath) or os.execute("start-stop-daemon") == 127 then
    return { disabled = true, }
end

local Filebrowser = WidgetContainer:extend {
    name = "Filebrowser",
    is_doc_only = false,
}

function Filebrowser:init()
    self.filebrowser_port = G_reader_settings:readSetting("filebrowser_port") or "80"
    self.filebrowser_password_hash = G_reader_settings:readSetting("filebrowser_password") or "admin" -- admin
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

-- Wipe configuration and set auth to noauth
function Filebrowser:config()
    os.remove(configPath)
    os.remove(dbPath)
    local init = string.format("%s %s",
        filebrowserCmd,
        "config init"
    )
    logger.info("init: " .. init)
    local status = os.execute(init)
    
    local create_user = string.format(
        "%s %s %s %s %s %s ",
        filebrowserCmd,
        "users",
        "add",
        "koreader",
        "koreader",
        "--perm.admin"
    )
    logger.info("create_user: " .. create_user)
    local status = os.execute(create_user)
    logger.info("status: " .. status)

    local set_noauth = string.format("%s %s %s %s %s %s %s %s ", binPath, "-d", dbPath, "-c", configPath, "config", "set", "--auth.method=noauth")
    logger.info("set_noauth: ".. set_noauth)
    local status = status + os.execute(set_noauth)
    if status == 0 then
        logger.info("[Filebrowser] User has been reset to koreader and password has been reset to koreader and auth has been reset to noauth.")
    else
        logger.info("[Filebrowser] Failed to reset admin password and auth, status Filebrowser, status: ", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to reset Filebrowser config."),
        }
        UIManager:show(info)
    end
end


function Filebrowser:start()
    self:config()
    -- Since Filebrowser doesn't start as a deamon by default and has no option to
    -- set a pidfile, we launch it using the start-stop-daemon helper. On Kobo and Kindle,
    -- this command is provided by BusyBox:
    -- https://busybox.net/downloads/BusyBox.html#start_stop_daemon
    -- The full version has slightly more options, but seems to be a superset of
    -- the BusyBox version, so it should also work with that:
    -- https://man.cx/start-stop-daemon(8)

    -- Use a pidfile to identify the process later, set --oknodo to not fail if
    -- the process is already running and set --background to start as a
    -- background process. On Filebrowser itself, set the root directory,
    -- and a log file.
    local cmd = string.format(
        "%s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s ",
        "start-stop-daemon -S ",
        " -m -p ", pidFilePath,
        " -o ",
        " -b ",
        " -x ", binPath,
        " -- ", -- filebrowser arguments follow
        filebrowserArgs,
        " -a 0.0.0.0 ", -- ip to bind to (0.0.0.0 means all interfaces)
        " -r ", dataPath,
        " -p ", self.filebrowser_port,
        " -l ", logPath
    )

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
    logger.dbg("[Filebrowser] Opening port: ", filebrowser_port)
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.filebrowser_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.filebrowser_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    logger.info("[Filebrowser] Launching Filebrowser: ", cmd)

    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[Filebrowser] Filebrowser started. Find Filebrowser logs at ", logPath)
        local info = InfoMessage:new {
            timeout = 2,
            text = _("Filebrowser started!")
        }
        UIManager:show(info)
    else
        logger.dbg("[Filebrowser] Failed to start Filebrowser, status: ", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to start Filebrowser."),
        }
        UIManager:show(info)
    end
end

function Filebrowser:isRunning()
    -- Run start-stop-daemon in “stop” mode (-K) with signal 0 (no-op)
    -- to test whether any process matches this pidfile and executable.
    -- Exit code: 0 → at least one process found, 1 → none found.
    local cmd = string.format(
        "start-stop-daemon -K -s 0 -p %s -x %s",
        pidFilePath,
        binPath
    )

    logger.dbg("[Filebrowser] Check if Filebrowser is running: ", cmd)

    local status = os.execute(cmd)

    logger.dbg("[Filebrowser] Running status exit code (0 -> running): ", status)

    return status == 0
end

function Filebrowser:stop()
    -- Use start-stop-daemon -K to stop the process, with --oknodo to exit with
    -- status code 0 if there are no matching processes in the first place.
    local cmd = string.format(
        "%s %s %s %s %s ",
        "start-stop-daemon -K ",
        " -o -p ", pidFilePath,
        " -x ", binPath
    )
    local cmd = string.format(
        "start-stop-daemon -K -o -p %s -x %s",
        pidFilePath,
        binPath
    )
    local cmd = string.format("cat %s | xargs kill", pidFilePath)


    logger.dbg("[Filebrowser] Stopping Filebrowser: ", cmd)

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
    logger.dbg("[Filebrowser] Closing port: ", filebrowser_port)
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.filebrowser_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.filebrowser_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[Filebrowser] Filebrowser stopped.")

        UIManager:show(InfoMessage:new {
            text = _("Filebrowser stopped!"),
            timeout = 2,
        })

        if util.pathExists(pidFilePath) then
            logger.dbg("[Filebrowser] Removing PID file at ", pidFilePath)
            os.remove(pidFilePath)
        end
    else
        logger.dbg("[Filebrowser] Failed to stop Filebrowser, status: ", status)

        UIManager:show(InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to stop Filebrowser.")
        })
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
    Dispatcher:registerAction("toggle_filebrowser",
        { category = "none", event = "ToggleFilebrowser", title = _("Toggle Filebrowser"), general = true })
end

return Filebrowser
