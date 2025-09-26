extends GraphEdit

var control_script
var graph_edit
var open_help
var multiple_connections
var selected_nodes = {} #used to track which nodes in the GraphEdit are selected
var copied_nodes_data = [] #stores node data on ctrl+c
var copied_connections = [] #stores all connections on ctrl+c
var node_data = {} #stores json with all nodes in it
var valueslider = preload("res://scenes/Nodes/valueslider.tscn") #slider scene for use in nodes
var addremoveinlets = preload("res://scenes/Nodes/addremoveinlets.tscn") #add remove inlets scene for use in nodes
var node_logic = preload("res://scenes/Nodes/node_logic.gd") #load the script logic
var selected_cables:= [] #used to track which cables are selected for changing colour and for deletion
var theme_background #used to track if the theme has changed and if so change the cable selection colour
var theme_custom_background
var high_contrast_cables


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	snapping_enabled = false
	show_grid = false
	zoom = 0.9
	#parse json
	var file = FileAccess.open("res://scenes/main/process_help.json", FileAccess.READ)
	if file:
		var result = JSON.parse_string(file.get_as_text())
		if typeof(result) == TYPE_DICTIONARY:
			node_data = result
		else:
			push_error("Invalid JSON")
			
	var interface_settings = ConfigHandler.load_interface_settings()
	theme_background = interface_settings.theme
	theme_custom_background = interface_settings.theme_custom_colour
	high_contrast_cables = interface_settings.high_contrast_selected_cables
	set_cable_colour(interface_settings.theme)

func init(main_node: Node, graphedit: GraphEdit, openhelp: Callable, multipleconnections: Window) -> void:
	control_script = main_node
	graph_edit = graphedit
	open_help = openhelp
	multiple_connections = multipleconnections

