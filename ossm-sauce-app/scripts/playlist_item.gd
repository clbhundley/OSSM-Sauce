extends Panel

func set_active():
	$Icon.show()
	$Animation.play('Spin')

func select():
	$Label.self_modulate = Color.SANDY_BROWN
	self_modulate = Color.SLATE_GRAY

func deselect():
	self_modulate.a = 0.7
	self_modulate = Color.WHITE
	if get_index() == get_tree().get_root().get_node("OSSMSauce").active_path_index:
		$Label.self_modulate = Color.BURLYWOOD
	else:
		$Label.self_modulate = Color.WHITE
		$Label.self_modulate.a = 0.765
		$Icon.hide()
		$Animation.stop()
