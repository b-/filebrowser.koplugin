local util = require("util")

local Config = {}

Config.SETTINGS_USERNAME_KEY = "filebrowser_username"
Config.SETTINGS_PASSWORD_KEY = "filebrowser_password"
Config.SETTINGS_PORT_KEY = "filebrowser_port"
Config.SETTINGS_ROOT_DIRECTORY_KEY = "filebrowser_root_directory"

Config.DEFAULT_DIRECTORY_FALLBACK = G_reader_settings:readSetting("home_dir")
    or require("apps/filemanager/filemanagerutil").getDefaultDir()

function Config.getSetting(key, default)
    return G_reader_settings:readSetting(key) or default
end

function Config.saveSetting(key, value)
    if type(value) == "string" then
        G_reader_settings:saveSetting(key, util.trim(value))
    else
        G_reader_settings:saveSetting(key, value)
    end
end

function Config.deleteSetting(key)
    G_reader_settings:delSetting(key)
end

function Config.deleteAllSettings()
    Config.deleteSetting(Config.SETTINGS_USERNAME_KEY)
    Config.deleteSetting(Config.SETTINGS_PASSWORD_KEY)
    Config.deleteSetting(Config.SETTINGS_PORT_KEY)
    Config.deleteSetting(Config.SETTINGS_ROOT_DIRECTORY_KEY)
end

return Config