func _make_node(command: String, skip_undo_redo := false) -> GraphNode:
	if node_data.has(command):
		var node_info = node_data[command]
		
		if node_info.get("category", "") == "utility":
			#Find utility node with matching name and create a version of it in the graph edit
			#and position it close to the origin right click to open the menu
			var effect: GraphNode = Nodes.get_node(NodePath(command)).duplicate()
			effect.name = command
			add_child(effect, true)
			if command == "outputfile":
				effect.init() #initialise ui from user prefs
			effect.connect("open_help", open_help)
			if effect.has_signal("node_moved"):
				effect.node_moved.connect(_auto_link_nodes)
			effect.set_position_offset((control_script.effect_position + graph_edit.scroll_offset) / graph_edit.zoom) #set node to current mouse position in graph edit
			_register_inputs_in_node(effect) #link sliders for changes tracking
			_register_node_movement() #link nodes for tracking position changes for changes tracking

			control_script.changesmade = true

			if not skip_undo_redo:
				# Remove node with UndoRedo
				control_script.undo_redo.create_action("Add Node")
				control_script.undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(effect))
				control_script.undo_redo.add_undo_method(Callable(effect, "queue_free"))
				control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
				control_script.undo_redo.commit_action()
			
			return effect
		else: #auto generate node from json
			#get the title to display at the top of the node
			var title 
			if node_info.get("category", "") == "pvoc":
				title = "%s: %s" % [node_info.get("category", "").to_upper(), node_info.get("title", "")]
			else:
				title = "%s: %s" % [node_info.get("subcategory", "").to_pascal_case(), node_info.get("title", "")]
			var shortdescription = node_info.get("short_description", "") #for tooltip
			
			#get node properties
			var stereo = node_info.get("stereo", false)
			var outputisstereo = node_info.get("outputisstereo", false) #used to identify the few processes that always output in stereo making the thread need to be stereo
			var inputs = JSON.parse_string(node_info.get("inputtype", ""))
			var outputs = JSON.parse_string(node_info.get("outputtype", ""))
			var portcount = max(inputs.size(), outputs.size())
			var parameters = node_info.get("parameters", {})
			
			var graphnode = GraphNode.new()
			
			#set meta data for the process
			graphnode.set_meta("command", command)
			graphnode.set_meta("stereo_input", stereo)
			graphnode.set_meta("output_is_stereo", outputisstereo)
			if inputs.size() == 0 and outputs.size() > 0:
				graphnode.set_meta("input", true)
			else:
				graphnode.set_meta("input", false)
			
			#adjust size, position and title of the node
			graphnode.title = title
			graphnode.tooltip_text = shortdescription
			graphnode.size.x = 306
			graphnode.custom_minimum_size.y = 80
			graphnode.set_position_offset((control_script.effect_position + graph_edit.scroll_offset) / graph_edit.zoom)
			graphnode.name = command
			
			#add one small control node to the top of the node to aline first inlet to top
			var first_inlet = Control.new()
			graphnode.add_child(first_inlet)
			
			if parameters.is_empty():
				var noparams = Label.new()
				noparams.text = "No adjustable parameters"
				noparams.custom_minimum_size.x = 270
				noparams.custom_minimum_size.y = 57
				noparams.vertical_alignment = 1
				
				graphnode.add_child(noparams)
			else:
				for param_key in parameters.keys():
					var param_data = parameters[param_key]
					if param_data.get("uitype", "") == "hslider":
						#instance the slider scene
						var slider = valueslider.instantiate()
						
						#get slider text
						var slider_label = param_data.get("paramname", "")
						var slider_tooltip  = param_data.get("paramdescription", "")
						
						#name slider
						slider.name = slider_label.replace(" ", "")
						
						#get slider properties
						var brk = param_data.get("automatable", false)
						var time = param_data.get("time", false)
						var outputduration = param_data.get("outputduration", false)
						var min = param_data.get("min", false)
						var max = param_data.get("max", false)
						var flag = param_data.get("flag", "")
						var fftwindowsize = param_data.get("fftwindowsize", false)
						var fftwindowcount = param_data.get("fftwindowcount", false)
						var minrange = param_data.get("minrange", 0)
						var maxrange = param_data.get("maxrange", 10)
						var step = param_data.get("step", 0.01)
						var value = param_data.get("value", 1)
						var exponential = param_data.get("exponential", false)
						
						#set labels and tooltips
						slider.get_node("SliderLabel").text = slider_label
						if brk == true:
							slider.get_node("SliderLabel").text += "~"
						slider.tooltip_text = slider_tooltip
						slider.get_node("SliderLabel").tooltip_text = slider_tooltip
						
						#set meta data
						var hslider = slider.get_node("HSplitContainer/HSlider")
						hslider.set_meta("brk", brk)
						hslider.set_meta("time", time)
						hslider.set_meta("min", min)
						hslider.set_meta("max", max)
						hslider.set_meta("flag", flag)
						hslider.set_meta("default_value", value)
						hslider.set_meta("fftwindowsize", fftwindowsize)
						hslider.set_meta("fftwindowcount", fftwindowcount)
						
						#set slider params
						hslider.min_value = minrange
						hslider.max_value = maxrange
						hslider.step = step
						hslider.value = value
						hslider.exp_edit = exponential
						
						#add output duration meta to main if true
						if outputduration:
							graphnode.set_meta("outputduration", value)
							
						#scale automation window
						var automationwindow = slider.get_node("BreakFileMaker")
						if automationwindow.content_scale_factor < control_script.uiscale:
							automationwindow.size = automationwindow.size * control_script.uiscale
							automationwindow.content_scale_factor = control_script.uiscale
						
						graphnode.add_child(slider)
					
					elif param_data.get("uitype", "") == "checkbutton":
						#make a checkbutton
						var checkbutton = CheckButton.new()
						
						#get button text
						var checkbutton_label = param_data.get("paramname", "")
						var checkbutton_tooltip  = param_data.get("paramdescription", "")
						
						#name checkbutton
						checkbutton.name = checkbutton_label.replace(" ", "")
						
						#get checkbutton properties
						var flag = param_data.get("flag", "")
						
						checkbutton.text = checkbutton_label
						checkbutton.tooltip_text = checkbutton_tooltip
						
						var checkbutton_pressed = param_data.get("value", "false")
						#get button state
						if str(checkbutton_pressed).to_lower() == "true":
							checkbutton.button_pressed = true
							
						#set checkbutton meta
						checkbutton.set_meta("flag", flag)
						
						graphnode.add_child(checkbutton)
					elif param_data.get("uitype", "") == "optionbutton":
						#make optionbutton and label
						var label = Label.new()
						var optionbutton = OptionButton.new()
						var margin = MarginContainer.new()
						
						#get button text
						var optionbutton_label = param_data.get("paramname", "")
						var optionbutton_tooltip  = param_data.get("paramdescription", "")
						
						#name optionbutton
						optionbutton.name = optionbutton_label.replace(" ", "").to_lower()
						
						#add meta flag if this is a sample rate selector for running thread sample rate checks
						if optionbutton.name == "samplerate":
							graphnode.set_meta("node_sets_sample_rate", true)
						
						#get optionbutton properties
						var options = JSON.parse_string(param_data.get("step", ""))
						var value = param_data.get("value", 1)
						var flag = param_data.get("flag", "")
						
						label.text = optionbutton_label
						optionbutton.tooltip_text = optionbutton_tooltip
						
						#fill option button
						for option in options:
							optionbutton.add_item(str(option))
						
						
						#select the given id
						optionbutton.select(int(value))
						
						#set flag meta
						optionbutton.set_meta("flag", flag)
						
						#add margin size for vertical spacing
						margin.add_theme_constant_override("margin_bottom", 4)
						
						graphnode.add_child(label)
						graphnode.add_child(optionbutton)
						graphnode.add_child(margin)
					elif param_data.get("uitype", "") == "addremoveinlets":
						var addremove = addremoveinlets.instantiate()
						addremove.name = "addremoveinlets"
						
						#get parameters
						var min_inlets = param_data.get("minrange", 0)
						var max_inlets = param_data.get("maxrange", 10)
						var default_inlets = param_data.get("value", 1)
						
						#set meta
						addremove.set_meta("min", min_inlets)
						addremove.set_meta("max", max_inlets)
						addremove.set_meta("default", default_inlets)
						
						graphnode.add_child(addremove)
				
				control_script.changesmade = true
			
			#add control nodes if number of child nodes is lower than the number of inlets or outlets
			for i in range(portcount - graphnode.get_child_count()):
				#add a number of control nodes equal to whatever is higher input or output ports
				var control = Control.new()
				control.custom_minimum_size.y = 57
				graphnode.add_child(control)
				if graphnode.has_node("addremoveinlets"):
					graphnode.move_child(graphnode.get_node("addremoveinlets"), graphnode.get_child_count() - 1)
			
			#add ports
			for i in range(portcount):
				#check if input or output is enabled
				var enable_input = i < inputs.size()
				var enable_output = i < outputs.size()
				
				#get the colour of the port for time or pvoc ins/outs
				var input_colour = Color("#ffffff90")
				var output_colour = Color("#ffffff90")
				
				if enable_input:
					if inputs[i] == 1:
						input_colour = Color("#000000b0")
				if enable_output:
					if outputs[i] == 1:
						output_colour = Color("#000000b0")
				
				#enable and set ports
				if enable_input == true and enable_output == false:
					graphnode.set_slot(i, true, inputs[i], input_colour, false, 0, output_colour)
				elif enable_input == false and enable_output == true:
					graphnode.set_slot(i, false, 0, input_colour, true, outputs[i], output_colour)
				elif enable_input == true and enable_output == true:
					graphnode.set_slot(i, true, inputs[i], input_colour, true, outputs[i], output_colour)
				else:
					pass
			
			graphnode.set_script(node_logic)
			
			add_child(graphnode, true)
			graphnode.connect("open_help", open_help)
			graphnode.connect("inlet_removed", Callable(self, "on_inlet_removed"))
			graphnode.node_moved.connect(_auto_link_nodes)
			_register_inputs_in_node(graphnode) #link sliders for changes tracking
			_register_node_movement() #link nodes for tracking position changes for changes tracking
			
			if not skip_undo_redo:
				# Remove node with UndoRedo
				control_script.undo_redo.create_action("Add Node")
				control_script.undo_redo.add_undo_method(Callable(graph_edit, "remove_child").bind(graphnode))
				control_script.undo_redo.add_undo_method(Callable(graphnode, "queue_free"))
				control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
				control_script.undo_redo.commit_action()
			
			return graphnode
			
	return null
	

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	#check if this is trying to connect a node to itself and skip
	if from_node == to_node:
		return
	
	var to_graph_node = get_node(NodePath(to_node))
	var from_graph_node = get_node(NodePath(from_node))

	# Get the type of the ports
	var to_port_type = to_graph_node.get_input_port_type(to_port)
	var from_port_type = from_graph_node.get_output_port_type(from_port)
	
	#skip if this isnt a valid connection
	if to_port_type != from_port_type:
		return

	# If port type is 1 and already has a connection, reject the request
	if to_port_type == 1:
		var connections = get_connection_list()
		var existing_connections = 0

		for conn in connections:
			if conn.to_node == to_node and conn.to_port == to_port:
				existing_connections += 1
				if existing_connections >= 1:
					var interface_settings = ConfigHandler.load_interface_settings()
					if interface_settings.disable_pvoc_warning == false:
						multiple_connections.popup_centered()
					return
					
	if from_graph_node.get_meta("command") == "inputfile" and to_graph_node.get_meta("command") == "outputfile":
		return

	# If no conflict, allow the connection
	connect_node(from_node, from_port, to_node, to_port)
	control_script.changesmade = true

