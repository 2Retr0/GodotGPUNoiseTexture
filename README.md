# GPUNoiseTexture
A Godot engine plugin that introduces two new `Texture` resources: `GPUNoiseTexture2D` and `GPUNoiseTexture3D`.
These new texture types permit the creation of custom noise patterns via compute shaders.
Compute shaders implementations can be hotswapped in the editor for rapid prototyping.

This plugin originated as a quick tool for personal use, but was found to be significant enough
to be separated into its own repository. I hope it can be useful to some!

> [!IMPORTANT]
> Basic familiarity with compute shaders is a prerequisite to use this plugin! To learn more about what compute shaders
> are and how they are used in Godot, please take a look at [this tutorial](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html).

![cloud_demo](https://github.com/user-attachments/assets/80b1b370-f44f-4b7b-b9ca-4be5bbe15624)

## Usage
Both `GPUNoiseTexture2D` and `GPUNoiseTexture3D` require a compute shader which implements the
desired noise, writing the noise values to a texture. Noise parameters (e.g., frequency) are passed in as a push constant and roughly
match the parameters used in Godot's `FastNoiseLite` class. How/whether the parameters actually affect
the generated noise is entirely up to the shader implementation.

`GPUNoiseTexture`'s also require specifying the [`DataFormat`](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#enum-renderingdevice-dataformat)
of the generated noise texture. One useful consequence of this is that custom noise implementations
can write to multiple color channels in the output texture if desired.

> [!NOTE]
> For noise implementations written in GLSL, the [format qualifier](https://www.khronos.org/opengl/wiki/Image_Load_Store#Format_qualifiers)
> of the image uniform (`r8` is used in the examples below) should match the `DataFormat` specified in
> its respective `GPUNoiseTexture` resource. This is not a concern for implementations written in HLSL
> as format qualifiers are implicit in that language.

## Examples
Below are some generic examples for how one might implement a compute shader for a `GPUNoiseTexture`.
<ul>
<details open><summary><b>Example GLSL pseudocode for <code>GPUNoiseTexture2D</code></b></summary>

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r8, set = 0, binding = 0) uniform restrict writeonly image2D noise_image;

layout(push_constant) uniform PushConstants {
    bool invert;
    uint seed;
    float frequency;
    uint octaves;
    float lacunarity;
    float gain;
    float attenuation;
};

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);

    // Discard threads outside image dimensions.
    if (any(greaterThanEqual(id, imageSize(noise_image)))) return;

    float noise = get_noise(id, frequency, seed, octaves, lacunarity, gain);
    noise = mix(noise, 1.0 - noise, int(invert));
    noise = pow(noise, attenuation);
    imageStore(noise_image, id, vec4(vec3(noise), 1));
}
```

</details>

<details><summary><b>Example GLSL pseudocode for <code>GPUNoiseTexture3D</code></b></summary>

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(r8, set = 0, binding = 0) uniform restrict writeonly image3D noise_image;

layout(push_constant) uniform PushConstants {
    bool invert;
    uint seed;
    float frequency;
    uint octaves;
    float lacunarity;
    float gain;
    float attenuation;
};

void main() {
    ivec3 id = ivec3(gl_GlobalInvocationID);

    // Discard threads outside image dimensions.
    if (any(greaterThanEqual(id, imageSize(noise_image)))) return;

    float noise = get_noise(id, frequency, seed, octaves, lacunarity, gain);
    noise = mix(noise, 1.0 - noise, int(invert));
    noise = pow(noise, attenuation);
    imageStore(noise_image, id, vec4(vec3(noise), 1));
}
```

</details>
</ul>

For real-world implementations, please check out the samples included in the [`examples/`](/addons/gpu_noise_texture/examples/) directory.
