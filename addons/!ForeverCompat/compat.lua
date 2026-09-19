-- !ForeverCompat - shims for globals the mainline engine removed. Each one is only defined
-- when the client does not provide it, and behaves exactly like the original FrameXML helper.

-- FrameXML's SetDesaturation(texture, desaturation) was a thin wrapper around
-- Texture:SetDesaturated; old AceGUI-3.0 CheckBox widgets (v26, bundled by idTip) still call it.
if not SetDesaturation then
	function SetDesaturation(texture, desaturation)
		if texture and texture.SetDesaturated then
			texture:SetDesaturated(desaturation and true or false)
		end
	end
end
