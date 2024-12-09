@tool
extends EditorPlugin

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	# Add the new type with a name, a parent type, a script and an icon.
	add_custom_type('GPUNoiseTexture2D', 'Texture2DRD', preload('gpu_noise_texture_2d.gd'), preload('assets/NoiseTexture2D.svg'))
	add_custom_type('GPUNoiseTexture3D', 'Texture3DRD', preload('gpu_noise_texture_3d.gd'), preload('assets/NoiseTexture3D.svg'))

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	# Always remember to remove it from the engine when deactivated.
	remove_custom_type('GPUNoiseTexture2D')
	remove_custom_type('GPUNoiseTexture3D')
