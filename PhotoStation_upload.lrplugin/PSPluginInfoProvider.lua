--[[----------------------------------------------------------------------------

PSPluginInfoProvider.lua
Plugin info provider description for Lightroom PhotoStation Upload
Copyright(c) 2015, Martin Messmer

This file is part of PhotoStation Upload - Lightroom plugin.

PhotoStation Upload is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

PhotoStation Upload is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with PhotoStation Upload.  If not, see <http://www.gnu.org/licenses/>.

PhotoStation Upload uses the following free software to do its job:
	- convert.exe,			see: http://www.imagemagick.org/
	- ffmpeg.exe, 			see: https://www.ffmpeg.org/
	- qt-faststart.exe, 	see: http://multimedia.cx/eggs/improving-qt-faststart/

------------------------------------------------------------------------------]]

-- Lightroom SDK
local LrBinding		= import 'LrBinding'
local LrHttp 		= import 'LrHttp'
local LrView 		= import 'LrView'
local LrPathUtils 	= import 'LrPathUtils'
local LrFileUtils	= import 'LrFileUtils'
local LrPrefs		= import 'LrPrefs'
local LrTasks		= import 'LrTasks'

local bind = LrView.bind
local share = LrView.share
local conditionalItem = LrView.conditionalItem

-- PhotoStation Upload plug-in
require "PSDialogs"
require "PSUtilities"
require "PSPublishSupport"
require "PSUploadTask"
require "PSUpdate"

--============================================================================--

local pluginInfoProvider = {}

-------------------------------------------------------------------------------
-- updatePluginStatus: do some sanity check on dialog settings
local function updatePluginStatus( propertyTable )
	
	local message = nil
	
	repeat
		-- Use a repeat loop to allow easy way to "break" out.
		-- (It only goes through once.)
		
		if propertyTable.PSUploaderPath ~= '' and not PSDialogs.validatePSUploadProgPath(nil, propertyTable.PSUploaderPath) then
			message = LOC "$$$/PSUpload/PluginDialog/Messages/PSUploadPathMissing=Wrong Synology PhotoStation Uploader path." 
			break
		end

		if propertyTable.exiftoolprog ~= '' and not PSDialogs.validateProgram(nil, propertyTable.exiftoolprog) then
			message = LOC "$$$/PSUpload/PluginDialog/Messages/PSUploadPathMissing=Wrong Synology PhotoStation Uploader path." 
			break
		end

	until true
	
	if message then
		propertyTable.message = message
		propertyTable.hasError = true
		propertyTable.hasNoError = false
	else
		propertyTable.message = nil
		propertyTable.hasError = false
		propertyTable.hasNoError = true
	end
	
end

-------------------------------------------------------------------------------
-- pluginInfoProvider.startDialog( propertyTable )
function pluginInfoProvider.startDialog( propertyTable )
	local prefs = LrPrefs.prefsForPlugin()
	
	openLogfile(4)
	writeLogfile(4, "pluginInfoProvider.startDialog\n")
	LrTasks.startAsyncTaskWithoutErrorHandler(PSUpdate.checkForUpdate, "PSUploadCheckForUpdate")

	-- local path to Synology PhotoStation Uploader: required for thumb generation an video handling
	propertyTable.PSUploaderPath = prefs.PSUploaderPath
	if not propertyTable.PSUploaderPath then 
    	propertyTable.PSUploaderPath =  PSConvert.defaultInstallPath
	end
	
	-- exiftool program path: used  for metadata translations on upload
	propertyTable.exiftoolprog = prefs.exiftoolprog
	if not propertyTable.exiftoolprog then
		propertyTable.exiftoolprog = PSExiftoolAPI.defaultInstallPath
	end

	propertyTable:addObserver('PSUploaderPath', updatePluginStatus )
	propertyTable:addObserver('exiftoolprog', updatePluginStatus )

	updatePluginStatus(propertyTable)
end

-------------------------------------------------------------------------------
-- pluginInfoProvider.endDialog( propertyTable )
function pluginInfoProvider.endDialog( propertyTable )
	local prefs = LrPrefs.prefsForPlugin()

	prefs.PSUploaderPath = propertyTable.PSUploaderPath
	prefs.exiftoolprog = propertyTable.exiftoolprog