func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	control_script.changesmade = true

func _on_graph_edit_node_selected(node: Node) -> void:
	selected_nodes[node] = true

func _on_graph_edit_node_deselected(node: Node) -> void:
	selected_nodes[node] = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			_on_graph_edit_delete_nodes_request(PackedStringArray(selected_nodes.keys().filter(func(k): return selected_nodes[k])))
			pass

func _on_graph_edit_delete_nodes_request(nodes: Array[StringName]) -> void:
	control_script.undo_redo.create_action("Delete Nodes (Undo only)")

	for node_name in nodes:
		var node: GraphNode = get_node_or_null(NodePath(node_name))
		if node and is_instance_valid(node):
			# Skip output nodes
			if node.get_meta("command") == "outputfile":
				continue

			# Store duplicate and state for undo
			var node_data = node.duplicate()
			var position = node.position_offset

			# Store all connections for undo
			var conns := []
			for con in get_connection_list():
				if con["to_node"] == node.name or con["from_node"] == node.name:
					conns.append(con)

			# Delete
			remove_connections_to_node(node)
			node.queue_free()
			control_script.changesmade = true

			# Register undo restore
			control_script.undo_redo.add_undo_method(Callable(self, "add_child").bind(node_data, true))
			control_script.undo_redo.add_undo_method(Callable(node_data, "set_position_offset").bind(position))
			for con in conns:
				control_script.undo_redo.add_undo_method(Callable(self, "connect_node").bind(
					con["from_node"], con["from_port"],
					con["to_node"], con["to_port"]
				))
			control_script.undo_redo.add_undo_method(Callable(self, "set_node_selected").bind(node_data, true))
			control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
			control_script.undo_redo.add_undo_method(Callable(self, "_register_inputs_in_node").bind(node_data))
			control_script.undo_redo.add_undo_method(Callable(self, "_register_node_movement"))

	selected_nodes = {}

	control_script.undo_redo.commit_action()

