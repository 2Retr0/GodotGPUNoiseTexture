#[compute]
#version 450
/**
 * A compute shader implementation of tileable 3D 'alligator' noise.
 *
 * Copyright (c) 2024
 *      Side Effects Software Inc.  All rights reserved.
 *
 * Redistribution and use of Houdini Development Kit samples in source and
 * binary forms, with or without modification, are permitted provided that the
 * following conditions are met:
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. The name of Side Effects Software may not be used to endorse or
 *    promote products derived from this software without specific prior
 *    written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY SIDE EFFECTS SOFTWARE `AS IS' AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN
 * NO EVENT SHALL SIDE EFFECTS SOFTWARE BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
 * OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// Note: The image format of the GPUNoiseTexture resource should match the layout used here!
layout(r8, set = 0, binding = 0) uniform restrict writeonly image3D noise_image;

// The values of these parameters match that of the GPUNoiseTexture.
layout(push_constant) uniform PushConstants {
    bool invert;
    uint seed;
    float frequency;
    uint octaves;
    float lacunarity;
    float gain;
    float attenuation;
};

// Source: https://www.shadertoy.com/view/XlGcRh
vec3 hash(vec3 x) {
    uvec3 v = floatBitsToUint(x);
    // --- pcg3d Hash ---
    v = v * 1664525U + 1013904223U;
    v.x += v.y*v.z; v.y += v.z*v.x; v.z += v.x*v.y;
    v ^= v >> 16U;
    v.x += v.y*v.z; v.y += v.z*v.x; v.z += v.x*v.y;
    return uintBitsToFloat(v & 0x007FFFFFU | 0x3F800000U) - 1.0;
}

// Adapted from: https://www.shadertoy.com/view/4fX3D8
float alligator_noise(vec3 p, vec3 tiling, uint seed) {  
    float closest = 0.0;
    float second_closest = 0.0;
    for (int ix = -1; ix <= 1; ++ix)
    for (int iy = -1; iy <= 1; ++iy)
    for (int iz = -1; iz <= 1; ++iz) {
        vec3 offset = vec3(ix, iy, iz);
        vec3 cell = mod(floor(p) + offset, tiling);
        vec3 cell_center = hash(cell + float(seed)) + offset;
 
        float dist = distance(fract(p), cell_center);
        float closeness = hash(cell + float(seed)*2.0).r * smoothstep(0.0, 1.0, 1.0 - dist);
            
        if (closest < closeness) {
            second_closest = closest;
            closest = closeness;
        } else if (second_closest < closeness) {
            second_closest = closeness;
        }
    }
    return closest - second_closest;
}

float fbm(vec3 p, float frequency, uint seed, uint num_octaves, float lacunarity, float gain) {
    const ivec3 dims = imageSize(noise_image);
    
    float frequency_multiplier = 1.0;
    float amplitude = 1.0;
    float amplitude_sum = 0.0;
    float result = 0.0;
    
    for (uint octave = 0U; octave < num_octaves; ++octave) {
        vec3 sample_frequency = floor(frequency*dims*frequency_multiplier) / dims;

        seed += 1234U; // Change seed for each fractal octave (seed >= 1)
        result += alligator_noise(p*sample_frequency, dims*sample_frequency, seed) * amplitude;
        frequency_multiplier *= lacunarity;    
        amplitude_sum += amplitude;
        amplitude *= gain;
    }
    return result / amplitude_sum; // Normalize output to [0..1]
}

void main() {
    const ivec3 id = ivec3(gl_GlobalInvocationID);
    // Discard threads outside the noise image dimensions.
    if (any(greaterThanEqual(id, imageSize(noise_image)))) return;

    float noise = fbm(id, frequency, seed, octaves, lacunarity, gain);
    noise = mix(noise, 1.0 - noise, int(invert));
    noise = pow(noise, attenuation);
    imageStore(noise_image, id, vec4(vec3(noise),1));
}
