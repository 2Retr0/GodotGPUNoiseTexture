@tool
class_name GPUNoiseTexture2D extends Texture2DRD

## The maximum number of pixels the generated texture can have. This is to
## prevent accidentally allocating enormous amounts of memory.
const MAX_DIMENSION_SIZE := 256*256*256
const TEXTURE_TYPE := RenderingDevice.TEXTURE_TYPE_2D

#region Parameters
@export_category('Shader Configuration')
## A compute shader implementing the desired noise type. A typical implementation
## should roughly follow the corresponding GLSL pseudocode:
## [codeblock]
## layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
##
## layout([FORMAT], set = 0, binding = 0) uniform restrict writeonly image2D noise_image;
##
## layout(push_constant) uniform PushConstants {
##     bool invert;
##     uint seed;
##     float frequency;
##     uint octaves;
##     float lacunarity;
##     float gain;
##     float attenuation;
## };
##
## void main() {
##     ivec2 id = ivec2(gl_GlobalInvocationID.xy);
##     if (any(greaterThanEqual(id, imageSize(noise_image)))) return;
##
##     imageStore(noise_image, id, vec4(get_noise(...), 1));
## }
## [/codeblock]
@export var shader_file : RDShaderFile :
	set(value):
		shader_file = value
		if not shader_file: return
		shader_file.changed.connect(_init) # Rebuild pipelines whenever the shader file is edited externally.
		_init()

## The image format of the the generated texture. This should match the format used
## in the compute shader file.
@export var format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R8_UNORM :
	set(value): format = value; _init()

## Width of the generated texture (in pixels).
@export var width := 64 :
	set(value): if value*height*depth <= MAX_DIMENSION_SIZE and value > 0: width = value; _init()

## Height of the generated texture (in pixels).
@export var height := 64 :
	set(value): if width*value*depth <= MAX_DIMENSION_SIZE and value > 0: height = value; _init()

## Depth of the generated texture (in pixels).
@export var depth := 1 :
	set(value): if width*height*value <= MAX_DIMENSION_SIZE and value > 0: depth = value; _init()

## If [code]true[/code], inverts the noise texture. White becomes black, black becomes white.
@export var invert := false :
	set(value): invert = value; _generate()

@export_group('Noise Parameters')
## The random number seed for the noise.
@export_range(0, int(1e10)) var seed := 0 :
	set(value): seed = value; _generate()

## The frequency of the noise. Low frequency results in smooth noise while
## high frequency results in rougher, more granular noise.
@export_range(0.0, 1.0) var frequency := 0.1 :
	set(value): frequency = value; _generate()

## The number of noise layers that are sampled to get the final value for
## fractal noise types.
@export_range(1, 10) var octaves := 5 :
	set(value): octaves = value; _generate()

## Frequency multiplier between subsequent octaves. Increasing this value
## results in higher octaves producing noise with finer details and a rougher
## appearance.
@export_range(1.0, 1e10, 1e-4, 'hide_slider') var lacunarity := 2.0 :
	set(value): lacunarity = value; _generate()

## Determines the strength of each subsequent layer of noise in fractal noise.[br][br]
## A low value places more emphasis on the lower frequency base layers, while
## a high value puts more emphasis on the higher frequency layers.
@export_range(0.0, 1.0) var gain := 0.5 :
	set(value): gain = value; _generate()

## Modifies the gamma of the generated texture. A low value will brighten the,
## image while a high value will darken it.
@export_range(0.0, 1.0) var attenuation := 0.5 :
	set(value): attenuation = value; _generate()
#endregion

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var noise_image: RID

# A lazy way to hide the 'depth' property so I can copy-paste code from GPUNoiseTexture3D...
func _validate_property(property):
	if property.name == 'depth':
		property.usage = PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_READ_ONLY

## Called when this resource is constructed.
func _init() -> void:
	# FIXME: This function gets called FOUR times on initialization due to property setters!
	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_init_gpu)

func _init_gpu() -> void:
	if not shader_file: return

	_notification(NOTIFICATION_PREDELETE) # Free previous shader + dependents
	## --- Build Pipelines ---
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	if shader_spirv.compile_error_compute != '':
		printerr(shader_spirv.compile_error_compute.replace('\r', ''))
		return

	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	## --- Allocate Noise Texture ---
	var texture_format := RDTextureFormat.new()
	texture_format.format = format
	texture_format.width = width
	texture_format.height = height
	texture_format.depth = depth
	texture_format.texture_type = TEXTURE_TYPE
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	noise_image = rd.texture_create(texture_format, RDTextureView.new())
	_generate()
	self.texture_rd_rid = noise_image # This is what binds the texture to the Godot Resource...

func _generate() -> void:
	if not shader.is_valid(): return

	## --- Create Uniforms ---
	# Create a uniform set, this will be cached, the cache will be cleared if
	# the image dimensions are changed.
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(noise_image)
	var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [uniform])

	## --- Create Push Constant ---
	# Noise parameters are sent to the shader as a push constant.
	var push_constant := PackedByteArray(); push_constant.resize(32)
	push_constant.encode_u32(0, int(invert))
	push_constant.encode_u32(4, seed)
	push_constant.encode_float(8, frequency)
	push_constant.encode_u32(12, octaves)
	push_constant.encode_float(16, lacunarity)
	push_constant.encode_float(20, gain)
	push_constant.encode_float(24, 2.0*attenuation if attenuation < 0.5 else 0.5/(1.0-attenuation)) # [0..1] -> [0..INF]

	## --- Execute Compute Shader Workload ---
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	rd.compute_list_dispatch(compute_list, ceili(width/8.0), ceili(height/8.0), ceili(depth/8.0))
	rd.compute_list_end()

## System notifications, we want to react on the notification that
## alerts us we are about to be destroyed.
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# Freeing our shader will also free any dependents such as the pipeline!
		if shader.is_valid(): rd.free_rid(shader)