func set_node_selected(node: Node, selected: bool) -> void:
	selected_nodes[node] = selected
#
func remove_connections_to_node(node):
	for con in get_connection_list():
		if con["to_node"] == node.name or con["from_node"] == node.name:
			disconnect_node(con["from_node"], con["from_port"], con["to_node"], con["to_port"])
			control_script.changesmade = true
			
#copy and paste nodes with vertical offset on paste
func copy_selected_nodes():
	copied_nodes_data.clear()
	copied_connections.clear()

	# Store selected nodes and their slider values
	for node in get_children():
		# Check if the node is selected and not an 'inputfile' or 'outputfile'
		if node is GraphNode and selected_nodes.get(node, false):
			if node.get_meta("command") == "outputfile":
				continue  # Skip these nodes

			var node_data = {
				"name": node.name,
				"type": node.get_class(),
				"offset": node.position_offset,
				"slider_values": {}
			}

			for child in node.get_children():
				if child is HSlider or child is VSlider:
					node_data["slider_values"][child.name] = child.value

			copied_nodes_data.append(node_data)

	# Store connections between selected nodes
	for conn in get_connection_list():
		var from_ref = get_node_or_null(NodePath(conn["from_node"]))
		var to_ref = get_node_or_null(NodePath(conn["to_node"]))

		var is_from_selected = from_ref != null and selected_nodes.get(from_ref, false)
		var is_to_selected = to_ref != null and selected_nodes.get(to_ref, false)

		# Skip if any of the connected nodes are 'inputfile' or 'outputfile'
		if (from_ref != null and (from_ref.get_meta("command") == "inputfile" or from_ref.get_meta("command") == "outputfile")) or (to_ref != null and (to_ref.get_meta("command") == "inputfile" or to_ref.get_meta("command") == "outputfile")):
			continue

		if is_from_selected and is_to_selected:
			# Store connection as dictionary
			var conn_data = {
				"from_node": conn["from_node"],
				"from_port": conn["from_port"],
				"to_node": conn["to_node"],
				"to_port": conn["to_port"]
			}
			copied_connections.append(conn_data)

