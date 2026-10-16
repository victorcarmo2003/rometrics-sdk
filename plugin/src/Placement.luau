--!strict
-- "Onde colocar o código": the line where the user left the cursor in a script tab, or the end of
-- the script selected in the Explorer. Draws the picker (it updates itself when the cursor moves)
-- and inserts generated code there in one undo step.
local Codegen = require(script.Parent.Codegen)
local Receipts = require(script.Parent.Receipts)
local Registry = require(script.Parent.Registry)
local Studio = require(script.Parent.Studio)
local UI = require(script.Parent.UI)

local Placement = {}

export type Mode = "cursor" | "selected"
export type State = { mode: Mode? }
export type Target = { script: LuaSourceContainer, line: number? }

local function lineText(container: LuaSourceContainer, line: number): string
	local lines = string.split(Studio.getSource(container), "\n")
	local text = lines[line] or ""
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

-- Where the code would go now (nil + reason when there is nowhere to put it).
function Placement.target(state: State): (Target?, string?)
	local cursor = Studio.cursor()
	local selected = Studio.selectedScript()
	local mode = state.mode or (if cursor then "cursor" else "selected")
	if mode == "cursor" then
		if cursor then
			return { script = cursor.script, line = cursor.line }, nil
		end
		return nil, "Abra o script e clique na linha onde a ação acontece."
	end
	if selected then
		return { script = selected, line = nil }, nil
	end
	return nil, "Selecione um script no Explorer."
end

-- Draws the picker into `parent`. `onChange` runs when the mode changes.
function Placement.render(state: State, parent: Instance, onChange: (() -> ())?)
	local holder = UI.column(6)
	holder.Parent = parent

	local function draw()
		UI.clear(holder)
		local cursor = Studio.cursor()
		local selected = Studio.selectedScript()
		local mode = state.mode or (if cursor then "cursor" else "selected")
		local cursorHint = if cursor
			then `<b>{cursor.script.Name}</b>, logo depois da linha {cursor.line}:  <font face="RobotoMono">{UI.escape(
				string.sub(lineText(cursor.script, cursor.line), 1, 60)
			)}</font>`
			else "Abra o script e clique na linha onde a ação acontece. Esta caixa se atualiza sozinha."
		UI.radio({
			{ value = "cursor", label = "Na linha onde está o cursor", hint = cursorHint },
			{
				value = "selected",
				label = "No fim do script selecionado no Explorer",
				hint = if selected then `<b>{selected:GetFullName()}</b>` else "Nenhum script selecionado.",
			},
		}, mode, function(value)
			state.mode = value
			draw()
			if onChange then
				onChange()
			end
		end).Parent =
			holder
	end

	draw()
	local stop = Studio.watchEditor(function()
		if holder.Parent then
			draw()
		end
	end)
	local selectionConnection = game:GetService("Selection").SelectionChanged:Connect(function()
		if holder.Parent then
			draw()
		end
	end)
	holder.AncestryChanged:Connect(function()
		if not holder:IsDescendantOf(game) then
			stop()
			selectionConnection:Disconnect()
		end
	end)
end

export type InsertOptions = {
	-- Builds the code given the name of the SDK variable in the target script.
	build: (sdk: string) -> string,
	label: string,
	-- Registry to save in the same undo step (events created by the assistant).
	registry: Registry.Registry?,
	fallbackSdkPath: string,
}

-- Inserts the code at the current target. Returns nil on success or an error message.
function Placement.insert(app: any, state: State, opts: InsertOptions): string?
	local target, reason = Placement.target(state)
	if not target then
		return reason
	end
	local container = target.script
	local source = Studio.getSource(container)
	local sdk = Receipts.sdkVariable(source)
	local header = if sdk then {} else Studio.sdkHeader(opts.fallbackSdkPath)
	local code = opts.build(sdk or "RoMetrics")
	local newSource, line = Codegen.insert(source, header, code, target.line)
	local function write()
		local ScriptEditorService = game:GetService("ScriptEditorService")
		local ok = pcall(function()
			ScriptEditorService:UpdateSourceAsync(container, function()
				return newSource
			end)
		end)
		if not ok then
			(container :: any).Source = newSource
		end
	end
	local err: string?
	if opts.registry then
		err = app:saveRegistry(opts.registry, opts.label, write)
	else
		err = Studio.editSource(container, newSource, opts.label)
	end
	if err then
		return err
	end
	app:toast(`Código colocado em {container.Name}, linha {line}.`, "success", {
		text = "Desfazer",
		onClick = function()
			app:undo()
		end,
	})
	-- Next insertion goes right below this one (when the code was placed at the cursor).
	if target.line then
		Studio.setCursor(container, line + #string.split(code, "\n") - 1)
	end
	Studio.openScript(app.plugin, container, line)
	return nil
end

-- Code preview + live update helper: returns the frame and a refresh function.
function Placement.preview(build: () -> string): (any, () -> ())
	local frame, setText = UI.code(build())
	return frame, function()
		setText(build())
	end
end

return Placement
