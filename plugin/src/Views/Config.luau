--!strict
-- "Config": endpoint, Secret name, SDK path, connection test and dashboard link.
local Studio = require(script.Parent.Parent.Studio)
local Theme = require(script.Parent.Parent.Theme)
local UI = require(script.Parent.Parent.UI)

local View = {
	id = "config",
	title = "Config",
	watches = {},
}

function View.render(app: any, container: Frame)
	local p = UI.palette
	local settings = app.settings
	local scroller = UI.scroll({ Parent = container }, 10, 12)

	local panel, body = UI.section("Conexão")
	UI.controlRow(
		"Endpoint",
		UI.input({
			text = settings:get("endpoint"),
			placeholder = "https://ingest.rometrics.app",
			onCommit = function(text)
				local value = string.gsub(text, "%s", "")
				value = string.gsub(value, "/+$", "")
				if value == "" then
					value = "https://ingest.rometrics.app"
				end
				settings:set("endpoint", value)
			end,
		}),
		"Usado nos snippets. Dev local: http://localhost:4100 (HttpService aceita localhost no Studio)."
	).Parent =
		body
	UI.controlRow(
		"Secret",
		UI.input({
			text = settings:get("secretName"),
			placeholder = "rometrics_key",
			onCommit = function(text)
				settings:set("secretName", if text ~= "" then text else "rometrics_key")
			end,
		}),
		"Nome do Secret (Game Settings > Security > Secrets). O plugin nunca lê nem guarda a chave."
	).Parent =
		body

	local result = UI.label("", { color = p.subText, size = 13, wrap = true })
	local testing = false
	UI.controlRow(
		"Testar",
		UI.column(4, {
			UI.button("Testar conexão", {
				onClick = function()
					if testing then
						return
					end
					testing = true
					result.Text = "Testando…"
					result.TextColor3 = p.subText
					task.spawn(function()
						local ok, message = Studio.testConnection(settings:get("endpoint"))
						testing = false
						if result.Parent then
							result.Text = message
							result.TextColor3 = if ok then p.success else p.danger
						end
					end)
				end,
			}),
			result,
		}),
		"GET {endpoint}/health. O Studio pode pedir permissão de HTTP para o plugin na primeira vez."
	).Parent =
		body
	panel.Parent = scroller

	local sdkPanel, sdk = UI.section("SDK")
	local pathBox = UI.input({
		text = settings:get("sdkPath"),
		placeholder = "ReplicatedStorage.Packages.RoMetrics",
		onCommit = function(text)
			if text ~= "" then
				settings:set("sdkPath", text)
			end
		end,
	})
	pathBox.Size = UDim2.fromScale(0, 1)
	UI.flex().Parent = pathBox
	UI.controlRow(
		"Caminho",
		UI.row(6, {
			pathBox,
			UI.button("Detectar", {
				onClick = function()
					local found = Studio.detectSdkPath()
					if found then
						settings:set("sdkPath", found)
						pathBox.Text = found
						app:toast(`SDK encontrado em {found}`, "success")
					else
						app:toast("ModuleScript RoMetrics (com Tags) não encontrado", "warning")
					end
				end,
			}),
		}),
		"Caminho do ModuleScript do SDK usado no require() dos snippets."
	).Parent =
		sdk
	sdkPanel.Parent = scroller

	local dashPanel, dash = UI.section("Dashboard")
	UI.controlRow(
		"URL",
		UI.input({
			text = settings:get("dashboardUrl"),
			onCommit = function(text)
				if text ~= "" then
					settings:set("dashboardUrl", text)
				end
			end,
		}),
		"Plugins não abrem o navegador: selecione o texto e copie (Ctrl+C)."
	).Parent =
		dash
	dashPanel.Parent = scroller

	local aboutPanel, about = UI.section("Sobre")
	UI.label(
		"Registro: ReplicatedStorage.RoMetricsEvents · Tag: RoMetrics · Atributos: RM_Event, RM_Trigger, RM_Value, RM_Cooldown, RM_Once, RM_Prop_*. "
			.. "Preferências ficam no seu Studio (plugin:SetSetting), não no place.",
		{ wrap = true, color = p.subText, size = Theme.SMALL_SIZE }
	).Parent =
		about
	aboutPanel.Parent = scroller
end

return View