func paste_copied_nodes():
	if copied_nodes_data.is_empty():
		return

	var name_map = {}
	var pasted_nodes = []

	# Step 1: Find topmost and bottommost Y of copied nodes
	var min_y = INF
	var max_y = -INF
	for node_data in copied_nodes_data:
		var y = node_data["offset"].y
		min_y = min(min_y, y)
		max_y = max(max_y, y)

	# Step 2: Decide where to paste the group
	var base_y_offset = max_y + 350  # Pasting below the lowest node

	# Step 3: Paste nodes, preserving vertical layout
	for node_data in copied_nodes_data:
		var original_node = get_node_or_null(NodePath(node_data["name"]))
		if not original_node:
			continue

		var new_node = original_node.duplicate()
		new_node.name = node_data["name"] + "_copy_" + str(randi() % 10000)

		var relative_y = node_data["offset"].y - min_y
		new_node.position_offset = Vector2(
			node_data["offset"].x,
			base_y_offset + relative_y
		)
		

		# Restore sliders
		for child in new_node.get_children():
			if child.name in node_data["slider_values"]:
				child.value = node_data["slider_values"][child.name]

		add_child(new_node, true)
		new_node.connect("open_help", open_help)
		new_node.node_moved.connect(_auto_link_nodes)
		_register_inputs_in_node(new_node) #link sliders for changes tracking
		_register_node_movement() # link nodes for changes tracking
		name_map[node_data["name"]] = new_node.name
		pasted_nodes.append(new_node)


	# Step 4: Reconnect new nodes
	for conn_data in copied_connections:
		var new_from = name_map.get(conn_data["from_node"], null)
		var new_to = name_map.get(conn_data["to_node"], null)

		if new_from and new_to:
			connect_node(new_from, conn_data["from_port"], new_to, conn_data["to_port"])

	# Step 5: Select pasted nodes
	for pasted_node in pasted_nodes:
		set_selected(pasted_node)
		selected_nodes[pasted_node] = true
	
	control_script.changesmade = true
	
	# Remove node with UndoRedo
	control_script.undo_redo.create_action("Paste Nodes")
	for pasted_node in pasted_nodes:
		control_script.undo_redo.add_undo_method(Callable(self, "remove_child").bind(pasted_node))
		control_script.undo_redo.add_undo_method(Callable(pasted_node, "queue_free"))
		control_script.undo_redo.add_undo_method(Callable(self, "remove_connections_to_node").bind(pasted_node))
		control_script.undo_redo.add_undo_method(Callable(self, "_track_changes"))
	control_script.undo_redo.commit_action()
	

#functions for tracking changes for save state detection
func _register_inputs_in_node(node: Node):
	#tracks input to nodes sliders and codeedit to track if patch is saved
	# Track Sliders
	for slider in node.find_children("*", "HSlider", true, false):
		# Create a Callable to the correct method
		var callable = Callable(self, "_on_any_slider_changed")
		# Check if it's already connected, and connect if not
		if not slider.is_connected("value_changed", callable):
			slider.connect("value_changed", callable)
	
	for slider in node.find_children("*", "VBoxContainer", true, false):
		# Also connect to meta_changed if the slider has that signal
		if slider.has_signal("meta_changed"):
			var meta_callable = Callable(self, "_on_any_slider_meta_changed")
			if not slider.is_connected("meta_changed", meta_callable):
				slider.connect("meta_changed", meta_callable)
		
	# Track CodeEdits
	for editor in node.find_children("*", "CodeEdit", true, false):
		var callable = Callable(self, "_on_any_input_changed")
		if not editor.is_connected("text_changed", callable):
			editor.connect("text_changed", callable)
			
func _on_any_slider_meta_changed():
	control_script.changesmade = true
	print("Meta changed in slider")
	
func _register_node_movement():
	for graphnode in get_children():
		if graphnode is GraphNode:
			var callable = Callable(self, "_on_graphnode_moved")
			if not graphnode.is_connected("position_offset_changed", callable):
				graphnode.connect("position_offset_changed", callable)

func _on_graphnode_moved():
	control_script.changesmade = true
	
func _on_any_slider_changed(value: float) -> void:
	control_script.changesmade = true
	
