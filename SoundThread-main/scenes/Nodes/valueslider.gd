extends VBoxContainer

@onready var window := $BreakFileMaker
@onready var editor := window.get_node("AutomationEditor")
signal meta_changed


#Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#$HSplitContainer/ValueLabel.text = str($HSplitContainer/HSlider.value) # initial value
	$HSplitContainer/LineEdit.text = str($HSplitContainer/HSlider.value) # initial value
	$BreakFileMaker.hide()
	editor.connect("automation_updated", Callable(self, "_on_automation_data_received"))


func _on_h_slider_value_changed(value: float) -> void:
	#$HSplitContainer/ValueLabel.text = str(value)
	$HSplitContainer/LineEdit.text = str(value)

	
func _on_line_edit_text_submitted(new_text: String) -> void:
	#check if input from text box is a valid number for the slider if not choose an appropriate value and set that
	if new_text.is_valid_float():
		var new_val = new_text.to_float()
		if new_val > $HSplitContainer/HSlider.max_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.max_value
		elif new_val < $HSplitContainer/HSlider.min_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.min_value
		else:
			$HSplitContainer/HSlider.set_value_no_signal(new_val)
	else:
		$HSplitContainer/LineEdit.text = str($HSplitContainer/HSlider.value)
		


func _on_line_edit_focus_exited() -> void:
	#check if input from text box is a valid number for the slider if not choose and appropriate value and set that
	if $HSplitContainer/LineEdit.text.is_valid_float():
		var new_val = $HSplitContainer/LineEdit.text.to_float()
		if new_val > $HSplitContainer/HSlider.max_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.max_value
		elif new_val < $HSplitContainer/HSlider.min_value:
			$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.min_value
		else:
			$HSplitContainer/HSlider.set_value_no_signal(new_val)
	else:
		$HSplitContainer/LineEdit.text = str($HSplitContainer/HSlider.value)
		

		



		

#check for right click
func _on_h_slider_gui_input(event: InputEvent) -> void:
	if $HSplitContainer/HSlider.get_meta("brk"): #check if slider can take a break file
		if $HSplitContainer/HSlider.has_meta("brk_data"): #check if it already has break data and set menu correctly (used when loading files)
			$HSplitContainer/HSlider/PopupMenu.set_item_text(0, "Edit Automation")
			if $HSplitContainer/HSlider/PopupMenu.get_item_count() <= 1: #if it has automation data but no remove button, add it
				$HSplitContainer/HSlider/PopupMenu.add_item("Remove Automation", 1)
		$HSplitContainer/HSlider/PopupMenu.set_item_disabled(0, false)
	else: #if it can't take automation data updata menu to let user know
		$HSplitContainer/HSlider/PopupMenu.set_item_disabled(0, true)
		$HSplitContainer/HSlider/PopupMenu.set_item_text(0, "Automation is not available for this parameter")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var local_pos = DisplayServer.mouse_get_position()
		# Show popup at global mouse position
		$HSplitContainer/HSlider/PopupMenu.popup()
		$HSplitContainer/HSlider/PopupMenu.set_position(local_pos)
		# Prevent default context menu or input propagation if needed
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		$HSplitContainer/HSlider.value = $HSplitContainer/HSlider.get_meta("default_value")
		accept_event()

func _on_popup_menu_index_pressed(index: int) -> void:
	match index:
		0:
			$BreakFileMaker.position = DisplayServer.mouse_get_position()
			$BreakFileMaker.show()
			if $HSplitContainer/HSlider.has_meta("brk_data"):
				$BreakFileMaker/AutomationEditor.read_automation($HSplitContainer/HSlider.get_meta("brk_data"))
				
		1:
			$HSplitContainer/HSlider.set_meta("brk_data", null)
			$BreakFileMaker/AutomationEditor.reset_automation()
			$HSplitContainer/HSlider.editable = true
			$HSplitContainer/HSlider/PopupMenu.set_item_text(0, "Add Automation")
			$HSplitContainer/HSlider/PopupMenu.remove_item(1)
			_on_meta_changed()

func _on_automation_data_received(data):
	$HSplitContainer/HSlider.set_meta("brk_data", data)
	$HSplitContainer/HSlider.editable = false
	$HSplitContainer/HSlider/PopupMenu.set_item_text(0, "Edit Automation")
	if $HSplitContainer/HSlider/PopupMenu.get_item_count() <= 1:
		$HSplitContainer/HSlider/PopupMenu.add_item("Remove Automation", 1)
	_on_meta_changed()



func _on_save_automation_button_down() -> void:
	$BreakFileMaker.hide()


func _on_save_automation_2_button_down() -> void:
	$BreakFileMaker.hide()


func _on_break_file_maker_close_requested() -> void:
	$BreakFileMaker.hide()

func _on_meta_changed():
	emit_signal("meta_changed")
