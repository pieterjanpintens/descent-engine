class_name UserMacro
extends MissionMacro

## A MissionMacro made from a MacroTemplate: the editor, the dialog and the engine treat it like any built-in macro, but its inputs and
## what it generates come from data instead of code. build() copies the template's parts, gives the generated variables and prop actions
## their (unique) names, replaces the {tokens} in every text, writes the inputs into the bound fields and adds the result to the mission
## through the MacroContext - so apply / regenerate / remove / hand-edit detection work unchanged.

var template: MacroTemplate


func _init(p_template: MacroTemplate = null) -> void:
	template = p_template


func id() -> String:
	return template.macro_id


func title() -> String:
	return template.title


func description() -> String:
	return template.description


func repeatable() -> bool:
	return template.repeatable


func plan_hint() -> String:
	return template.plan_hint


func fits(target: OutlineNode) -> bool:
	match template.target_type:
		MacroTemplate.TargetType.PROP:
			return target is InteractableEntry and fits_mesh((target as InteractableEntry).mesh_item_name)
		MacroTemplate.TargetType.MONSTER_SPAWN:
			return target is MonsterSpawn
		_:
			return target != null


func fits_mesh(mesh: String) -> bool:
	if template.target_type != MacroTemplate.TargetType.PROP:
		return false
	return template.meshes.is_empty() or template.meshes.has(mesh)


func params() -> Array[MacroParam]:
	return template.params


func problem(values: Dictionary) -> String:
	var broken := template.problems()
	if not broken.is_empty():
		return broken[0]
	for param in template.params:
		if param.allow_empty:
			continue
		var value: Variant = values.get(param.id)
		if param.kind == MacroParam.Kind.LOOT:
			var loot := value as Effect
			if loot == null or (loot.loot_materials.is_empty() and loot.loot_cards.is_empty() and loot.loot_recipes.is_empty() and loot.loot_usable.is_empty()):
				return "Fill in '%s' first." % param.label
		elif param.kind == MacroParam.Kind.MONSTERS:
			var pool := value as Effect
			if pool == null or (pool.spawn_monsters.is_empty() and pool.spawn_group_id == ""):
				return "Fill in '%s' first." % param.label
	return ""


func build(ctx: MacroContext, values: Dictionary) -> void:
	var tokens := {"base": ctx.base_name()}
	var by_id := {}
	for param in template.params:
		by_id[param.id] = param
		_add_param_tokens(tokens, param, values.get(param.id, param.make_default()))

	# 1. Give the generated variables and prop actions their real names, so tokens and references can use them.
	var live := {}  # part key -> the variable declared / the copy of the action or trigger
	var action_ids: Dictionary = {}  # part key -> the id its action will get
	var reserved := {}
	for part in template.parts:
		if part.data == null:
			continue
		match part.kind:
			MacroTemplatePart.Kind.VARIABLE:
				var source := part.data as MissionVariable
				var name := ctx.variable(MacroTokens.text(part.wanted, tokens), source.type, source.default_value)
				tokens["var:" + part.key] = name
				live[part.key] = _declared(ctx.mission, name)
			MacroTemplatePart.Kind.ACTION:
				var wanted := MacroTokens.text(part.wanted, tokens)
				var action_id := ctx.unique_action_id(wanted)
				var suffix := 2
				while reserved.has(action_id):
					action_id = "%s_%d" % [wanted, suffix]
					suffix += 1
				reserved[action_id] = true
				action_ids[part.key] = action_id
				tokens["action:" + part.key] = action_id
				live[part.key] = part.data.duplicate(true)
			MacroTemplatePart.Kind.TRIGGER:
				live[part.key] = part.data.duplicate(true)

	# 2. Tokens into every text of the copies.
	for key in live:
		MacroTokens.substitute(live[key], tokens)

	# 3. Inputs into the bound fields.
	for binding in template.bindings:
		var param: MacroParam = by_id.get(binding.param_id)
		var root: Variant = live.get(binding.part_key())
		if param == null or root == null or binding.fields().is_empty():
			push_warning("UserMacro %s: binding '%s' cannot be applied" % [id(), binding.path])
			continue
		var value: Variant = _bound_value(param, values.get(param.id, param.make_default()), binding, tokens)
		if not MacroBinding.write(root, binding.fields(), value):
			push_warning("UserMacro %s: binding '%s' leads nowhere" % [id(), binding.path])

	# 4. Add the actions and triggers to the mission, in the order of the template.
	for part in template.parts:
		if not live.has(part.key):
			continue
		if part.kind == MacroTemplatePart.Kind.ACTION:
			ctx.adopt_action(live[part.key] as PropAction, action_ids[part.key])
		elif part.kind == MacroTemplatePart.Kind.TRIGGER:
			ctx.trigger(live[part.key] as MissionTrigger)


func _add_param_tokens(tokens: Dictionary, param: MacroParam, value: Variant) -> void:
	if param.kind == MacroParam.Kind.LOOT or param.kind == MacroParam.Kind.MONSTERS:
		return
	tokens[param.id] = _text_of(value)
	if param.kind != MacroParam.Kind.CHOICE:
		return
	for choice in param.choices:
		if typeof(choice[1]) != typeof(value) or choice[1] != value:
			continue
		tokens[param.id + ".label"] = str(choice[0])
		tokens[param.id + ".value"] = _text_of(choice[1])
		if choice.size() > 2 and choice[2] is Dictionary:
			var extras: Dictionary = choice[2]
			for extra in extras:
				tokens["%s.%s" % [param.id, extra]] = str(extras[extra])
		return


func _text_of(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return "yes" if value else "no"
	return str(value)


## The value a binding writes: a Resource input (loot, monsters) is copied and given the binding's overrides and defaults; a number is kept
## inside the input's range.
func _bound_value(param: MacroParam, value: Variant, binding: MacroBinding, tokens: Dictionary) -> Variant:
	if param.kind == MacroParam.Kind.INT:
		return clampi(int(value), param.min_value, param.max_value)
	if not value is Resource:
		return value
	var copy: Resource = (value as Resource).duplicate(true)
	for field in binding.overrides:
		var wanted: Variant = binding.overrides[field]
		copy.set(field, MacroTokens.text(wanted, tokens) if wanted is String else wanted)
	for field in binding.fill_empty:
		var current: Variant = copy.get(field)
		if current == null or (current is String and current == ""):
			var fallback: Variant = binding.fill_empty[field]
			copy.set(field, MacroTokens.text(fallback, tokens) if fallback is String else fallback)
	return copy


func _declared(mission: MissionData, name: String) -> MissionVariable:
	for variable in mission.custom_variables:
		if variable.name == name:
			return variable
	return null