func _on_any_input_changed():
	control_script.changesmade = true

func _track_changes():
	control_script.changesmade = true


func _on_copy_nodes_request() -> void:
	graph_edit.copy_selected_nodes()
	#get_viewport().set_input_as_handled()


func _on_paste_nodes_request() -> void:
	control_script.simulate_mouse_click() #hacky fix to stop tooltips getting stuck
	await get_tree().process_frame
	graph_edit.paste_copied_nodes()

func on_inlet_removed(node_name: StringName, port_index: int):
	var connections = get_connection_list()
	for conn in connections:
		if conn.to_node == node_name and conn.to_port == port_index:
			disconnect_node(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
			
func _swap_node(old_node: GraphNode, command: String):
	#store the position and name of the node to be replaced
	var position = old_node.position_offset
	var old_name = old_node.name
	#gather all connections in the graph
	var connections = get_connection_list()
	var related_connections = []
	
	#filter the connections to get just those connected to the node to be replaced
	for conn in connections:
		if conn.from_node == old_name or conn.to_node == old_name:
			related_connections.append(conn)
			
	#delete the old node
	_on_graph_edit_delete_nodes_request([old_node.name])
	
	#make the new node and reposition it to the location of the old node
	var new_node = _make_node(command)
	new_node.position_offset = position
	
	#filter through all the connections to the old node
	for conn in related_connections:
		var from = conn.from_node
		var from_port = conn.from_port
		var to = conn.to_node
		var to_port = conn.to_port
		
		#where the old node is referenced replace it with the name of the new node
		if from == old_name:
			from = new_node.name
		if to == old_name:
			to = new_node.name
			
		#check that the ports being connected to/from on the new node actually exist
		if (from == new_node.name and new_node.is_slot_enabled_right(from_port)) or (to == new_node.name and new_node.is_slot_enabled_left(to_port)):
			#check the two ports are the same type
			if _same_port_type(from, from_port, to, to_port):
				_on_connection_request(from, from_port, to, to_port)
	
func _connect_to_clicked_node(clicked_node: GraphNode, command: String):
	var new_node_position = clicked_node.position_offset + Vector2(clicked_node.size.x + 50, 0)
	#make the new node and reposition it to right of the node to connect to
	var new_node = _make_node(command)
	new_node.position_offset = new_node_position
	
	var clicked_node_has_outputs = clicked_node.get_output_port_count() > 0
	var new_node_has_inputs = new_node.get_input_port_count() > 0
	
	if clicked_node_has_outputs and new_node_has_inputs:
		if _same_port_type(clicked_node.name, 0, new_node.name, 0):
			_on_connection_request(clicked_node.name, 0, new_node.name, 0)


func _on_gui_input(event: InputEvent) -> void:
	#check if this is an unhandled mouse click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		
		#get dictionary of a cable if nearby
		var closest_connection = get_closest_connection_at_point(get_local_mouse_position())
		
		#check if there is anything in that dictionary
		if closest_connection.size() > 0:
			#check if the background has changed colour for highlighted cable colour
			var interface_settings = ConfigHandler.load_interface_settings()
			if interface_settings.theme != theme_background or interface_settings.theme_custom_colour != theme_custom_background or interface_settings.high_contrast_selected_cables != high_contrast_cables:
				#if bg has changed colour since last cable highlight reset to new bg and change cable colour
				theme_background = interface_settings.theme
				theme_custom_background = interface_settings.theme_custom_colour
				high_contrast_cables = interface_settings.high_contrast_selected_cables
				set_cable_colour(interface_settings.theme)
				
			#get details of nearby cable
			var from_node = closest_connection.from_node
			var from_port = closest_connection.from_port
			var to_node = closest_connection.to_node
			var to_port = closest_connection.to_port
			
			#check if user was holding shift and if so allow for multiple cables to be selected
			if event.shift_pressed:
				selected_cables.append(closest_connection)
				set_connection_activity(from_node, from_port, to_node, to_port, 1)
			
			#if user double clicked unselect all cables and delete the nearest cable
			elif event.double_click:
					for conn in selected_cables:
						set_connection_activity(conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0)
					_on_graph_edit_disconnection_request(from_node, from_port, to_node, to_port)
					
			#else just a single click, unselect any previously selected cables and select just the nearest
			else:
				for conn in selected_cables:
					set_connection_activity(conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0)
				selected_cables = []
				selected_cables.append(closest_connection)
				set_connection_activity(from_node, from_port, to_node, to_port, 1)
		
		#user didnt click on a cable unselect all cables
		else:
			for conn in selected_cables:
				set_connection_activity(conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0)
			selected_cables = []
			
	#if this is an unhandled delete check if there are any cables selected and deleted them
	if event is InputEventKey and event.pressed:
		if (event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE) and selected_cables.size() > 0:
			for conn in selected_cables:
				_on_graph_edit_disconnection_request(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
				selected_cables = []
	
func set_cable_colour(theme_colour: int):
	var background_colour
	var cable_colour
	var interface_settings = ConfigHandler.load_interface_settings()
	match theme_colour:
		0:
			background_colour = Color("#2f4f4e")
		1:
			background_colour = Color("#000807")
		2:
			background_colour = Color("#98d4d2")
		3:
			background_colour = Color(interface_settings.theme_custom_colour)
			
	if interface_settings.high_contrast_selected_cables:
		#180 colour shift from background and up sv
		cable_colour = Color.from_hsv(fposmod(background_colour.h + 0.5, 1.0), clamp(background_colour.s + 0.2, 0, 1), clamp(background_colour.v + 0.2, 0, 1))
		var luminance = 0.299 * background_colour.r + 0.587 * background_colour.g + 0.114 * background_colour.b
		if luminance > 0.5 and cable_colour.get_luminance() > 0.5:
			cable_colour = cable_colour.darkened(0.4)
		elif luminance <= 0.5 and cable_colour.get_luminance() < 0.5:
			#increase s and v again
			cable_colour = Color.from_hsv(cable_colour.h, clamp(cable_colour.s + 0.2, 0, 0.8), clamp(cable_colour.v + 0.2, 0, 0.8))
	else:
		#keep hue but up saturation and variance
		cable_colour = Color.from_hsv(background_colour.h, clamp(background_colour.s + 0.2, 0, 1), clamp(background_colour.v + 0.2, 0, 1))
	#overide theme for cable highlight
	add_theme_color_override("activity", cable_colour)

func _auto_link_nodes(node: GraphNode, rect: Rect2):
	#get all cables that overlap with the node being moved
	var potential_connections = get_connections_intersecting_with_rect(rect)
	
	#if there are anyoverlapping and shift is being held down then
	if potential_connections.size() > 0 and Input.is_action_pressed("auto_link_nodes"):
		#sort through all the cables that overlap
		for conn in potential_connections:
			#get their info
			var new_node_name = node.name
			var new_node_has_inputs = node.get_input_port_count() > 0
			var new_node_has_outputs = node.get_output_port_count() > 0
			var from = conn.from_node
			var from_port = conn.from_port
			var to = conn.to_node
			var to_port = conn.to_port
			
			if new_node_has_inputs and new_node_has_outputs:
				#connect in the middle of the two nodes if they are the same port type
				var from_matches = _same_port_type(from, from_port, new_node_name, 0)
				var to_matches = _same_port_type(new_node_name, 0, to, to_port)
				
				if from_matches:
					_on_connection_request(from, from_port, new_node_name, 0)
				if to_matches:
					_on_connection_request(new_node_name, 0, to, to_port)
				#skip deleting cables if they are the same as the node being dragged or the ports don't match
				if from_matches and to_matches and from != new_node_name and to != new_node_name:
					_on_graph_edit_disconnection_request(from, from_port, to, to_port)

			elif new_node_has_inputs:
				#only has inputs check if the ports match and if they do connect but leave original connection in place
				if _same_port_type(from, from_port, new_node_name, 0):
					_on_connection_request(from, from_port, new_node_name, 0)
					
			elif new_node_has_outputs:
				#only has outputs check if the ports match and if they do connect but leave original connection in place
				if _same_port_type(new_node_name, 0, to, to_port):
					_on_connection_request(new_node_name, 0, to, to_port)

# function for checking if an inlet and an outlet are the same type
func _same_port_type(from: String, from_port: int, to: String, to_port: int) -> bool:
	var from_node = get_node_or_null(NodePath(from))
	var to_node = get_node_or_null(NodePath(to))
	#safety incase one somehow no longer exists
	if from_node != null and to_node != null:
		#check if the port types are the same e.g. both time or both pvoc
		if from_node.get_output_port_type(from_port) == to_node.get_input_port_type(to_port):
			return true
		else:
			return false
	else:
		return false
