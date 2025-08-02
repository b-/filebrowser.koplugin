local _ = require("gettext")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DownloadMgr = require("ui/downloadmgr")
local util = require("util")
local Config = require("filebrowser.config")

local Ui = {}

function Ui.showInfoMessage(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout})
end

function Ui.showErrorMessage(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout, icon = "notice-warning"})
end

function Ui.showUsernameDialog()
    local current_username = Config.getSetting(Config.SETTINGS_USERNAME_KEY, "koreader")
    local dialog

    dialog = InputDialog:new{
        title = _("Enter username"),
        input = current_username,
        input_hint = current_username,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local raw_input = dialog:getInputText() or ""
                    local trimmed_input = util.trim(raw_input)

                    if trimmed_input ~= "" then
                        Config.saveSetting(Config.SETTINGS_USERNAME_KEY, trimmed_input)
                        UIManager:close(dialog)
                    else
                        Ui.showErrorMessage("Username cannot be blank", 5)
                    end
                end,
            },
        }}
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ui.showPasswordDialog()
    local current_password = Config.getSetting(Config.SETTINGS_PASSWORD_KEY, "abc123")
    local dialog

    dialog = InputDialog:new{
        title = _("Enter password"),
        input = current_password,
        input_hint = current_password,
        text_type = "password",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local raw_input = dialog:getInputText() or ""
                    local trimmed_input = util.trim(raw_input)

                    if trimmed_input ~= "" then
                        Config.saveSetting(Config.SETTINGS_PASSWORD_KEY, trimmed_input)
                        UIManager:close(dialog)
                    else
                        Ui.showErrorMessage("Password cannot be blank", 5)
                    end
                end,
            },
        }}
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ui.showPortDialog()
    local current_port = Config.getSetting(Config.SETTINGS_PORT_KEY, 80)
    local dialog

    dialog = InputDialog:new{
        title = _("Choose port number"),
        input = current_port,
        input_type = "number",
        input_hint = current_port,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local raw_input = dialog:getInputText() or "80"
                    local new_port = tonumber(raw_input)

                    if new_port and new_port >= 0 then
                        Config.saveSetting(Config.SETTINGS_PORT_KEY, new_port)
                        UIManager:close(dialog)
                    else
                        Ui.showErrorMessage("Port must be a positive number", 5)
                    end
                end,
            },
        },},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ui.showRootDirectoryDialog()
    local currentDir = Config.getSetting(Config.SETTINGS_ROOT_DIRECTORY_KEY, Config.DEFAULT_DIRECTORY_FALLBACK)
    DownloadMgr:new{
        title = _("Select root directory"),
        onConfirm = function(path)
            if path then
                Config.saveSetting(Config.SETTINGS_ROOT_DIRECTORY_KEY, path)
            else
                Ui.showErrorMessage(_("No directory selected.", 5))
            end
        end,
    }:chooseDir(currentDir)
end

function Ui.showClearAllSettingsDialog()
    UIManager:show(ConfirmBox:new{
        text = _("Clear all settings?"),
        ok_text = _("Clear"),  -- ok_text defaults to _("OK")
        ok_callback = function()
            Config.deleteAllSettings()
        end,
    })
end

return Ui