end

--------------------------------------------------------------------------------
-- pluginInfoProvider.sectionsForTopOfDialog( f, propertyTable )
function pluginInfoProvider.sectionsForTopOfDialog( f, propertyTable )
	local prefs = LrPrefs.prefsForPlugin()
	local updateAvail
	local synops
		
	if prefs.updateAvailable == nil then
		synops = ""
		updateAvail = false
	elseif prefs.updateAvailable == '' or prefs.updateAvailable == pluginVersion then
		synops = LOC "$$$/PSUpload/PluginDialog/NOUPDATE=Plugin is up-to-date"
		updateAvail = false
	else
		synops = LOC "$$$/PSUpload/PluginDialog/UPDATE=" .. "Version " .. prefs.updateAvailable ..  " available!"
		updateAvail = true
	end 
	
	local noUpdateAvailableView = f:view {
		fill_horizontal = 1,
		
		f:row {
			f:static_text {
				title = synops,
				alignment = 'right',
				width = share 'labelWidth'
			},
		},
	}

	local updateAvailableView = f:view {
		fill_horizontal = 1,
		
		f:row {
			f:static_text {
				title = synops,
				alignment = 'right',
				width = share 'labelWidth'
			},

			f:push_button {
				title = LOC "$$$/PSUpload/PluginDialog/GetUpdate=Go to Update URL",
				tooltip = LOC "$$$/PSUpload/PluginDialog/Logfile=Open Update URL in browser",
				alignment = 'right',
				action = function()
					LrHttp.openUrlInBrowser(prefs.downloadUrl)
				end,
			},
		},
	}
	local result = {
	
		{
			title = LOC "$$$/PSUpload/PluginDialog/PsUploadInfo=PhotoStation Upload",
			
			synopsis = synops,

			conditionalItem(updateAvail, updateAvailableView),
			conditionalItem(not updateAvail, noUpdateAvailableView),
		},
	}
	
	return result

end

--------------------------------------------------------------------------------
-- pluginInfoProvider.sectionsForBottomOfDialog( f, propertyTable )
function pluginInfoProvider.sectionsForBottomOfDialog(f, propertyTable )
	local prefs = LrPrefs.prefsForPlugin()
--	local synops
	writeLogfile(4, string.format("sectionsForBottomOfDialog: props: PSUploader %s, exiftool: %s\n", propertyTable.PSUploaderPath, propertyTable.exiftoolprog))
	propertyTable.PSUploaderPath = prefs.PSUploaderPath
	propertyTable.exiftoolprog = prefs.exiftoolprog

	-- local path to Synology PhotoStation Uploader: required for thumb generation an video handling
	if ifnil(propertyTable.PSUploaderPath, '') == '' then 
    	propertyTable.PSUploaderPath = iif(WIN_ENV, 
    									'C:\\\Program Files (x86)\\\Synology\\\Photo Station Uploader',
    									'/Applications/Synology Photo Station Uploader.app/Contents/MacOS') 
	end
	
	-- exiftool program path: used  for metadata translations on upload
	if ifnil(propertyTable.exiftoolprog, '') == '' then
		propertyTable.exiftoolprog = iif(WIN_ENV, 'C:\\\Windows\\\exiftool.exe', '/usr/local/bin/exiftool') 
	end
	writeLogfile(4, string.format("props: PSUploader %s, exiftool: %s\n", propertyTable.PSUploaderPath, propertyTable.exiftoolprog))
		
	return {
		{
    		title = LOC "$$$/PSUpload/PluginDialog/PsSettings=Geneneral Settings",
    		synopsis = 'Set program paths',
			bind_to_object = propertyTable,
			     		
    		f:view {
				fill_horizontal = 1,
				
    			PSDialogs.psUploaderProgView(f, propertyTable),
				PSDialogs.exiftoolProgView(f, propertyTable),
    		}
		}
	}

end

--------------------------------------------------------------------------------

return pluginInfoProvider
