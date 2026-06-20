#version 440

layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float angle;
    float tilt;
    float lightDirX;
    float lightDirY;
    float lightDirZ;
};

layout(binding = 1) uniform sampler2D moonTex;

const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

vec3 rotateX(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rotateY(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

vec2 sphereToUV(vec3 p) {
    float lon = atan(p.x, p.z);
    float lat = asin(clamp(p.y, -1.0, 1.0));
    return vec2(lon / TAU + 0.5, 0.5 - lat / PI);
}

void main() {
    vec2 uv = coord * 2.0 - 1.0;
    float r = length(uv);

    if (r > 1.0) {
        fragColor = vec4(0.0);
        return;
    }

    float z = sqrt(1.0 - r * r);
    vec3 N = vec3(uv.x, -uv.y, z);

    // Moon is tidally locked, so angle just rotates it slowly
    vec3 pMoon = rotateY(rotateX(N, tilt), angle * TAU);
    vec2 moonUV = sphereToUV(pMoon);
    vec3 color = texture(moonTex, moonUV).rgb;

    // Dynamic lighting based on the true 3D light vector
    vec3 L = normalize(vec3(lightDirX, lightDirY, lightDirZ));
    float NdotL = dot(N, L);

    // Moon has no atmosphere, so sharper terminator
    float diffuse = smoothstep(-0.02, 0.15, NdotL);

    // Very dark night side
    float ambient = 0.01;
    float lighting = ambient + (1.0 - ambient) * diffuse;

    // Dimmer, realistic sunlight (matches Earth)
    vec3 sunColor = vec3(0.85, 0.83, 0.8);
    color *= lighting * sunColor;

    // Anti-aliased edge
    float aa = smoothstep(1.0, 0.98, r);
    fragColor = vec4(color, aa * qt_Opacity);
}
